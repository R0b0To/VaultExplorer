// Small helpers shared by the three session implementations.
#pragma once

#include <atomic>
#include <shared_mutex>
#include <string>

#include "fv_common.h"

namespace fv {

// Tracks in-flight public calls so close() can wait for them before wiping
// keys: every public Vault method holds an Op for its duration.
class Lifecycle {
public:
    class Op {
    public:
        explicit Op(Lifecycle& l) : lk_(l.mu_) {
            if (l.closed_.load()) throw Error(Err::Closed, "vault is closed");
        }
    private:
        std::shared_lock<std::shared_mutex> lk_;
    };
    bool isClosed() const { return closed_.load(); }
    // Returns true for the one call that actually performs the close.
    bool markClosed() { return !closed_.exchange(true); }
    // Blocks until no Op is running (new ones fail fast once markClosed ran).
    void drain() { std::unique_lock<std::shared_mutex> g(mu_); }
private:
    std::atomic<bool> closed_{false};
    std::shared_mutex mu_;
};

inline bool startsWith(const std::string& s, const char* p) { return s.rfind(p, 0) == 0; }
inline bool endsWith(const std::string& s, const std::string& suf) {
    return s.size() >= suf.size() && s.compare(s.size() - suf.size(), suf.size(), suf) == 0;
}

}  // namespace fv
