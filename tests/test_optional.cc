#include <algorithm>
#include <cctype>
#include <optional>
#include <string>
#include <type_traits>

#include <catch2/catch_test_macros.hpp>

#include "helpers/enum.hh"
#include "helpers/inheritance.hh"
#include "stdx/option.hh"
#include "stdx/type_traits.hh"
#include "stdx/types.hh"

namespace stdx::tests {

using helpers::non_optionable_enum;
using helpers::optionable_enum;

TEST_CASE("Ref construction checks") {
    STATIC_CHECK_FALSE(Constructible<detail::ref<i32>, i32&&>);
    STATIC_CHECK(TriviallyCopyable<detail::ref<i32>>);
}

TEST_CASE("Option template specialization") {
    STATIC_CHECK(std::is_same_v<option<i32&>, detail::ref<i32>>);
    STATIC_CHECK(std::is_same_v<option<const i32&>, detail::ref<const i32>>);
    STATIC_CHECK(std::is_same_v<option<i32>, std::optional<i32>>);
}

TEST_CASE("Option traits") {
    STATIC_CHECK(is_option<option<i32>>::value);
    STATIC_CHECK(is_option<option<i32&>>::value);
    STATIC_CHECK(Option<option<i32>>);
    STATIC_CHECK(Option<option<i32&>>);
    STATIC_CHECK_FALSE(Option<i32>);
}

TEST_CASE("Ref basic construction") {
    i32                    val{42};
    const detail::ref<i32> opt{val};

    CHECK(opt.has_value());
    CHECK(static_cast<bool>(opt));
    CHECK(opt);
    CHECK(opt.value() == val);
    CHECK(*opt == 42);
    CHECK(opt.get() == &val);
    CHECK(opt.raw() == &val);
}

TEST_CASE("Ref null use & access") {
    const detail::ref<i32> opt1{};
    CHECK_FALSE(opt1.has_value());
    const detail::ref<i32> opt2{none};
    CHECK_FALSE(opt2.has_value());
    CHECK(!opt2.raw());
}

TEST_CASE("Ref conversions") {
    SECTION("Non-const -> const") {
        i32                          val{42};
        const detail::ref<i32>       mut_opt{val};
        const detail::ref<const i32> const_opt{mut_opt};
        CHECK(const_opt.has_value());
        CHECK(*const_opt == 42);
    }

    SECTION("Derived -> Base") {
        helpers::derived                    d;
        const detail::ref<helpers::derived> d_opt{d};
        const detail::ref<helpers::base>    base_opt = d_opt;
        CHECK(base_opt.has_value());
        CHECK(base_opt->x == 10);
    }

    SECTION("To standard optional") {
        i32                    val{42};
        const detail::ref<i32> ref_opt{val};
        const auto             std_opt{ref_opt.materialize()};
        CHECK(std_opt == 42);
    }
}

TEST_CASE("Ref reassignment") {
    i32              a{1}, b{2};
    detail::ref<i32> opt{a};
    CHECK(*opt == 1);

    opt = b;
    CHECK(*opt == 2);

    opt = none;
    CHECK_FALSE(opt.has_value());
}

TEST_CASE("Ref mutability") {
    i32                    val{42};
    const detail::ref<i32> opt{val};
    CHECK(*opt == 42);

    *opt = 1;
    CHECK(*opt == 1);
    CHECK(val == 1);
    CHECK(&*opt == &val);
}

TEST_CASE("Safe optional default equality") {
    i32                x{10}, y{10}, z{20};
    const option<i32&> opt_x{x};
    const option<i32&> opt_y{y};
    const option<i32&> opt_z{z};
    const option<i32&> opt_null;

    CHECK(safe_eq<i32&>(opt_x, opt_y));
    CHECK_FALSE(safe_eq<i32&>(opt_x, opt_z));
    CHECK_FALSE(safe_eq<i32&>(opt_x, opt_null));
    CHECK(safe_eq<i32&>(opt_null, opt_null));
}

TEST_CASE("Safe optional custom equality") {
    std::string                s1 = "APPLE", s2 = "apple";
    const option<std::string&> opt1{s1};
    const option<std::string&> opt2{s2};

    CHECK(safe_eq<std::string&>(opt1, opt2, [](const std::string& a, const std::string& b) -> bool {
        return std::ranges::equal(
            a, b, [](char ac, char bc) -> bool { return std::tolower(ac) == std::tolower(bc); });
    }));
}

TEST_CASE("Ref transform on value") {
    i32          i{9};
    option<i32&> opt_i{i};

    const auto res{opt_i.transform([](const i32& inner) -> i32 { return inner + 2; })};
    REQUIRE(res);
    CHECK(*res == 11);
}

TEST_CASE("Ref transform on none") {
    option<i32&> opt_i{};

    const auto res{opt_i.transform([](const i32& i) -> i32 { return i + 2; })};
    CHECK_FALSE(res);
}

TEST_CASE("Boolean wrapper") {
    tribool b;
    CHECK_FALSE(b.has_value());
    CHECK_FALSE(b.value_or(false));
    CHECK_FALSE(b.value_or(0));

    b = true;
    CHECK(b.has_value());
    CHECK(b.value_or(false));
}

TEST_CASE("Boolean-std optional conversion") {
    std::optional<bool> std_b{true};
    tribool             my_b = std_b;
    REQUIRE(std_b.has_value());
    CHECK(*std_b == *my_b);

    std::optional<bool> std_extracted = my_b;
    REQUIRE(std_extracted.has_value());
    CHECK(*std_extracted);

    std::optional<bool> empty_std;
    my_b = empty_std;
    CHECK_FALSE(my_b.has_value());
}

TEST_CASE("Index wrapper") {
    opt_size i;
    CHECK_FALSE(i.has_value());

    i = 0;
    CHECK(i.has_value());
    CHECK(*i == 0);
}

TEST_CASE("Index-std optional conversion") {
    std::optional<usize> std_i{42};
    opt_size             my_i = std_i;
    REQUIRE(std_i.has_value());
    CHECK(*std_i == *my_i);

    std::optional<usize> std_extracted = my_i;
    REQUIRE(std_extracted.has_value());
    CHECK(*std_extracted == 42);

    std::optional<usize> empty_std;
    my_i = empty_std;
    CHECK_FALSE(my_i.has_value());
}

TEST_CASE("CompactOpt with enum") {
    STATIC_REQUIRE_FALSE(Compactable<i32>);
    STATIC_REQUIRE_FALSE(Compactable<non_optionable_enum>);
    STATIC_REQUIRE(Compactable<optionable_enum>);
    STATIC_REQUIRE(sizeof(option<optionable_enum>) == sizeof(optionable_enum));
}

TEST_CASE("Optional enum wrapper") {
    option<optionable_enum> e;
    CHECK_FALSE(e.has_value());

    e = optionable_enum::A;
    CHECK(e.has_value());
    CHECK(*e == optionable_enum::A);
}

TEST_CASE("Enum transform on value") {
    option<optionable_enum> e{optionable_enum::A};
    const auto res{e.transform([](const optionable_enum&) -> auto { return optionable_enum::B; })};
    REQUIRE(res);
    CHECK(*res == optionable_enum::B);
}

TEST_CASE("Enum transform on none") {
    option<optionable_enum> e{};
    const auto res{e.transform([](const optionable_enum&) -> auto { return optionable_enum::B; })};
    CHECK_FALSE(res);
}

TEST_CASE("Enum-std optional conversion") {
    std::optional<optionable_enum> std_i{optionable_enum::A};
    option<optionable_enum>        my_i = std_i;
    REQUIRE(std_i.has_value());
    CHECK(*std_i == *my_i);

    std::optional<optionable_enum> std_extracted = my_i;
    REQUIRE(std_extracted.has_value());
    CHECK(*std_extracted == optionable_enum::A);

    std::optional<optionable_enum> empty_std;
    my_i = empty_std;
    CHECK_FALSE(my_i.has_value());
}

TEST_CASE("Ref transform yielding a reference") {
    helpers::derived          d;
    option<helpers::derived&> opt{d};

    auto res{opt.transform([](helpers::derived& inner) -> i32& { return inner.x; })};
    STATIC_CHECK(std::is_same_v<decltype(res), option<i32&>>);
    REQUIRE(res);
    CHECK(res.get() == &d.x);
}

TEST_CASE("Ref and_then") {
    i32          i{4};
    option<i32&> opt{i};
    option<i32&> empty;

    const auto half = [](i32& v) -> std::optional<i32> {
        if (v % 2 != 0) { return none; }
        return v / 2;
    };

    CHECK(opt.and_then(half) == 2);
    CHECK_FALSE(empty.and_then(half));

    i = 3;
    CHECK_FALSE(opt.and_then(half));
}

TEST_CASE("Ref or_else") {
    i32          a{1}, b{2};
    option<i32&> opt{a};
    option<i32&> empty;

    const auto fallback = [&b] -> option<i32&> { return b; };
    CHECK(opt.or_else(fallback).get() == &a);
    CHECK(empty.or_else(fallback).get() == &b);
}

TEST_CASE("Ref value_or") {
    i32          a{1}, b{2};
    option<i32&> opt{a};
    option<i32&> empty;

    CHECK(&opt.value_or(b) == &a);
    CHECK(&empty.value_or(b) == &b);

    helpers::derived             d;
    const option<helpers::base&> base_opt;
    CHECK(&base_opt.value_or(d) == static_cast<helpers::base*>(&d));
}

TEST_CASE("Ref has_value_and") {
    i32          i{5};
    option<i32&> opt{i};
    option<i32&> empty;

    CHECK(opt.has_value_and([](i32 v) -> bool { return v > 3; }));
    CHECK_FALSE(opt.has_value_and([](i32 v) -> bool { return v > 10; }));
    CHECK_FALSE(empty.has_value_and([](i32) -> bool { return true; }));
}

TEST_CASE("Compact option monadics") {
    STATIC_CHECK(sizeof(option<optionable_enum>) == sizeof(optionable_enum));

    option<optionable_enum> e{optionable_enum::A};
    option<optionable_enum> empty;

    SECTION("transform stays compact for compactable results") {
        auto res{
            e.transform([](optionable_enum) -> optionable_enum { return optionable_enum::C; })};
        STATIC_CHECK(std::is_same_v<decltype(res), option<optionable_enum>>);
        CHECK(res == optionable_enum::C);
    }

    SECTION("transform accepts lvalue reference parameters") {
        auto res{e.transform([](optionable_enum& inner) -> optionable_enum& { return inner; })};
        STATIC_CHECK(std::is_same_v<decltype(res), option<optionable_enum&>>);
        REQUIRE(res);
        CHECK(res.get() == e.get());
    }

    SECTION("and_then") {
        const auto next = [](optionable_enum v) -> option<optionable_enum> {
            if (v == optionable_enum::C) { return none; }
            return static_cast<optionable_enum>(static_cast<u8>(v) + 1);
        };
        CHECK(e.and_then(next).and_then(next) == optionable_enum::C);
        CHECK_FALSE(e.and_then(next).and_then(next).and_then(next));
        CHECK_FALSE(empty.and_then(next));
    }

    SECTION("or_else") {
        const auto fallback = [] -> option<optionable_enum> { return optionable_enum::B; };
        CHECK(e.or_else(fallback) == optionable_enum::A);
        CHECK(empty.or_else(fallback) == optionable_enum::B);
    }

    SECTION("value_or accepts lvalues and rvalues") {
        const auto fallback{optionable_enum::C};
        CHECK(empty.value_or(fallback) == optionable_enum::C);
        CHECK(empty.value_or(optionable_enum::B) == optionable_enum::B);
        CHECK(e.value_or(fallback) == optionable_enum::A);
    }
}

TEST_CASE("Index wrapper monadics") {
    STATIC_CHECK(sizeof(opt_size) == sizeof(usize));

    const opt_size i{3UZ};
    const opt_size empty;

    SECTION("value_or") {
        CHECK(i.value_or(7) == 3);
        CHECK(empty.value_or(7) == 7);
    }

    SECTION("transform") {
        const auto res{i.transform([](usize v) -> usize { return v * 2; })};
        REQUIRE(res);
        CHECK(*res == 6);
        CHECK_FALSE(empty.transform([](usize v) -> usize { return v * 2; }));
    }

    SECTION("and_then") {
        const auto prev = [](usize v) -> opt_size {
            if (v == 0) { return none; }
            return v - 1;
        };
        const auto res{i.and_then(prev)};
        STATIC_CHECK(std::is_same_v<decltype(res), const opt_size>);
        CHECK(res == opt_size{2UZ});
        CHECK_FALSE(opt_size{0UZ}.and_then(prev));
        CHECK_FALSE(empty.and_then(prev));
    }

    SECTION("or_else") {
        const auto fallback = [] -> opt_size { return 0UZ; };
        CHECK(i.or_else(fallback) == opt_size{3UZ});
        CHECK(empty.or_else(fallback) == opt_size{0UZ});
    }

    SECTION("has_value_and") {
        CHECK(i.has_value_and([](usize v) -> bool { return v == 3; }));
        CHECK_FALSE(empty.has_value_and([](usize) -> bool { return true; }));
    }
}

TEST_CASE("Boolean wrapper monadics") {
    STATIC_CHECK(sizeof(tribool) == sizeof(u8));

    const tribool t{true};
    const tribool f{false};
    const tribool empty;

    SECTION("value_or on const") { CHECK(empty.value_or(true)); }

    SECTION("equality") {
        CHECK(t == tribool{true});
        CHECK(t != f);
        CHECK(empty == tribool{none});
        CHECK(f != empty);
    }

    SECTION("transform") {
        const auto res{t.transform([](bool b) -> i32 { return b ? 1 : 0; })};
        STATIC_CHECK(std::is_same_v<decltype(res), const option<i32>>);
        CHECK(res == 1);
        CHECK(f.transform([](bool b) -> i32 { return b ? 1 : 0; }) == 0);
        CHECK_FALSE(empty.transform([](bool) -> i32 { return 1; }));
    }

    SECTION("and_then") {
        const auto negate = [](bool b) -> tribool { return !b; };
        CHECK(t.and_then(negate) == f);
        CHECK(f.and_then(negate) == t);
        CHECK_FALSE(empty.and_then(negate));
        const auto only_true = [](bool b) -> tribool { return b ? tribool{true} : none; };
        CHECK_FALSE(f.and_then(only_true));
    }

    SECTION("or_else") {
        const auto fallback = [] -> tribool { return false; };
        CHECK(t.or_else(fallback) == t);
        CHECK(empty.or_else(fallback) == f);
    }

    SECTION("has_value_and") {
        const auto is_true = [](bool b) -> bool { return b; };
        CHECK(t.has_value_and(is_true));
        CHECK_FALSE(f.has_value_and(is_true));
        CHECK_FALSE(empty.has_value_and(is_true));
    }
}

} // namespace stdx::tests
