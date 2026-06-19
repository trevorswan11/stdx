#pragma once

#include "stdx/types.hh"

namespace stdx::tests::helpers {

enum class mock_enum : u8 {
    A,
    B,
    C,
    D,
};

enum class mock_positive_enum : u8 {
    A = 1,
    B,
    C,
    D,
};

enum class mock_negative_enum : i8 {
    A = -1,
    B,
    C,
    D,
};

enum class non_monotonic_enum : u8 {
    A = 0,
    B = 10,
    C = 25,
    D = 23,
};

} // namespace stdx::tests::helpers
