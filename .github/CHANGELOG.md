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
