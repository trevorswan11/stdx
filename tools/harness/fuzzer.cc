#include <string>

#include <absl/debugging/failure_signal_handler.h>
#include <absl/debugging/symbolize.h>
#include <fmt/format.h>
#include <fuzztest/fuzztest.h>
#include <fuzztest/init_fuzztest.h>
#include <gtest/gtest.h>
#include <stdx/profiler.hh>
#include <stdx/types.hh>

#include "hooks.hh"

namespace {

class alloc_leak_listener : public testing::EmptyTestEventListener {
  public:
    auto OnTestStart(const testing::TestInfo& info) -> void override {
        name_ = fmt::format("{}/{}", info.test_suite_name(), info.name());
        harness_begin_test();
    }
    auto OnTestEnd(const testing::TestInfo&) -> void override { harness_end_test(name_.c_str()); }

  private:
    std::string name_;
};

} // namespace

#ifdef STDX_PROFILE
#    include <stdx/memory.hh>

namespace {

class profile_timer_listener : public testing::EmptyTestEventListener {
  public:
    auto OnTestStart(const testing::TestInfo& info) -> void override {
        name_  = fmt::format("{}/{}", info.test_suite_name(), info.name());
        timer_ = stdx::make_nullable_box<stdx::timer>(name_.c_str());
    }

    auto OnTestEnd(const testing::TestInfo&) -> void override { timer_.reset(); }

  private:
    std::string                     name_;
    stdx::nullable_box<stdx::timer> timer_;
};

} // namespace
#endif

extern "C" {
auto launch(i32 argc, char** argv) -> i32 {
    stdx::profiler p{argv[0]};
    absl::InitializeSymbolizer(argv[0]);
    absl::FailureSignalHandlerOptions options;
    options.call_previous_handler = true;
    absl::InstallFailureSignalHandler(options);

    testing::InitGoogleTest(&argc, argv);

    auto& listeners = testing::UnitTest::GetInstance()->listeners();
    listeners.Append(new alloc_leak_listener());
#ifdef STDX_PROFILE
    listeners.Append(new profile_timer_listener());
#endif

    fuzztest::ParseAbslFlags(argc, argv);
    fuzztest::InitFuzzTest(&argc, &argv);
    return RUN_ALL_TESTS();
}
}
