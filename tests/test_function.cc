#include <string>
#include <utility>

#include <catch2/catch_test_macros.hpp>

#include "helpers/raii_tracker.hh"
#include "stdx/function.hh"
#include "stdx/types.hh"

namespace stdx::tests {

namespace {

auto free_add(i32 a, i32 b) -> i32 { return a + b; }

auto free_concat(const std::string& a, const std::string& b) -> std::string { return a + b; }

} // namespace

TEST_CASE("Empty function boolean conversion") {
    function<void()> empty;
    CHECK_FALSE(static_cast<bool>(empty));
    CHECK_FALSE(empty.is_valid());
    empty();

    function<i32()> empty_int;
    CHECK(empty_int() == 0);

    function<void()> from_null{nullptr};
    CHECK_FALSE(static_cast<bool>(from_null));
    from_null();
}

TEST_CASE("Function pointers") {
    function<i32(i32, i32)> fn{free_add};
    REQUIRE(static_cast<bool>(fn));
    CHECK(fn(3, 4) == 7);

    function<std::string(const std::string&, const std::string&)> str_fn{free_concat};
    CHECK(str_fn("foo", "bar") == "foobar");
}

TEST_CASE("Function with non-capturing lambdas") {
    function<i32(i32)> square{[](i32 x) -> i32 { return x * x; }};
    REQUIRE(static_cast<bool>(square));
    CHECK(square(5) == 25);
}

TEST_CASE("Function with capturing lambdas") {
    i32                multiplier{10};
    function<i32(i32)> scale{[multiplier](i32 x) -> i32 { return x * multiplier; }};
    CHECK(scale(7) == 70);

    std::string                               prefix{"Hello, "};
    function<std::string(const std::string&)> format{
        [prefix](const std::string& title) -> std::string { return prefix + title; }};
    CHECK(format("World!") == "Hello, World!");
}

TEST_CASE("Function with reference captures and mutations") {
    i32              call_count{0};
    function<void()> increment{[&call_count] -> void { ++call_count; }};

    increment();
    increment();
    increment();
    CHECK(call_count == 3);
}

TEST_CASE("Function with mutable stateful lambdas") {
    function<i32()> counter{[val{0}] mutable -> i32 { return ++val; }};

    CHECK(counter() == 1);
    CHECK(counter() == 2);
    CHECK(counter() == 3);
}

TEST_CASE("Function copy semantics") {
    i32             val{42};
    function<i32()> original{[val] -> i32 { return val; }};

    function<i32()> copy_constructed{original}; // NOLINT
    CHECK(copy_constructed() == 42);

    function<i32()> copy_assigned;
    copy_assigned = original;
    CHECK(copy_assigned() == 42);
}

TEST_CASE("Function move semantics") {
    std::string             text{"Hello function"};
    function<std::string()> original{[t{std::move(text)}] -> std::string { return t; }};

    function<std::string()> moved_to{std::move(original)};
    CHECK_FALSE(static_cast<bool>(original));
    REQUIRE(static_cast<bool>(moved_to));
    CHECK(moved_to() == "Hello function");

    function<std::string()> move_assigned;
    move_assigned = std::move(moved_to);
    CHECK_FALSE(static_cast<bool>(moved_to));
    REQUIRE(static_cast<bool>(move_assigned));
    CHECK(move_assigned() == "Hello function");
}

TEST_CASE("Function reset and destructor execution") {
    using tracker = helpers::raii_tracker;
    tracker::reset();

    {
        function<void()> t{[tr{tracker{0}}] -> void {}};
        CHECK(tracker::live_count == 1);
    }
    CHECK(tracker::live_count == 0);

    {
        function<void()> t{[tr{tracker{0}}] -> void {}};
        CHECK(tracker::live_count == 1);

        t.reset();
        CHECK(tracker::live_count == 0);
        CHECK_FALSE(static_cast<bool>(t));

        t = [tr{tracker{0}}] -> void {};
        CHECK(tracker::live_count == 1);

        t = nullptr;
        CHECK(tracker::live_count == 0);
    }
}

} // namespace stdx::tests
