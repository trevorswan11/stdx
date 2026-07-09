#include <catch2/catch_test_macros.hpp>

#include "stdx/hash.hh"
#include "stdx/types.hh"

namespace stdx::tests {

TEST_CASE("Hashing different types") {
    enum t1 : i32 {};
    STATIC_CHECK(hash<t1>{}(t1{0}) == 0);
    enum class t2 : i64 {};
    STATIC_CHECK(hash<t2>{}(t2{0}) == 0);
    enum class t3 : u32 {};
    CHECK(hash<t3>{}(t3{0}) == 0);
}

TEST_CASE("Order dependent hashing") {
    hasher h1{1}, h2{2};
    h1.combine(2);
    h2.combine(1);
    CHECK_FALSE(h1.finalize() == h2.finalize());
}

TEST_CASE("Builder pattern hashing") {
    CHECK_FALSE(hasher{}.combine(1).combine(2).combine(3).finalize() == 0);
}

} // namespace stdx::tests
