#ifdef STDX_PROFILE
#    include <string>

#    include <catch2/catch_test_case_info.hpp>
#    include <catch2/catch_test_spec.hpp>
#    include <catch2/interfaces/catch_interfaces_reporter.hpp>
#    include <catch2/reporters/catch_reporter_event_listener.hpp>
#    include <catch2/reporters/catch_reporter_registrars.hpp>
#    include <fmt/format.h>

#    include <stdx/memory.hh>
#    include <stdx/profiler.hh>
namespace {

// https://github.com/catchorg/Catch2/blob/devel/docs/event-listeners.md
class test_timer_listener : public Catch::EventListenerBase {
  public:
    using EventListenerBase::EventListenerBase;

    auto testCaseStarting(const Catch::TestCaseInfo& info) -> void override {
        auto line_info{info.lineInfo};
        name_  = fmt::format(R"({}: "{}" (line {}))", line_info.file, info.name, line_info.line);
        timer_ = stdx::make_nullable_box<stdx::timer>(name_.c_str());
    }

    auto testCaseEnded(const Catch::TestCaseStats&) -> void override { timer_.reset(); }

  private:
    std::string                     name_;
    stdx::nullable_box<stdx::timer> timer_;
};

} // namespace

CATCH_REGISTER_LISTENER(test_timer_listener)
#endif
