#pragma once

#include "stdx/types.hh"

namespace stdx::tests::helpers {

// Non-thread-safe tracker for memory-critical testing
struct raii_tracker {
    static inline i32 live_count{0};
    static inline i32 copy_count{0};
    static inline i32 move_count{0};
    static inline i32 destruct_count{0};

    static auto reset() -> void { live_count = copy_count = move_count = destruct_count = 0; }

    // Dummy variable for constructor to prevent default construction
    raii_tracker(i32) { live_count++; }
    ~raii_tracker() {
        live_count--;
        destruct_count++;
    }

    raii_tracker(const raii_tracker&) {
        live_count++;
        copy_count++;
    }

    auto operator=(const raii_tracker&) -> raii_tracker& {
        copy_count++;
        return *this;
    }

    raii_tracker(raii_tracker&&) noexcept {
        live_count++;
        move_count++;
    }

    auto operator=(raii_tracker&&) noexcept -> raii_tracker& {
        live_count++;
        move_count++;
        return *this;
    }
};

} // namespace stdx::tests::helpers
