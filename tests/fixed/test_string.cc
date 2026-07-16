#include <sstream>
#include <string>
#include <string_view>
#include <utility>

#include <ankerl/unordered_dense.h>
#include <catch2/catch_test_macros.hpp>
#include <fmt/format.h>

#include "stdx/fixed/string.hh"
#include "stdx/string.hh"

namespace stdx::fixed::tests {

TEST_CASE("fixed::basic_string basic usage") {
    fixed::string empty;
    CHECK(empty.empty());
    CHECK(empty.size() == 0);
    CHECK(std::string_view{empty.c_str()} == "");

    fixed::string s1("hello");
    CHECK_FALSE(s1.empty());
    CHECK(s1.size() == 5);
    CHECK(s1.view() == "hello");
    CHECK(std::string_view{s1.c_str()} == "hello");
}

TEST_CASE("fixed::basic_string copy construction") {
    fixed::string s1{"hello"};

    // Copy constructor
    const fixed::string& s2{s1};
    CHECK(s2.view() == "hello");

    // Copy assignment
    fixed::string s3;
    s3 = s2;
    CHECK(s3.view() == "hello");

    // Self assignment (copy)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wself-assign-overloaded"
    s3 = s3;
#pragma clang diagnostic pop
    CHECK(s3.view() == "hello");
}

TEST_CASE("fixed::basic_string move construction") {
    fixed::string s1{"hello"};

    // Move constructor
    fixed::string s2{std::move(s1)};
    CHECK(s2.view() == "hello");
    CHECK(s1.empty());

    // Move assignment
    fixed::string s3;
    s3 = std::move(s2);
    CHECK(s3.view() == "hello");
    CHECK(s2.empty());

    // Self assignment (move)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wself-move"
    s3 = std::move(s3);
#pragma clang diagnostic pop
    CHECK(s3.view() == "hello");
}

TEST_CASE("fixed::basic_string container features") {
    fixed::string s{"world"};
    CHECK(s[0] == 'w');
    CHECK(s[4] == 'd');
    CHECK(s.front() == 'w');
    CHECK(s.back() == 'd');

    // Mutability via operator[]
    s[0] = 'W';
    CHECK(s.view() == "World");
    s.front() = 'w';
    s.back()  = 'D';
    CHECK(s.view() == "worlD");

    // Iterators
    std::string result;
    for (auto c : s) { result += c; }
    CHECK(result == "worlD");
}

TEST_CASE("fixed::basic_string comparisons") {
    fixed::string s1{"abc"};
    fixed::string s2{"def"};

    CHECK(s1 < s2);
    CHECK(s1 <= s2);
    CHECK_FALSE(s1 > s2);
    CHECK(s1 == "abc");
    CHECK("abc" == s1);
    CHECK(s2 != "abc");
}

TEST_CASE("fixed::basic_string StringLike trait and to_view") {
    fixed::string s{"test"};
    STATIC_CHECK(stdx::StringLike<fixed::string>);
    CHECK(stdx::string::to_view(s) == "test");
}

TEST_CASE("fixed::basic_string hashing and formatting") {
    fixed::string s{"format-me"};

    // Formatting
    std::string formatted{fmt::format("{}", s)};
    CHECK(formatted == "format-me");

    // Stream operator
    std::ostringstream oss;
    oss << s;
    CHECK(oss.str() == "format-me");

    // Hashing
    ankerl::unordered_dense::hash<fixed::string> hasher;
    CHECK(hasher(s) == ankerl::unordered_dense::hash<std::string_view>{}("format-me"));
}

TEST_CASE("fixed::basic_string wide character support") {
    fixed::wstring empty;
    CHECK(empty.empty());
    CHECK(empty.size() == 0);
    CHECK(empty.c_str()[0] == L'\0');

    fixed::wstring s1{L"hello"};
    CHECK_FALSE(s1.empty());
    CHECK(s1.size() == 5);
    CHECK(s1.view() == L"hello");
    CHECK(s1[0] == L'h');
    CHECK(s1.front() == L'h');
    CHECK(s1.back() == L'o');

    fixed::wstring s2{s1};
    CHECK(s2 == s1);
    CHECK(s2 == L"hello");
}

TEST_CASE("fixed::basic_string at, find, contains") {
    fixed::string s{"hello"};

    // contains
    CHECK(s.contains('e'));
    CHECK(s.contains("ell"));
    CHECK_FALSE(s.contains('z'));
    CHECK_FALSE(s.contains("world"));

    // at
    auto opt{s.at(1)};
    CHECK(opt.has_value());
    CHECK(*opt == 'e');
    CHECK_FALSE(s.at(10));

    // Mutable at
    auto opt_mut{s.at(0)};
    CHECK(opt_mut.has_value());
    *opt_mut = 'H';
    CHECK(s.view() == "Hello");

    // find
    auto opt_find{s.find('l')};
    CHECK(opt_find.has_value());
    CHECK(&*opt_find == &s[2]);
    CHECK_FALSE(s.find('z'));
}

} // namespace stdx::fixed::tests
