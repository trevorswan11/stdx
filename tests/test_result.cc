#include <string>
#include <string_view>

#include <catch2/catch_test_macros.hpp>

#include "stdx/option.hh"
#include "stdx/result.hh"
#include "stdx/types.hh"
#include "stdx/utility.hh"

namespace stdx::tests {

TEST_CASE("Result traits") {
    STATIC_CHECK(is_result<result<i32, i64>>::value);
    STATIC_CHECK(is_result<result<i32&, std::string>>::value);
    STATIC_CHECK(Result<result<i32, i64>>);
    STATIC_CHECK_FALSE(Result<i32>);
}

TEST_CASE("Try macro usage") {
    result<i32, std::string_view> res;
    const auto                    unwrap = [&] -> option<err<std::string_view>> {
        const auto val{TRY(res)};
        CHECK(val == 2);
        return none;
    };

    res.emplace(2);
    CHECK_FALSE(unwrap());

    const std::string_view str{"Hello, World!"};
    res = make_err<std::string_view>(str);
    const auto err{unwrap()};
    REQUIRE(err);
    CHECK(err->error() == str);
}

TEST_CASE("Discarded results") {
    const auto result_maker = [] -> result<i32, std::string_view> { return 1; };
    DISCARD(result_maker());
}

} // namespace stdx::tests
