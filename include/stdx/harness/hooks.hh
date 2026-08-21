#pragma once

#include "stdx/types.hh"
#include "stdx/utility.hh"

extern "C" {
/// Per-test allocation tracking hooks called by test runner/fuzzer
auto harness_begin_test() -> void;
auto harness_end_test(const char* test_name) -> void;

/// Pre-harness hooks run before Catch2 entry point in tests
auto harness_pre_main(i32 argc, char** argv) -> void;

/// Post-harness hooks run after Catch2 entry point in tests
auto harness_post_main(i32 result) -> void;

/// Allocation tracking control
auto harness_pause_tracking() -> void;
auto harness_resume_tracking() -> void;
auto harness_is_tracking_active() -> bool;
}

namespace stdx {

struct [[nodiscard]] untracked_scope {
    untracked_scope() : previous_state_{harness_is_tracking_active()} {
        if (previous_state_) { harness_pause_tracking(); }
    }
    ~untracked_scope() {
        if (previous_state_) { harness_resume_tracking(); }
    }
    MAKE_PINNED(untracked_scope);

  private:
    bool previous_state_;
};

} // namespace stdx
