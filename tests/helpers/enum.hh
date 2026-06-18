#pragma once

#include "stdx/types.hh"

namespace stdx::tests::helpers {

enum class MockEnum : u8 {
    A,
    B,
    C,
    D,
};

enum class MockPositiveEnum : u8 {
    A = 1,
    B,
    C,
    D,
};

enum class MockNegativeEnum : i8 {
    A = -1,
    B,
    C,
    D,
};

enum class NonMonotonicEnum : u8 {
    A = 0,
    B = 10,
    C = 25,
    D = 23,
};

} // namespace stdx::tests::helpers
