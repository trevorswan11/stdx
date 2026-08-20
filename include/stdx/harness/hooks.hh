#pragma once

#include <stdx/types.hh>

extern "C" {
/// Per-test allocation tracking hooks called by test runner/fuzzer
auto harness_begin_test() -> void;
auto harness_end_test(const char* test_name) -> void;

/// Pre-harness hooks run before Catch2 entry point in tests
auto harness_pre_session() -> void;
auto harness_pre_run() -> void;
auto pre_harness_hook() -> void;
auto harness_pre_main(i32 argc, char** argv) -> void;

/// Post-harness hooks run after Catch2 entry point in tests
auto harness_post_session() -> void;
auto harness_post_run() -> void;
auto post_harness_hook() -> void;
auto harness_post_main(i32 result) -> void;
}
