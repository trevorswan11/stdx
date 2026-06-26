#include <utility>

#include <catch2/catch_test_macros.hpp>

#include "helpers/inheritance.hh"
#include "stdx/memory.hh"

namespace stdx::tests {

using ok_box     = box<bool>;
using not_box    = bool;
using custom_box = box<bool, void (*)(bool*)>;

TEST_CASE("Basic box construction") {
    auto b{make_box<int>(42)};
    CHECK(*b == 42);
}

TEST_CASE("Box upcasting") {
    auto               d{make_box<helpers::derived>()};
    box<helpers::base> b{std::move(d)};
    CHECK(b->x == 10);
}

TEST_CASE("Box release") {
    auto b{make_box<int>(10)};
    int* raw = b.release();
    CHECK(raw != nullptr);
    delete raw;
}

TEST_CASE("Sizes") {
    using namespace size_literals;
    CHECK(1_KiB == 1'024);
    CHECK(sizes::kib(1UZ) == 1'024);
    CHECK(1_MiB == 1'024ULL * 1'024ULL);
    CHECK(sizes::mib(1UZ) == 1'024ULL * 1'024ULL);
}

} // namespace stdx::tests
