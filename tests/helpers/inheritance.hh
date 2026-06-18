#pragma once

#include "stdx/types.hh"

namespace stdx::tests::helpers {

struct Base {
    virtual ~Base() = default;
    i32 x{10};
};

struct Derived : Base {
    i32 y{20};
};

} // namespace stdx::tests::helpers
