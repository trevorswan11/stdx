#include <string>

#include "stdx/types.hh"

namespace stdx::tests::helpers {

struct foo {
    i32  value;
    auto operator==(const foo&) const -> bool = default;
};

struct bar {
    std::string value;
    auto        operator==(const bar&) const -> bool = default;
};

struct baz {
    f64  value;
    auto operator==(const baz&) const -> bool = default;
};

} // namespace stdx::tests::helpers
