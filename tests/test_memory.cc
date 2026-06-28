#include <utility>

#include <catch2/catch_test_macros.hpp>
#include <gsl/span>

#include "helpers/inheritance.hh"
#include "stdx/memory.hh"
#include "stdx/types.hh"

namespace stdx::tests {

using ok_box     = box<bool>;
using not_box    = bool;
using custom_box = box<bool, void (*)(bool*)>;

TEST_CASE("Basic box construction") {
    auto b{make_box<i32>(42)};
    CHECK(*b == 42);
}

TEST_CASE("Box upcasting") {
    auto               d{make_box<helpers::derived>()};
    box<helpers::base> b{std::move(d)};
    CHECK(b->x == 10);
}

TEST_CASE("Box release") {
    auto b{make_box<i32>(10)};
    i32* raw = b.release();
    CHECK(raw != nullptr);
    delete raw;
}

TEST_CASE("Boxed array type specialization") {
    auto b{make_box<i32[]>(10UZ)};
    for (i32 i{0}; auto& val : gsl::span<i32>{b.get(), 10}) { val = i++; }
    for (usize i{0}; i < 10; ++i) { CHECK(b[i] == static_cast<i32>(i)); }
}

TEST_CASE("Boxed array conversion constructor") {
    auto non_const_b{make_box<i32[]>(10UZ)};
    for (i32 i{0}; auto& val : gsl::span<i32>{non_const_b.get(), 10}) { val = i++; }

    box<const i32[]> const_b{std::move(non_const_b)};
    for (usize i{0}; i < 10; ++i) { CHECK(const_b[i] == static_cast<i32>(i)); }
}

TEST_CASE("Sizes") {
    using namespace size_literals;
    CHECK(1_KiB == 1'024);
    CHECK(sizes::kib(1UZ) == 1'024);
    CHECK(1_MiB == 1'024ULL * 1'024ULL);
    CHECK(sizes::mib(1UZ) == 1'024ULL * 1'024ULL);
}

} // namespace stdx::tests
