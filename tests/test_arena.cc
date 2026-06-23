#include <algorithm>
#include <array>
#include <string>
#include <utility>
#include <vector>

#include <catch2/catch_test_macros.hpp>

#include "helpers/raii_tracker.hh"
#include "stdx/arena.hh"
#include "stdx/memory.hh"
#include "stdx/types.hh"

namespace stdx::tests {

namespace {

constexpr usize MARKER{42};

using namespace size_literals;
struct large {
    usize                                      marker{MARKER};
    std::array<i32, static_cast<usize>(4_KiB)> _;
};

struct beefy {
    std::vector<i32> nums{1, 2, 3, 4, 5, 6, 7, 8, 9};
};

} // namespace

TEST_CASE("Arena pointer stability") {
    arena               a;
    std::vector<large*> foos;
new int;
    // First use
    {
        for (usize i{0}; i < 100; ++i) { foos.emplace_back(a.make<large>().get()); }
        for (const auto& foo : foos) { CHECK(foo->marker == MARKER); }
    }

    // Reset and reuse
    {
        a.reset();
        foos.clear();
        for (usize i{0}; i < 100; ++i) { foos.emplace_back(a.make<large>().get()); }
        for (const auto& foo : foos) { CHECK(foo->marker == MARKER); }
    }

    // Clear and reuse
    {
        a.clear();
        foos.clear();
        for (usize i{0}; i < 100; ++i) { foos.emplace_back(a.make<large>().get()); }
        for (const auto& foo : foos) { CHECK(foo->marker == MARKER); }
    }
}

TEST_CASE("Arena alignment") {
    arena a;
    CHECK(*a.make<bool>(true));
    const auto p{a.make<void*>(nullptr)};
    CHECK(reinterpret_cast<uptr>(p.get()) % alignof(void*) == 0);
}

TEST_CASE("Arena array construction") {
    using namespace size_literals;
    arena<static_cast<usize>(32_KiB)> a;
    const auto                        array{a.make_span<i32>(10)};
    for (const auto& i : array) { CHECK(i == 0); }
}

TEST_CASE("Non-trivial arena types") {
    arena a;

    const auto work = [&] -> void {
        const auto str{a.make<std::string>("10")};
        CHECK(*str == "10");

        const auto array{a.make_span<beefy>(10)};
        for (const auto& b : array) {
            CHECK(std::ranges::equal(b.nums, std::array{1, 2, 3, 4, 5, 6, 7, 8, 9}));
        }

        CHECK(*a.make<bool>(true));
    };

    work();

    a.reset();
    work();

    a.clear();
    work();
}

TEST_CASE("Arena move construction transfers ownership") {
    arena               src;
    std::vector<large*> foos;

    // Move should maintain pointer stability
    for (usize i{0}; i < 100; ++i) { foos.emplace_back(src.make<large>().get()); }
    for (const auto& foo : foos) { CHECK(foo->marker == MARKER); }
    arena dst{std::move(src)};
    for (const auto& foo : foos) { CHECK(foo->marker == MARKER); }

    // Arena should both be useable
    auto* fresh{src.make<large>().get()};
    CHECK(fresh->marker == MARKER);

    auto* dst_fresh{dst.make<large>().get()};
    CHECK(dst_fresh->marker == MARKER);
}

TEST_CASE("Arena move assignment into an empty arena") {
    arena src;
    auto* foo{src.make<large>().get()};
    CHECK(foo->marker == MARKER);

    arena dst;
    dst = std::move(src);
    CHECK(foo->marker == MARKER);

    auto* fresh{src.make<large>().get()};
    CHECK(fresh->marker == MARKER);
    auto* dst_fresh{dst.make<large>().get()};
    CHECK(dst_fresh->marker == MARKER);
}

TEST_CASE("Arena move assignment into non-empty arena") {
    using tracker = helpers::raii_tracker;
    tracker::reset();

    arena dst;
    CHECK(dst.make<tracker>(1));
    CHECK(dst.make<tracker>(2));
    CHECK(tracker::live_count == 2);

    arena src;
    CHECK(src.make<tracker>(3).get());
    CHECK(tracker::live_count == 3);

    dst = std::move(src);
    CHECK(tracker::live_count == 1);
    CHECK(tracker::destruct_count == 2);

    CHECK(dst.make<tracker>(4).get());
    CHECK(tracker::live_count == 2);

    dst.clear();
    CHECK(tracker::live_count == 0);
}

} // namespace stdx::tests
