// Small fixed-size worker pool for block I/O (CryFS import/delete fan-out).
// One shared instance; tasks submitted from inside a worker run inline so a
// nested fan-out can never deadlock the fixed-size pool.
#pragma once

#include <condition_variable>
#include <deque>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

namespace fv {

class Pool {
public:
    static Pool& shared() {
        static Pool p;
        return p;
    }

    static bool insideWorker() { return inWorker_(); }

    template <class F>
    auto submit(F&& f) -> std::future<decltype(f())> {
        using R = decltype(f());
        auto task = std::make_shared<std::packaged_task<R()>>(std::forward<F>(f));
        std::future<R> fut = task->get_future();
        if (inWorker_()) { (*task)(); return fut; }   // never queue behind ourselves
        {
            std::lock_guard<std::mutex> g(mu_);
            q_.emplace_back([task] { (*task)(); });
        }
        cv_.notify_one();
        return fut;
    }

private:
    Pool() {
        unsigned hw = std::thread::hardware_concurrency();
        unsigned n = hw < 4 ? 4 : (hw > 8 ? 8 : hw);
        for (unsigned i = 0; i < n; i++)
            workers_.emplace_back([this] { inWorker_() = true; run(); });
    }
    ~Pool() {
        { std::lock_guard<std::mutex> g(mu_); stop_ = true; }
        cv_.notify_all();
        for (auto& t : workers_) if (t.joinable()) t.join();
    }
    static bool& inWorker_() { static thread_local bool v = false; return v; }
    void run() {
        for (;;) {
            std::function<void()> job;
            {
                std::unique_lock<std::mutex> g(mu_);
                cv_.wait(g, [&] { return stop_ || !q_.empty(); });
                if (stop_ && q_.empty()) return;
                job = std::move(q_.front());
                q_.pop_front();
            }
            job();
        }
    }
    std::mutex mu_;
    std::condition_variable cv_;
    std::deque<std::function<void()>> q_;
    std::vector<std::thread> workers_;
    bool stop_ = false;
};

}  // namespace fv
