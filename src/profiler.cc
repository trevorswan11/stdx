#include "stdx/profiler.hh"

#ifdef STDX_PROFILE
#    include <chrono>
#    include <cstdint>
#    include <filesystem>
#    include <fstream>
#    include <iterator>
#    include <memory>
#    include <mutex>
#    include <ratio>
#    include <string_view>
#    include <thread>

#    include <fmt/base.h>
#    include <fmt/format.h>
#    include <fmt/ostream.h>
#    include <fmt/std.h>

#    include "stdx/assert.hh"
#    include "stdx/fixed/vector.hh"
#    include "stdx/json.hh"
#    include "stdx/memory.hh"
#    include "stdx/option.hh"
#    include "stdx/types.hh"

namespace stdx {

namespace chrono = std::chrono;
using namespace size_literals;

namespace {

template <typename T> using micros = chrono::duration<T, std::micro>;

struct session_deleter {
    auto operator()(std::ofstream* ostream) -> void {
        if (!ostream) { return; }
        fmt::print(*ostream, "]}}");
        delete ostream;
    }
};

constinit nullable_box<std::ofstream, session_deleter> session;
constinit std::mutex                                   mutex;

class buffer {
  public:
    static constexpr usize BUF_SIZE{64_KiB};

  public:
    constexpr buffer() = default;
    ~buffer()          = default;

    buffer(const buffer&)                        = delete;
    auto operator=(const buffer&) -> buffer&     = delete;
    buffer(buffer&&) noexcept                    = delete;
    auto operator=(buffer&&) noexcept -> buffer& = delete;

    // Must be called with the global mutex held
    auto flush() -> void {
        if (buf_.empty() || !session || !session->is_open()) { return; }
        fmt::print(*session, "{}", std::string_view{buf_.data(), buf_.size()});
        buf_.clear();
    }

  private:
    fixed::vector<char, BUF_SIZE> buf_;

    friend struct buffer_manager;
};

struct buffer_manager {
  public:
    static constexpr usize HEADROOM{buffer::BUF_SIZE / 2};
    static constexpr usize MAX_BUFFERS{1_KiB};
    static inline constinit fixed::vector<option<buffer&>, MAX_BUFFERS> buffers;

  public:
    buffer data;

    buffer_manager() {
        std::scoped_lock lock{mutex};

        // Reuse empty slots to prevent buffer overflows
        for (auto& buf : buffers) {
            if (!buf) {
                buf.emplace(data);
                return;
            }
        }

        ASSERT(buffers.size() < buffers.capacity(), "Too many threads spawned");
        buffers.emplace_back(data);
    }

    ~buffer_manager() {
        std::scoped_lock lock{mutex};
        data.flush();

        // Setting to nullptr is more efficient than erase since it avoids shift
        for (auto& buf : buffers) {
            if (buf == &data) {
                buf.reset();
                return;
            }
        }
    }

    buffer_manager(const buffer_manager&)                        = delete;
    auto operator=(const buffer_manager&) -> buffer_manager&     = delete;
    buffer_manager(buffer_manager&&) noexcept                    = delete;
    auto operator=(buffer_manager&&) noexcept -> buffer_manager& = delete;

    // Gets a back inserter for libfmt to write out to
    [[nodiscard]] auto out() noexcept -> auto { return std::back_inserter(data.buf_); }

    // Flushes the buffer if full, managing the global mutex accordingly
    auto ensure_capacity() -> void {
        if (data.buf_.size() + HEADROOM >= data.buf_.capacity()) {
            std::scoped_lock lock{mutex};
            data.flush();
        }
    }
};

auto write_scope(std::string_view     name,
                 micros<double>       start,
                 micros<std::int64_t> elapsed,
                 std::thread::id      tid) -> void {
    ASSERT(session && session->is_open(), "Writing cannot be done prior to initialization");

    thread_local buffer_manager manager;
    manager.ensure_capacity();

    fmt::format_to(
        manager.out(),
        R"(,{{"cat":"function","dur":{},"name":"{}","ph":"X","pid":0,"tid":"{}","ts":{:.3f}}})",
        elapsed.count(),
        json::sanitized_string{name},
        tid,
        start.count());
}

[[nodiscard]] constexpr auto to_int_micros(auto clock) -> auto {
    return chrono::time_point_cast<micros<std::int64_t>>(clock).time_since_epoch();
}

} // namespace

profiler::profiler(std::string_view path) {
    std::filesystem::path json{path};
    json.replace_filename(fmt::format("{}-profile.json", json.stem()));

    std::scoped_lock lock{mutex};
    session.reset(new std::ofstream{json});
    ASSERT(session->is_open(), "Profiler could not open output path");
    fmt::print(*session, R"({{"otherData": {{}},"traceEvents":[{{}})");
}

profiler::~profiler() {
    std::scoped_lock lock{mutex};
    for (auto& buf : buffer_manager::buffers) {
        if (buf) { buf->flush(); }
    }
    buffer_manager::buffers.clear();
    session.reset();
}

timer::timer(const char* name) : name_{name}, start_{chrono::steady_clock::now()} {}

timer::~timer() {
    auto           end{to_int_micros(chrono::steady_clock::now())};
    micros<double> high_res_start{start_.time_since_epoch()};
    auto           start{to_int_micros(start_)};
    auto           elapsed{end - start};
    write_scope(name_, high_res_start, elapsed, std::this_thread::get_id());
}

} // namespace stdx
#else
namespace stdx {

profiler::profiler(std::string_view) {}
profiler::~profiler() = default;

timer::timer(const char*) : name_{nullptr} {}
timer::~timer() = default;

} // namespace stdx
#endif
