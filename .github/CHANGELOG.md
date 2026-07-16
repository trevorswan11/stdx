# v1.0.0

- Initial release
- Partial parody of [ghoti](https://github.com/trevorswan11/ghoti)'s support library
  - Didn't port domain specific components

# v1.1.0

- Change naming conventions to use snake_case like the C++ standard library does already
- Add rehash support to `fixed::hash_map`
- Make transparent hashing more robust in the `fixed::hash_map` implementation

# v1.2.0

- Add non-trivial type support to arena allocator
  - Implemented with a linked list of destructors if one is needed
- Add operator literals for memory sizes in `size_literals` namespace

# v1.3.0

- Add set implementation to fixed hash containers
  - Renamed `fixed/hash_map` to `fixed/hash_table`

# v1.3.1

- Fix an issue where the package compressor could not handle directories

# v1.3.2

- Add some more utilities to the utility steps

# v1.4.0

- Add [nlohmann/json](https://github.com/nlohmann/json) as a dependency since it is a common dependency in applications
- Add the following dependencies for fuzz testing:
  - [fuzztest](https://github.com/google/fuzztest)
  - [abseil](https://github.com/abseil/abseil-cpp)
  - [re2](https://github.com/google/re2)
  - [googletest](https://github.com/google/googletest)
- A sample fuzz test was added that uses the new fuzzer harness extension
- All of these dependencies can be brought in by your `build.zig` except for fuzztest which does not work on windows
- Improved the zig side of the harness to support both Catch2 and GTest workflows

# v1.4.1

- Make fuzztest a non-lazy dependency so that it's trivial to link against it and its dependencies in applications and libraries

# v1.4.2

- Add pop_back, erase, and resize to vector alongside some utility (front, back) helpers
- Add object_at to memory
- Add DISCARD macro for (void) pattern

# v1.4.3

- Add spdlog as an installable library and link it against stdx by default

# v1.4.4

- Fix an issue where the intrumentor could segfault on actually valid frees (very uncommon)

# v1.4.5

- Flatten `std::hash` namespace into `stdx`'s root

# v1.4.6

- Add Capacity constraints on custom data structures
- Make math's `min_bits` a helper function rather than a IILE property
- Adjust `DISCARD` utility to properly deal with result types

# v1.5.0

- Adds `T[]` support in the `stdx::box` helper class
- Updates `TODO` to have an `unreachable` call to tell the compiler that control flow terminates

# v1.5.1

- Add default constructors for `box` types

# v1.5.2

- Add standard layout concept to `type_traits`

# v1.5.3

- Unrestrict `object_at` to take any type `T`
- Update `variant` to use `object_at` instead of duplicated launder + reinterpret
- Use std algorithm for fixed::vector erase

# v1.5.4

- Make `fixed::vector` and `fixed::hash_table`'s `capacity` helper a static constexpr one

# v1.5.5

- Make `stdx::crc::crc32` no longer depend on wyhash
- Make `stdx::crc::crc32` range independent assuming the values can be converted to a u32

# v1.5.6

- Add `stdx::enum_ops` namespace for easy enum operation usage without needing to pollute the namespace with `MAKE_ENUM_OPERATORS`

# v1.5.7

- Make `stdx::fixed::vector` respect trivial types
    - Use `std::fill` when growing if trivially copyable
    - Update the field without popping elements when shrinking if trivially destructible

# v1.6.0

- Make `stdx::fixed::hash_table` respect overwrite existing in map workflows
- Make `stdx::fixed::vector` constructor use copy constructor correctly
- Add `auto_` variants to hash tables for automatic rehashing

# v1.6.1

- Make `stdx::hasher` return references to self on `combine` for 'builder' pattern

# v2.0.0

- Remove template parameter from `crc::hash`
- `fixed::hash_` and `fixed::auto_hash_` no longer default to crc32 for hashing, preferring wyhash
    - All `constexpr` string hash maps must manually specify the `crc::hash` function

# v2.0.1

- Fix a bug where `crc32` would only work with contiguous ranges despite only needing an `input_range`

# v2.1.0

- Make abseil considerably easier to install
- Upgrade abseil and fuzztest versions to latest

# v2.2.0

- Add `fixed::basic_string` for dynamically allocated strings that are not resizable

# v2.2.1

- Add missing size initialization to `fixed::basic_string`
