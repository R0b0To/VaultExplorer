// Small helpers shared by the three session implementations.
#pragma once

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <string>

#include "fv_common.h"

namespace fv {

// Tracks in-flight public calls so close() can wait for them before wiping
// keys: every public Vault method holds an Op for its duration.
//
// Deliberately a counter, not a shared_mutex. An Op never blocks: it either
// registers or, once the vault is closing, fails fast. That matters because a
// call may sit inside another vault's call (a copy between two vaults pulls
// from the source while the destination's importStream runs): with a
// reader-writer lock, a close() waiting on one vault makes new readers queue
// behind it on writer-preferring implementations (Windows' SRWLOCK, bionic), and
// two opposite-direction copies plus a close of both vaults can then deadlock.
// The same goes for a call that re-enters its own vault.
class Lifecycle {
public:
    class Op {
    public:
        explicit Op(Lifecycle& l) : l_(l) {
            std::lock_guard<std::mutex> g(l_.mu_);
            if (l_.closed_.load()) throw Error(Err::Closed, "vault is closed");
            ++l_.inflight_;
        }
        ~Op() {
            std::lock_guard<std::mutex> g(l_.mu_);
            if (--l_.inflight_ == 0 && l_.closed_.load()) l_.cv_.notify_all();
        }
        Op(const Op&) = delete;
        Op& operator=(const Op&) = delete;
    private:
        Lifecycle& l_;
    };
    bool isClosed() const { return closed_.load(); }
    // Returns true for the one call that actually performs the close.
    bool markClosed() {
        std::lock_guard<std::mutex> g(mu_);
        return !closed_.exchange(true);
    }
    // Blocks until no Op is running (new ones fail fast once markClosed ran).
    void drain() {
        std::unique_lock<std::mutex> g(mu_);
        cv_.wait(g, [&] { return inflight_ == 0; });
    }
private:
    std::atomic<bool> closed_{false};
    std::mutex mu_;                     // guards inflight_ only; never held across a call
    std::condition_variable cv_;
    int inflight_ = 0;
};

inline bool startsWith(const std::string& s, const char* p) { return s.rfind(p, 0) == 0; }
inline bool endsWith(const std::string& s, const std::string& suf) {
    return s.size() >= suf.size() && s.compare(s.size() - suf.size(), suf.size(), suf) == 0;
}

}  // namespace fv
