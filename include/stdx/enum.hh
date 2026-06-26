#pragma once

#include <array>
#include <concepts>

#include <magic_enum/magic_enum.hpp>

#include "stdx/type_traits.hh"
#include "stdx/types.hh"

namespace stdx {

using magic_enum::enum_value;

// Returns the minimum value of the present enumerations as the value
template <Enum E> consteval auto enum_min_value() { return enum_value<E>(0); }

// Returns the minimum value of the present enumerations as the underlying value
template <Enum E> consteval auto enum_min_underlying() {
    return magic_enum::enum_integer(enum_min_value<E>());
}

// Returns the maximum value of the present enumerations as the value
template <Enum E> consteval auto enum_max_value() {
    return enum_value<E>(magic_enum::enum_count<E>() - 1);
}

// Returns the maximum value of the present enumerations as the underlying value
template <Enum E> consteval auto enum_max_underlying() {
    return magic_enum::enum_integer(enum_max_value<E>());
}

// Requires that the enum is in an exclusively bounded range of magic enum bounds
//
// This prevents possible bugs and should be fixed by adjusting defines in `build.zig`
template <typename E>
concept BoundedEnum = Enum<E> && requires {
    enum_min_underlying<E>() > MAGIC_ENUM_RANGE_MIN &&
        enum_max_underlying<E>() < MAGIC_ENUM_RANGE_MAX;
};

// Returns an inclusive range of enum values. Requires `lower < higher`
template <auto Lower, auto Upper>
    requires(BoundedEnum<decltype(Lower)> && std::same_as<decltype(Lower), decltype(Upper)>)
consteval auto enum_range() noexcept {
    using enum_type = decltype(Lower);
    constexpr auto opt_low{magic_enum::enum_index<enum_type>(Lower)};
    constexpr auto opt_high{magic_enum::enum_index<enum_type>(Upper)};
    static_assert(opt_low && opt_high, "Bounds must be valid enumerations");

    constexpr usize low_idx{*opt_low};
    constexpr usize high_idx{*opt_high};
    static_assert(high_idx >= low_idx, "Range must be strictly increasing");

    // The range is inclusive to circumvent weird indexing
    constexpr usize              count{high_idx - low_idx + 1};
    std::array<enum_type, count> range;
    for (usize i{0}; i < range.size(); ++i) { range[i] = enum_value<enum_type>(low_idx + i); }
    return range;
}

// Returns an array of all possible enum values
template <BoundedEnum E> consteval auto enum_range() noexcept {
    return enum_range<enum_min_value<E>(), enum_max_value<E>()>();
}

// NOLINTBEGIN
#define MAKE_ENUM_OPERATORS(EnumType)                                                    \
    constexpr auto operator|(EnumType lhs, EnumType rhs)->EnumType {                     \
        return static_cast<EnumType>(std::to_underlying(lhs) | std::to_underlying(rhs)); \
    }                                                                                    \
                                                                                         \
    constexpr auto operator&(EnumType lhs, EnumType rhs)->EnumType {                     \
        return static_cast<EnumType>(std::to_underlying(lhs) & std::to_underlying(rhs)); \
    }                                                                                    \
                                                                                         \
    constexpr auto operator^(EnumType lhs, EnumType rhs)->EnumType {                     \
        return static_cast<EnumType>(std::to_underlying(lhs) ^ std::to_underlying(rhs)); \
    }                                                                                    \
                                                                                         \
    constexpr auto operator|=(EnumType& lhs, EnumType rhs)->EnumType& {                  \
        lhs = lhs | rhs;                                                                 \
        return lhs;                                                                      \
    }                                                                                    \
                                                                                         \
    constexpr auto operator~(EnumType op)->EnumType {                                    \
        return static_cast<EnumType>(~std::to_underlying(op));                           \
    }
// NOLINTEND

} // namespace stdx
