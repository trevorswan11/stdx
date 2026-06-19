#include <string>
#include <utility>

#include <catch2/catch_test_macros.hpp>

#include "helpers/dummy.hh"
#include "helpers/raii_tracker.hh"
#include "stdx/option.hh"
#include "stdx/types.hh"
#include "stdx/variant.hh"

namespace stdx::tests {

using foo     = helpers::foo;
using bar     = helpers::bar;
using baz     = helpers::baz;
using fbb     = variant<foo, bar, baz>;
using tracker = helpers::raii_tracker;

TEST_CASE("Variant default construction activates first alternative") {
    variant<foo, bar> v;
    CHECK(v.is<foo>());
    CHECK(v.index() == 0UZ);
}

TEST_CASE("Variant implicit construction from alternative type") {
    fbb v{foo{42}};
    CHECK(v.is<foo>());
    CHECK(v.as<foo>().value == 42);
}

TEST_CASE("Variant in-place construction") {
    fbb v{std::in_place_type<bar>, "hello"};
    CHECK(v.is<bar>());
    CHECK(v.as<bar>().value == "hello");
}

TEST_CASE("Variant::emplace<T> changes active alternative") {
    fbb v{foo{1}};
    v.emplace<bar>("emplaced");
    CHECK(v.is<bar>());
    CHECK(v.as<bar>().value == "emplaced");
}

TEST_CASE("Variant::emplace<T> calls destructor on old value") {
    tracker::reset();
    {
        variant<tracker, foo> v = tracker{0};
        CHECK(tracker::live_count == 1);
        v.emplace<foo>(99);
        CHECK(tracker::live_count == 0);
    }
}

TEST_CASE("Variant::is<T>") {
    fbb v{bar{"x"}};
    CHECK(v.is<bar>());
    CHECK_FALSE(v.is<foo>());
    CHECK_FALSE(v.is<baz>());
}

TEST_CASE("Variant::index") {
    CHECK(fbb{foo{}}.index() == 0UZ);
    CHECK(fbb{bar{}}.index() == 1UZ);
    CHECK(fbb{baz{}}.index() == 2UZ);
}

TEST_CASE("Variant::as<T> returns mutable reference") {
    fbb v{foo{1}};
    v.as<foo>().value = 99;
    CHECK(v.as<foo>().value == 99);
}

TEST_CASE("Variant::as<T> returns const reference on const Variant") {
    const fbb  v{bar{"const"}};
    const bar& b{v.as<bar>()};
    CHECK(b.value == "const");
}

TEST_CASE("Variant::as<T> moves out of rvalue Variant") {
    fbb v{bar{"moved"}};
    bar b{std::move(v).as<bar>()};
    CHECK(b.value == "moved");
}

TEST_CASE("Variant::as_opt<T> returns engaged Option for active type") {
    fbb  v{baz{1.5}};
    auto opt{v.as_opt<baz>()};
    REQUIRE(opt.has_value());
    CHECK(opt->value == 1.5);
}

TEST_CASE("Variant::as_opt<T> returns empty Option for inactive type") {
    fbb v{foo{1}};
    CHECK_FALSE(v.as_opt<bar>().has_value());
}

TEST_CASE("Variant::as_opt<T> const yields const ref") {
    const fbb          v{bar{"ro"}};
    option<const bar&> opt = v.as_opt<bar>();
    REQUIRE(opt.has_value());
    CHECK(opt->value == "ro");
}

TEST_CASE("Variant::as_opt<T> supports transform()") {
    fbb  v{bar{"transform"}};
    auto len{v.as_opt<bar>().transform([](const bar& b) -> usize { return b.value.size(); })};
    REQUIRE(len.has_value());
    CHECK(*len == 9UZ);
}

TEST_CASE("Variant::visit variadic lambda form with non-void return") {
    fbb v{foo{10}};
    i32 r{v.visit([](const foo& f) -> i32 { return f.value; },
                  [](const bar&) -> i32 { return -1; },
                  [](const baz&) -> i32 { return -2; })};
    CHECK(r == 10);
}

TEST_CASE("Variant::visit variadic lambda form with void return") {
    fbb  v{bar{"side effect"}};
    auto called{false};
    v.visit([](const foo&) -> void {},
            [&](const bar&) -> void { called = true; },
            [](const baz&) -> void {});
    CHECK(called);
}

TEST_CASE("Variant::visit on const Variant") {
    const fbb v{bar{"const visit"}};
    auto      len{v.visit([](const foo&) -> usize { return 0UZ; },
                     [](const bar& b) -> usize { return b.value.size(); },
                     [](const baz&) -> usize { return 0UZ; })};
    CHECK(len == 11UZ);
}

TEST_CASE("Variant::operator==") {
    CHECK(fbb{foo{1}} == fbb{foo{1}});
    CHECK(fbb{bar{"x"}} == fbb{bar{"x"}});
    CHECK_FALSE(fbb{foo{1}} == fbb{foo{2}});
    CHECK_FALSE(fbb{foo{1}} == fbb{bar{"x"}});
}

TEST_CASE("Variant copy construction") {
    fbb a{bar{"copy me"}};
    fbb b{a};
    CHECK(b.is<bar>());
    CHECK(b.as<bar>().value == "copy me");
    a.as<bar>().value = "modified";
    CHECK(b.as<bar>().value == "copy me");
}

TEST_CASE("Variant copy assignment") {
    fbb a{foo{1}};
    fbb b{bar{"x"}};
    b = a;
    CHECK(b.is<foo>());
    CHECK(b.as<foo>().value == 1);
}

TEST_CASE("Variant move construction") {
    fbb a{bar{"move me"}};
    fbb b{std::move(a)};
    CHECK(b.is<bar>());
    CHECK(b.as<bar>().value == "move me");
}

TEST_CASE("Variant move assignment") {
    fbb a{baz{3.14}};
    fbb b{foo{0}};
    b = std::move(a);
    CHECK(b.is<baz>());
    CHECK(b.as<baz>().value == 3.14);
}

TEST_CASE("Variant copy/move destructor accounting") {
    tracker::reset();
    {
        variant<tracker, foo> a{tracker{0}};
        CHECK(tracker::live_count == 1);
        variant<tracker, foo> b = a; // copy (increment)
        CHECK(tracker::live_count == 2);
        variant<tracker, foo> c = std::move(b); // move (no increment)
        CHECK(tracker::live_count == 2);
    } // a and c destroyed
    CHECK(tracker::live_count == 0);
}

} // namespace stdx::tests
