#pragma once

#include <chrono>
#include <string_view>

namespace stdx {

// Opens a Chrome-trace JSON profiling session next to the given binary.
struct profiler {
    explicit profiler(std::string_view binary_path);
    ~profiler();

    profiler(const profiler&)                        = delete;
    auto operator=(const profiler&) -> profiler&     = delete;
    profiler(profiler&&) noexcept                    = delete;
    auto operator=(profiler&&) noexcept -> profiler& = delete;
};

// Records a named time range.
class timer {
  public:
    explicit timer(const char* name);
    ~timer();

    timer(const timer&)                        = delete;
    auto operator=(const timer&) -> timer&     = delete;
    timer(timer&&) noexcept                    = delete;
    auto operator=(timer&&) noexcept -> timer& = delete;

  private:
    [[maybe_unused]] const char*                                        name_;
    [[maybe_unused]] std::chrono::time_point<std::chrono::steady_clock> start_;
};

} // namespace stdx

#define PROFILE_CONCAT_INNER(a, b) a##b
#define PROFILE_CONCAT(a, b) PROFILE_CONCAT_INNER(a, b)

#define PROFILE_SCOPE(name) \
    ::stdx::timer PROFILE_CONCAT(timer, __LINE__) { name }
#define PROFILE_FUNCTION() PROFILE_SCOPE(__PRETTY_FUNCTION__)
