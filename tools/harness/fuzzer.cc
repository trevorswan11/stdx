#include <catch2/catch_session.hpp>

#include <stdx/profiler.hh>
#include <stdx/types.hh>

extern "C" {
auto launch(i32 argc, char** argv) -> i32 {
    stdx::profiler p{argv[0]};
    return Catch::Session().run(argc, argv);
}
}
