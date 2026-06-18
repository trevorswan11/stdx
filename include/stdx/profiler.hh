#pragma once

#include <chrono>
#include <string_view>

namespace stdx {

// Opens a Chrome-trace JSON profiling session next to the given binary.
struct Profiler {
    explicit Profiler(std::string_view binary_path);
    ~Profiler();

    Profiler(const Profiler&)                        = delete;
    auto operator=(const Profiler&) -> Profiler&     = delete;
    Profiler(Profiler&&) noexcept                    = delete;
    auto operator=(Profiler&&) noexcept -> Profiler& = delete;
};

// Records a named time range.
class Timer {
  public:
    explicit Timer(const char* name);
    ~Timer();

    Timer(const Timer&)                        = delete;
    auto operator=(const Timer&) -> Timer&     = delete;
    Timer(Timer&&) noexcept                    = delete;
    auto operator=(Timer&&) noexcept -> Timer& = delete;

  private:
    [[maybe_unused]] const char*                                        name_;
    [[maybe_unused]] std::chrono::time_point<std::chrono::steady_clock> start_;
};

} // namespace stdx

#define PROFILE_CONCAT_INNER(a, b) a##b
#define PROFILE_CONCAT(a, b) PROFILE_CONCAT_INNER(a, b)

#define PROFILE_SCOPE(name) \
    ::stdx::Timer PROFILE_CONCAT(timer, __LINE__) { name }
#define PROFILE_FUNCTION() PROFILE_SCOPE(__PRETTY_FUNCTION__)
