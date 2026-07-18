#include <algorithm>
#include <cctype>
#include <optional>
#include <string>
#include <type_traits>

#include <catch2/catch_test_macros.hpp>

#include "helpers/inheritance.hh"
#include "stdx/option.hh"
#include "stdx/type_traits.hh"
#include "stdx/types.hh"

namespace stdx::tests {

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
    CHECK(&*opt == &val);
}

TEST_CASE("Ref null use & access") {
    const detail::ref<i32> opt1{};
    CHECK_FALSE(opt1.has_value());
    const detail::ref<i32> opt2{none};
    CHECK_FALSE(opt2.has_value());
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

enum non_optionable_enum : u8 {};

enum class optionable_enum : u8 {
    A,
    B,
    C,
};

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

} // namespace stdx::tests
