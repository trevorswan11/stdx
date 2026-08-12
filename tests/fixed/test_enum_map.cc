#include <algorithm>
#include <iterator>

#include <catch2/catch_test_macros.hpp>

#include "helpers/enum.hh"
#include "stdx/fixed/enum_map.hh"
#include "stdx/option.hh"
#include "stdx/types.hh"
#include "stdx/utility.hh"

namespace stdx::tests {

using helpers::mock_enum;
using helpers::mock_negative_enum;
using helpers::mock_positive_enum;
using helpers::non_monotonic_enum;

TEST_CASE("Standard enum map") {
    fixed::enum_map<mock_enum, option<int>> map;
    CHECK(map.size() == 4);
    for (const auto& item : map) { CHECK_FALSE(item); }

    map[mock_enum::A] = 4;
    for (const auto& item : map) {
        if (item) { CHECK(item == 4); }
    }

    SECTION("Automatic optional getting") {
        const auto present_opt{map.get_opt(mock_enum::A)};
        CHECK(present_opt);
        CHECK(present_opt == 4);

        const auto missing_opt{map.get_opt(mock_enum::B)};
        CHECK_FALSE(missing_opt);
    }
}

TEST_CASE("Positive enum map") {
    fixed::enum_map<mock_positive_enum, usize*> map;
    CHECK(map.size() == 4);
    for (const auto& item : map) { CHECK(item == nullptr); }

    usize v{1};
    map[mock_positive_enum::A] = &v;
    for (const auto& item : map) {
        if (item != nullptr) { CHECK(*item == 1); }
    }

    SECTION("Automatic optional getting") {
        const auto present_opt{map.get_opt(mock_positive_enum::A)};
        CHECK(**present_opt == 1);

        const auto missing_opt{map.get_opt(mock_positive_enum::B)};
        CHECK_FALSE(missing_opt);
    }
}

TEST_CASE("Negative enum map") {
    fixed::enum_map<mock_negative_enum, bool> map{true};
    CHECK(map.size() == 4);
    for (const auto& item : map) { CHECK(item); }

    map[mock_negative_enum::A] = false;
    CHECK_FALSE(map[mock_negative_enum::A]);
    CHECK(map[mock_negative_enum::B]);
    CHECK(map[mock_negative_enum::C]);
    CHECK(map[mock_negative_enum::D]);
}

TEST_CASE("Non-monotonic enum map") {
    fixed::enum_map<non_monotonic_enum, usize> map{0xDEADBEEF};
    CHECK(map.size() == 4);

    map[non_monotonic_enum::D] = 0xC0FFEE;
    CHECK(map[non_monotonic_enum::A] == 0xDEADBEEF);
    CHECK(map[non_monotonic_enum::B] == 0xDEADBEEF);
    CHECK(map[non_monotonic_enum::C] == 0xDEADBEEF);
    CHECK(map[non_monotonic_enum::D] == 0xC0FFEE);
}

TEST_CASE("Move-only type enum map") {
    struct move_only_type {
        i32 value{0};

        move_only_type() = default;
        explicit move_only_type(i32 v) : value{v} {}
        ~move_only_type() = default;
        MAKE_MOVE_ONLY(move_only_type);
    };

    SECTION("Default construction with move-only value") {
        fixed::enum_map<mock_enum, move_only_type> map;
        CHECK(map.size() == 4);
        for (const auto& item : map) { CHECK(item.value == 0); }
    }

    SECTION("Default construction with move-only option") {
        fixed::enum_map<mock_enum, option<move_only_type>> map;
        CHECK(map.size() == 4);
        for (const auto& item : map) { CHECK_FALSE(item); }

        map[mock_enum::A].emplace(100);
        CHECK(map[mock_enum::A]);
        CHECK(map[mock_enum::A]->value == 100);
        CHECK_FALSE(map[mock_enum::B]);
    }

    SECTION("Move construction and assignment") {
        fixed::enum_map<mock_enum, option<move_only_type>> map;
        map[mock_enum::B].emplace(42);

        auto moved_map{std::move(map)};
        CHECK(moved_map[mock_enum::B]);
        CHECK(moved_map[mock_enum::B]->value == 42);
        CHECK_FALSE(moved_map[mock_enum::A]);
    }
}

TEST_CASE("fixed::enum_map ranges compatibility") {
    using enum_map = fixed::enum_map<non_monotonic_enum, usize>;
    STATIC_REQUIRE(std::forward_iterator<enum_map::iterator>);
    STATIC_REQUIRE(std::forward_iterator<enum_map::const_iterator>);

    constexpr enum_map map{0xDEADBEEF};
    std::ranges::for_each(map, [](usize value) -> void { CHECK(value == 0xDEADBEEF); });
}

} // namespace stdx::tests
