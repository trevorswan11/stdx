#include <array>
#include <vector>

#include <catch2/catch_test_macros.hpp>

#include "stdx/arena.hh"
#include "stdx/types.hh"

namespace stdx::tests {

namespace {

constexpr usize MARKER{42};

struct large {
    usize                          marker{MARKER};
    std::array<i32, 4UZ * 1'024UZ> _;
};

} // namespace

TEST_CASE("Arena pointer stability") {
    arena               a;
    std::vector<large*> foos;

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
}

TEST_CASE("Arena alignment") {
    arena a;
    CHECK(*a.make<bool>(true));
    const auto p{a.make<void*>(nullptr)};
    CHECK(reinterpret_cast<uptr>(p.get()) % alignof(void*) == 0);
}

TEST_CASE("Arena array construction") {
    arena      a;
    const auto array{a.make_span<i32>(10)};
    for (const auto& i : array) { CHECK(i == 0); }
}

} // namespace stdx::tests
