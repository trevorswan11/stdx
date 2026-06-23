#include <absl/debugging/failure_signal_handler.h>
#include <absl/debugging/symbolize.h>
#include <fuzztest/fuzztest.h>
#include <fuzztest/init_fuzztest.h>
#include <gtest/gtest.h>

#include <stdx/profiler.hh>
#include <stdx/types.hh>

extern "C" {
auto launch(i32 argc, char** argv) -> i32 {
    stdx::profiler p{argv[0]};
    absl::InitializeSymbolizer(argv[0]);
    absl::FailureSignalHandlerOptions options;
    options.call_previous_handler = true;
    absl::InstallFailureSignalHandler(options);
    testing::InitGoogleTest(&argc, argv);

    fuzztest::ParseAbslFlags(argc, argv);
    fuzztest::InitFuzzTest(&argc, &argv);
    return RUN_ALL_TESTS();
}
}
