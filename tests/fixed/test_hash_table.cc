#include <algorithm>
#include <iterator>
#include <string>
#include <string_view>
#include <utility>

#include <catch2/catch_test_macros.hpp>

#include "helpers/raii_tracker.hh"
#include "stdx/fixed/hash_table.hh"
#include "stdx/hash.hh"
#include "stdx/types.hh"

namespace stdx::tests {

TEST_CASE("Metadata helpers") {
    using fixed::detail::hash_table_metadata;
    hash_table_metadata metadata;

    metadata.open_up();
    CHECK(metadata.is_open());
    metadata.bury();
    CHECK(metadata.is_tombstone());

    metadata.fill(20);
    CHECK(metadata.get_fingerprint() == 20);
    CHECK(metadata.is_used());
    metadata.fill(255);
    REQUIRE(metadata.get_fingerprint() == 127);

    REQUIRE(hash_table_metadata::take_fingerprint(300) == 0);
    REQUIRE(hash_table_metadata::take_fingerprint(0xFFFFFFFFFFFFFFF) == 7);
    REQUIRE(hash_table_metadata::take_fingerprint(0xAFFF5FFFFFFFFFFF) == 87);
    REQUIRE(hash_table_metadata::take_fingerprint(0xFFFFFFFFFFFFFFFF) == 127);
}

TEST_CASE("hash_map construction") {
    fixed::hash_map<u16, u32, 4> hm;

    STATIC_CHECK(hm.capacity() == 4);
    CHECK(hm.size() == 0);

    for (const auto& metadata : hm.get_metadata()) {
        CHECK(metadata == fixed::detail::hash_table_metadata::make_open_slot());
    }
}

TEST_CASE("hash_map basic usage") {
    fixed::hash_map<u32, u32, 16> hm;

    constexpr u32 insert_count{10};
    for (u32 i = 0; i < insert_count; ++i) { hm.emplace(i, i); }
    CHECK(hm.size() == insert_count);

    for (u32 i = 0; i < insert_count; ++i) {
        CHECK(hm.contains(i));
        const auto val{hm.get_opt(i)};
        REQUIRE(val);
        CHECK(*val == i);
        CHECK(hm.get(i) == i);
    }

    hm.remove(0);
}

TEST_CASE("hash_set basic usage") {
    fixed::hash_set<u32, 16> hs;

    constexpr u32 insert_count{10};
    for (u32 i = 0; i < insert_count; ++i) { hs.emplace(i); }
    CHECK(hs.size() == insert_count);

    for (u32 i = 0; i < insert_count; ++i) { CHECK(hs.contains(i)); }

    hs.remove(0);
    CHECK_FALSE(hs.contains(0));
}

TEST_CASE("hash_map helper constructor & clear") {
    auto hm{fixed::make_hash_map(std::pair{0, 0},
                                 std::pair{3, 3},
                                 std::pair{3, 4},
                                 std::pair{4, 4},
                                 std::pair{5, 5},
                                 std::pair{6, 6})};

    STATIC_CHECK(hm.capacity() == 8);
    CHECK(hm.size() == 5);

    CHECK(hm.contains(0));
    CHECK(hm.get(0) == 0);

    CHECK(hm.contains(3));
    CHECK(hm.get(3) == 4);

    hm.clear();
    CHECK(hm.size() == 0);
    for (i32 i = -10; i < 10; ++i) {
        CHECK_FALSE(hm.contains(i));
        CHECK_FALSE(hm.get_opt(i));
    }
}

TEST_CASE("hash_map constexpr operations") {
    constexpr auto hm{fixed::make_hash_map(std::pair{0, 0}, std::pair{3, 3}, std::pair{2, 4})};
    STATIC_CHECK(hm.size() == 3);
    STATIC_CHECK(hm.contains(0));
    STATIC_CHECK(hm.get(0) == 0);
    STATIC_CHECK_FALSE(hm.contains(12));
}

TEST_CASE("hash_map constexpr string view key") {
    constexpr auto hm{[] -> auto {
        fixed::hash_map<std::string_view, i32, 6, crc::hash> map;
        map.emplace("0", 0);
        map.emplace("3", 3);
        map.emplace("3", 4);
        map.emplace("4", 4);
        map.emplace("5", 5);
        map.emplace("6", 6);
        return map;
    }()};

    CHECK(hm.contains("0"));
    CHECK(hm.get_opt("3"));
    CHECK(hm.get("3") == 4);
}

TEST_CASE("Rehash map") {
    fixed::hash_map<usize, usize, 1'635UZ> hm;

    // Add some elements and remove every third to simulate a fragmented map
    for (usize i{0}; i < hm.capacity(); i++) {
        hm.emplace(i, i);
        if (i % 3 == 0) { hm.remove(i); }
    }

    // Rehash and ensure data was not lost along the way
    hm.rehash();
    REQUIRE(hm.size() == hm.capacity() * 2 / 3);
    for (usize i = 0; i < hm.capacity(); i++) {
        if (i % 3 == 0) {
            CHECK_FALSE(hm.contains(i));
        } else {
            const auto& opt_value = hm.get_opt(i);
            REQUIRE(opt_value);
            CHECK(*opt_value == i);
        }
    }
}

TEST_CASE("hash_map transparent usage") {
    fixed::hash_map<std::string, u32, 20> hm;
    hm.emplace("hi", 2);
    CHECK(hm.contains("hi"));
}

TEST_CASE("hash_map emplace api") {
    fixed::hash_map<u32, u32, 20> hm;

    // Happy path emplacement
    {
        auto try_result = hm.try_emplace(0, 1);
        CHECK(try_result.inserted);
        CHECK(try_result.it->first == 0);
        CHECK(try_result.it->second == 1);

        auto result = hm.emplace(1, 2);
        CHECK(result.inserted);
        CHECK(result.it->first == 1);
        CHECK(result.it->second == 2);
    }

    // try_emplace doesn't overwrite data
    {
        auto try_result = hm.try_emplace(0, 1);
        CHECK_FALSE(try_result.inserted);
        CHECK(try_result.it->first == 0);
        CHECK(try_result.it->second == 1);
    }

    // Emplace overwrites data
    {
        auto result = hm.emplace(0, 7);
        CHECK(result.inserted);
        CHECK(result.it->first == 0);
        CHECK(result.it->second == 7);
    }
}

using tracker = helpers::raii_tracker;

TEST_CASE("hash_table destructor correctness") {
    tracker::reset();
    {
        fixed::hash_map<i32, tracker, 5> hm;
        hm.emplace(0, 0);
        hm.emplace(1, 0);
    }
    CHECK(tracker::destruct_count == 2);
}

TEST_CASE("hash_table copy correctness") {
    using hash_map = fixed::hash_map<i32, tracker, 3>;
    tracker::reset();
    {
        hash_map original;
        original.emplace(0, 0);
        original.emplace(1, 0);

        SECTION("Copy constructor") {
            hash_map copy{original}; // NOLINT
            CHECK(copy.size() == 2);
            CHECK(tracker::copy_count == 2);

            // 2 in original, 2 in copy
            CHECK(tracker::live_count == 4);
        }

        SECTION("Copy assignment") {
            hash_map assigned;
            assigned = original;
            CHECK(assigned.size() == 2);

            // Copy internally followed by move
            CHECK(tracker::copy_count == 2);
        }
    }
    CHECK(tracker::live_count == 0);
}

TEST_CASE("hash_table move correctness") {
    using hash_map = fixed::hash_map<i32, tracker, 78>;
    tracker::reset();
    {
        hash_map original;
        original.emplace(0, 0);
        original.emplace(1, 0);

        hash_map destination{std::move(original)};
        CHECK(destination.size() == 2);
        CHECK(original.empty());
        CHECK(tracker::move_count == 2);
        CHECK(tracker::live_count == 2);
    }
    CHECK(tracker::live_count == 0);
}

TEST_CASE("hash_table self assignment") {
    tracker::reset();
    fixed::hash_map<i32, tracker, 3> hm;
    hm.emplace(0, 0);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wself-assign-overloaded"
    hm = hm;
#pragma clang diagnostic pop

    CHECK(hm.size() == 1);
    CHECK(tracker::live_count == 1);
}

TEST_CASE("hash_map non-const iterator") {
    auto hm{fixed::make_hash_map(std::pair{0, -1},
                                 std::pair{1, -1},
                                 std::pair{2, -1},
                                 std::pair{3, -1},
                                 std::pair{4, -1},
                                 std::pair{5, -1},
                                 std::pair{6, -1},
                                 std::pair{7, -1})};

    SECTION("Full map iteration and update") {
        usize iter_count{0};
        for (auto [key, value] : hm) {
            CHECK(value == -1);
            value = 10;
            iter_count++;
        }
        CHECK(iter_count == hm.size());
        for (auto [key, value] : hm) { CHECK(value == 10); }
    }

    SECTION("Map item removal") {
        usize iter_count{0};
        hm.remove(7);
        for (auto _ : hm) { iter_count++; }
        CHECK(iter_count == hm.size());
    }
}

TEST_CASE("hash_map const iterator") {
    constexpr auto hm{fixed::make_hash_map(
        std::pair{0, -1}, std::pair{1, -1}, std::pair{5, -1}, std::pair{6, -1}, std::pair{7, -1})};

    usize iter_count{0};
    for (auto [key, value] : hm) {
        CHECK(value == -1);
        iter_count++;
    }
    CHECK(iter_count == hm.size());
}

TEST_CASE("hash_set non-const iterator") {
    auto hs{fixed::make_hash_set(0, 1, 2)};

    usize iter_count{0};
    for (auto _ : hs) { iter_count++; }
    CHECK(iter_count == hs.size());
}

TEST_CASE("hash_set const iterator") {
    constexpr auto hs{fixed::make_hash_set(0, 1, 2)};

    usize iter_count{0};
    for (auto _ : hs) { iter_count++; }
    CHECK(iter_count == hs.size());
}

TEST_CASE("hash_map ranges compatibility") {
    STATIC_REQUIRE(std::forward_iterator<fixed::hash_map<u16, u32, 4>::iterator>);
    STATIC_REQUIRE(std::forward_iterator<fixed::hash_map<u16, u32, 4>::const_iterator>);

    constexpr auto hm{fixed::make_hash_map(std::pair{-2, -1}, std::pair{1, -1}, std::pair{5, -1})};
    i32            sum{0};
    usize          iter_count{0};
    std::ranges::for_each(hm, [&sum, &iter_count](auto pair) -> void {
        sum += pair.first;
        iter_count++;
    });

    CHECK(sum == 4);
    CHECK(iter_count == 3);
}

TEST_CASE("auto_hash_map basic usage & automatic tombstone cleanup") {
    fixed::auto_hash_map<u32, u32, 8> ahm;
    STATIC_CHECK(ahm.capacity() == 8);
    CHECK(ahm.size() == 0);

    for (u32 i{0}; i < 50; ++i) {
        ahm.emplace(i, i * 10);
        CHECK(ahm.size() == 1);
        CHECK(ahm.contains(i));
        CHECK(ahm.get(i) == i * 10);

        ahm.remove(i);
        CHECK(ahm.size() == 0);
        CHECK_FALSE(ahm.contains(i));
    }
}

TEST_CASE("auto_hash_set basic usage & automatic tombstone cleanup") {
    fixed::auto_hash_set<u32, 8> ahs;

    STATIC_CHECK(ahs.capacity() == 8);
    CHECK(ahs.size() == 0);

    for (u32 i{0}; i < 50; ++i) {
        ahs.emplace(i);
        CHECK(ahs.size() == 1);
        CHECK(ahs.contains(i));

        ahs.remove(i);
        CHECK(ahs.size() == 0);
        CHECK_FALSE(ahs.contains(i));
    }
}

TEST_CASE("make_auto_hash_map & make_auto_hash_set helper constructors") {
    auto ahm{fixed::make_auto_hash_map(std::pair{1, 10}, std::pair{2, 20})};
    STATIC_CHECK(ahm.capacity() == 2);
    CHECK(ahm.size() == 2);
    CHECK(ahm.get(1) == 10);
    CHECK(ahm.get(2) == 20);

    auto ahs{fixed::make_auto_hash_set(10, 20, 30)};
    STATIC_CHECK(ahs.capacity() == 4);
    CHECK(ahs.size() == 3);
    CHECK(ahs.contains(10));
    CHECK(ahs.contains(20));
    CHECK(ahs.contains(30));
}

} // namespace stdx::tests
