#include <fuzztest/fuzztest.h>
#include <gtest/gtest.h>

void MyApiAlwaysSucceedsOnPositiveIntegers(int i) { EXPECT_TRUE(true); }
FUZZ_TEST(MyApiTest, MyApiAlwaysSucceedsOnPositiveIntegers)
    .WithDomains(/*i:*/ fuzztest::Positive<int>());
