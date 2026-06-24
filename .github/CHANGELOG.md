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
