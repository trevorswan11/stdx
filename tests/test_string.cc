#include <string>
#include <string_view>
#include <type_traits>

#include <catch2/catch_test_macros.hpp>

#include "stdx/string.hh"

namespace stdx::tests {

TEST_CASE("String traits") {
    STATIC_CHECK(StringLike<std::string>);
    STATIC_CHECK(StringLike<std::string_view>);
    STATIC_CHECK(StringLike<const char*>);
}

TEST_CASE("Byte type requirement") {
    STATIC_CHECK(std::is_same_v<std::string::value_type, char>);
    STATIC_CHECK(std::is_same_v<char, char>);
}

TEST_CASE("Left trim spaces") {
    CHECK(string::trim_left("") == "");
    CHECK(string::trim_left("the") == "the");
    CHECK(string::trim_left("    the") == "the");
    CHECK(string::trim_left("        ") == "");
}

TEST_CASE("Right trim spaces") {
    CHECK(string::trim_right("") == "");
    CHECK(string::trim_right("the") == "the");
    CHECK(string::trim_right("the    ") == "the");
    CHECK(string::trim_right("        ") == "");
}

TEST_CASE("Trim spaces") {
    CHECK(string::trim("") == "");
    CHECK(string::trim("the") == "the");
    CHECK(string::trim("the    ") == "the");
    CHECK(string::trim("    the") == "the");
    CHECK(string::trim("    the    ") == "the");
    CHECK(string::trim("        ") == "");
}

TEST_CASE("Trim pred") {
    constexpr std::string_view against{"asdaefae"};
    CHECK(string::trim("theasdaefae", [&](char c) -> bool { return against.contains(c); }) == "th");
}

TEST_CASE("String view substrings") {
    constexpr std::string_view str{"abcdefghijk"};
    CHECK(string::substr(str, 2) == "cdefghijk");
    CHECK(string::substr(str, 2, 7) == "cdefghi");
    CHECK(string::substr(str, 100) == "");
}

TEST_CASE("Blank string check") {
    CHECK_FALSE(string::is_blank("const T &text"));
    CHECK(string::is_blank("        "));
    CHECK(string::is_blank("        \t\n\r"));
}

TEST_CASE("String view conversion") {
    const auto*            c_str{"Hello, World!"};
    const std::string_view view{c_str};
    const std::string      str{c_str};

    CHECK(string::to_view(c_str) == string::to_view(c_str));
    CHECK(string::to_view(c_str) == string::to_view(view));
    CHECK(string::to_view(c_str) == string::to_view(str));
    CHECK(string::to_view(view) == string::to_view(str));
}

TEST_CASE("to_lower and to_upper for characters") {
    CHECK(string::to_lower('A') == 'a');
    CHECK(string::to_lower('Z') == 'z');
    CHECK(string::to_lower('a') == 'a');
    CHECK(string::to_lower('z') == 'z');
    CHECK(string::to_lower('0') == '0');
    CHECK(string::to_lower('!') == '!');

    CHECK(string::to_upper('a') == 'A');
    CHECK(string::to_upper('z') == 'Z');
    CHECK(string::to_upper('A') == 'A');
    CHECK(string::to_upper('Z') == 'Z');
    CHECK(string::to_upper('9') == '9');
    CHECK(string::to_upper('?') == '?');
}

TEST_CASE("inplace_lower and inplace_upper for strings") {
    std::string s1{"AbCdEfG123!@#"};
    string::inplace_lower(s1);
    CHECK(s1 == "abcdefg123!@#");

    std::string s2{"AbCdEfG123!@#"};
    string::inplace_upper(s2);
    CHECK(s2 == "ABCDEFG123!@#");

    std::string empty;
    string::inplace_lower(empty);
    CHECK(empty.empty());
    string::inplace_upper(empty);
    CHECK(empty.empty());
}

} // namespace stdx::tests
