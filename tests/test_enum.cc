#include <array>

#include <catch2/catch_test_macros.hpp>

#include "helpers/enum.hh"
#include "stdx/enum.hh"
#include "stdx/types.hh"

namespace stdx::tests {

using helpers::mock_enum;
using helpers::mock_negative_enum;
using helpers::mock_positive_enum;
using helpers::non_monotonic_enum;

TEST_CASE("Enum min/max calculations") {
    STATIC_CHECK(enum_min_underlying<mock_enum>() == 0);
    STATIC_CHECK(enum_max_underlying<mock_enum>() == 3);

    STATIC_CHECK(enum_min_underlying<mock_positive_enum>() == 1);
    STATIC_CHECK(enum_max_underlying<mock_positive_enum>() == 4);

    STATIC_CHECK(enum_min_underlying<mock_negative_enum>() == -1);
    STATIC_CHECK(enum_max_underlying<mock_negative_enum>() == 2);

    STATIC_CHECK(enum_min_underlying<non_monotonic_enum>() == 0);
    STATIC_CHECK(enum_max_underlying<non_monotonic_enum>() == 25);
}

TEST_CASE("Monotonically increasing enum range") {
    for (usize i{0}; const auto v : enum_range<mock_enum::A, mock_enum::D>()) {
        CHECK(v == static_cast<mock_enum>(i++));
    }

    for (usize i{0}; const auto v : enum_range<mock_enum>()) {
        CHECK(v == static_cast<mock_enum>(i++));
    }
}

TEST_CASE("Non-monotonic enum range") {
    constexpr std::array expected{
        non_monotonic_enum::A,
        non_monotonic_enum::B,
        non_monotonic_enum::D,
        non_monotonic_enum::C,
    };

    for (usize i{0}; const auto v : enum_range<non_monotonic_enum::A, non_monotonic_enum::D>()) {
        CHECK(v == expected[i++]);
    }
    for (usize i{0}; const auto v : enum_range<non_monotonic_enum>()) { CHECK(v == expected[i++]); }
}

} // namespace stdx::tests
