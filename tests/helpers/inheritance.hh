#pragma once

#include "stdx/types.hh"

namespace stdx::tests::helpers {

struct base {
    virtual ~base() = default;
    i32 x{10};
};

struct derived : base {
    i32 y{20};
};

} // namespace stdx::tests::helpers
