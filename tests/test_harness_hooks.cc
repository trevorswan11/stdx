#include <cstdlib>

#include <catch2/catch_test_macros.hpp>

#include "stdx/harness/hooks.hh"
#include "stdx/types.hh"

namespace { bool pre_main_hook_ran{false}; } // namespace

extern "C" auto harness_pre_main(i32 argc, char** argv) -> void {
    if (argc > 0 && argv) { pre_main_hook_ran = true; }
}

TEST_CASE("Harness pre and post hooks execution") { CHECK(pre_main_hook_ran); }
