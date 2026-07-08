#pragma once

#include <array>
#include <bit>
#include <concepts>
#include <functional>
#include <iterator>
#include <memory>
#include <type_traits>
#include <utility>

#include <gsl/span>

#include "stdx/assert.hh"
#include "stdx/fixed/storage.hh"
#include "stdx/hash.hh"
#include "stdx/iterator.hh"
#include "stdx/math.hh"
#include "stdx/option.hh"
#include "stdx/string.hh"
#include "stdx/type_traits.hh"
#include "stdx/types.hh"

namespace stdx::fixed {

namespace detail {

class hash_table_metadata {
  public:
    enum class fingerprint : u8 {
        OPEN      = 0,
        TOMBSTONE = 1,
    };

  public:
    constexpr hash_table_metadata() noexcept = default;
    constexpr hash_table_metadata(u8 fingerprint, bool used) noexcept {
        raw_ |= used << USED_OFFSET;
        raw_ |= fingerprint & FINGERPRINT_MASK;
    }

    constexpr hash_table_metadata(fingerprint fingerprint, bool used) noexcept
        : hash_table_metadata{static_cast<u8>(fingerprint), used} {}

    [[nodiscard]] static constexpr auto make_open_slot() noexcept -> hash_table_metadata {
        return {fingerprint::OPEN, false};
    }

    [[nodiscard]] static constexpr auto make_tombstone_slot() noexcept -> hash_table_metadata {
        return {fingerprint::TOMBSTONE, false};
    }

    [[nodiscard]] constexpr auto is_used() const noexcept -> bool { return (raw_ & USED_MASK) > 0; }
    [[nodiscard]] constexpr auto get_fingerprint() const noexcept -> u8 {
        return raw_ & FINGERPRINT_MASK;
    }

    constexpr auto               open_up() noexcept -> void { *this = make_open_slot(); }
    [[nodiscard]] constexpr auto is_open() const noexcept -> bool {
        return *this == make_open_slot();
    }

    constexpr auto               bury() noexcept -> void { *this = make_tombstone_slot(); }
    [[nodiscard]] constexpr auto is_tombstone() const noexcept -> bool {
        return *this == make_tombstone_slot();
    }

    // Sets the inner fingerprint and marks the metadata as used
    constexpr auto fill(u8 fingerprint) noexcept -> void { *this = {fingerprint, true}; }

    // Only the 7 most significant bits of the result are relevant
    static constexpr auto take_fingerprint(u64 hash) noexcept -> u8 {
        return FINGERPRINT_MASK & (hash >> (64 - USED_OFFSET));
    }

    [[nodiscard]] constexpr auto operator==(const hash_table_metadata&) const noexcept
        -> bool = default;

  private:
    static constexpr u8 FINGERPRINT_MASK{0x7F};
    static constexpr u8 USED_MASK{0x80};
    static constexpr u8 USED_OFFSET{std::countr_zero(USED_MASK)};

  private:
    u8 raw_{0};
};

// Auto hash map
template <typename Key, typename Value, usize Capacity, bool AutoRehash, usize RehashLimit>
class hash_table_storage {
  public:
    [[nodiscard]] constexpr auto key_data(this auto&& self) noexcept -> auto* {
        return self.keys_.data();
    }

    [[nodiscard]] constexpr auto value_data(this auto&& self) noexcept -> auto* {
        return self.values_.data();
    }

    // `reset_churn` must be called manually
    [[nodiscard]] constexpr auto needs_rehash() const noexcept -> bool {
        return ++churn_ >= RehashLimit;
    }

    constexpr auto reset_churn() const noexcept -> void { churn_ = 0; }

  private:
    storage<Key, Capacity>   keys_;
    storage<Value, Capacity> values_;
    mutable usize            churn_{0};
};

// Auto hash set
template <typename Key, usize Capacity, usize RehashLimit>
class hash_table_storage<Key, void, Capacity, true, RehashLimit> {
  public:
    [[nodiscard]] constexpr auto key_data(this auto&& self) noexcept -> auto* {
        return self.keys_.data();
    }
    [[nodiscard]] constexpr auto value_data(this auto&&) noexcept -> auto* { return nullptr; }

    // `reset_churn` must be called manually
    [[nodiscard]] constexpr auto needs_rehash() const noexcept -> bool {
        return ++churn_ >= RehashLimit;
    }

    constexpr auto reset_churn() const noexcept -> void { churn_ = 0; }

  private:
    storage<Key, Capacity> keys_;
    mutable usize          churn_{0};
};

// Base hash map
template <typename Key, usize Capacity, usize RehashLimit>
class hash_table_storage<Key, void, Capacity, false, RehashLimit> {
  public:
    [[nodiscard]] constexpr auto key_data(this auto&& self) noexcept -> auto* {
        return self.keys_.data();
    }
    [[nodiscard]] constexpr auto value_data(this auto&&) noexcept -> auto* { return nullptr; }

    [[nodiscard]] constexpr auto needs_rehash() const noexcept -> bool { return false; }
    constexpr auto               reset_churn() const noexcept -> void {}

  private:
    storage<Key, Capacity> keys_;
};

// Base hash set
template <typename Key, typename Value, usize Capacity, usize RehashLimit>
class hash_table_storage<Key, Value, Capacity, false, RehashLimit> {
  public:
    [[nodiscard]] constexpr auto key_data(this auto&& self) noexcept -> auto* {
        return self.keys_.data();
    }

    [[nodiscard]] constexpr auto value_data(this auto&& self) noexcept -> auto* {
        return self.values_.data();
    }

    [[nodiscard]] constexpr auto needs_rehash() const noexcept -> bool { return false; }
    constexpr auto               reset_churn() const noexcept -> void {}

  private:
    storage<Key, Capacity>   keys_;
    storage<Value, Capacity> values_;
};

template <typename Key, typename Value> struct hash_table_iterator_value_t {
    using type = std::pair<const Key, Value>;
};

template <typename Key> struct hash_table_iterator_value_t<Key, void> {
    using type = const Key;
};

template <typename Key, typename Value> struct hash_table_iterator_reference_t {
    using type = std::pair<const Key&, Value&>;
};

template <typename Key> struct hash_table_iterator_reference_t<Key, void> {
    using type = const Key&;
};

template <typename Key> struct hash_table_iterator_reference_t<Key, const void> {
    using type = const Key&;
};

// Facilitates const and non-const behavior
template <typename HashTableSelf, typename Key, typename Value, usize Capacity>
class hash_table_iterator {
  public:
    using iterator_category = std::forward_iterator_tag;
    using value_type        = hash_table_iterator_value_t<Key, Value>::type;
    using difference_type   = idiff;
    using pointer           = void;
    using reference =
        hash_table_iterator_reference_t<Key, const_dispatch_t<HashTableSelf, Value>>::type;

    // Facilitates `->` operator usage without violating memory safety
    struct proxy {
        reference value;

        [[nodiscard]] constexpr auto operator->() const noexcept -> const reference* {
            return &value;
        }
    };

  public:
    constexpr hash_table_iterator() noexcept = default;
    constexpr hash_table_iterator(HashTableSelf& ht, usize index) noexcept
        : ht_{&ht}, index_{index} {
        next();
    }

    // The index is always advanced up to the next occupied slot
    [[nodiscard]] constexpr auto operator++() -> hash_table_iterator& {
        if (index_ < Capacity) {
            index_++;
            next();
        }
        return *this;
    }

    [[nodiscard]] constexpr auto operator++(int) -> hash_table_iterator {
        hash_table_iterator it{*this};
        ++(*this);
        return it;
    }

    [[nodiscard]] constexpr auto operator*() const noexcept -> reference {
        ASSERT(ht_, "Attempt to dereference null hash map");
        if constexpr (std::same_as<void, Value>) {
            return reference{*(ht_->key_data() + index_)};
        } else {
            return reference{*(ht_->key_data() + index_), *(ht_->value_data() + index_)};
        }
    }

    [[nodiscard]] constexpr auto operator->() const noexcept -> proxy { return {operator*()}; }

    [[nodiscard]] constexpr auto operator==(const hash_table_iterator& other) const noexcept
        -> bool {
        return ht_ == other.ht_ && index_ == other.index_;
    }

    [[nodiscard]] constexpr auto operator==(std::default_sentinel_t) const noexcept -> bool {
        return index_ >= Capacity;
    }

  private:
    constexpr auto next() noexcept -> void {
        if (!ht_) { return; }
        const auto metadata{ht_->get_metadata()};
        while (index_ < Capacity && !metadata[index_].is_used()) { index_++; }
    }

  private:
    HashTableSelf* ht_{nullptr};
    usize          index_{0};
};

// Heavily inspired by Zig's hash map implementation and trevor's C version:
// https://github.com/trevorswan11/ghoti/blob/4577f3279f5ab09e32a13b8cacb044da686e64bd/src/util/containers/hash_map.c
template <typename Key,
          typename Value,
          usize Capacity,
          typename Hash,
          typename Equal,
          bool  AutoRehash,
          usize RehashLimit>
    requires(Capacity > 0 && is_power_of_two(Capacity) && !std::same_as<void, Key>)
class hash_table {
  public:
    static constexpr auto is_map = !std::same_as<void, Value>;
    using iterator               = hash_table_iterator<hash_table, Key, Value, Capacity>;
    using const_iterator = hash_table_iterator<std::add_const_t<hash_table>, Key, Value, Capacity>;

    struct emplace_result {
        // This is always a valid iterator, but it may point to a previously inserted item
        iterator it;
        bool     inserted;
    };

  public:
    constexpr hash_table() noexcept = default;
    constexpr ~hash_table() { clear(); }
    constexpr ~hash_table()
        requires(TriviallyDestructible<Key> && (TriviallyDestructible<Value> || !is_map))
    = default;

    constexpr hash_table(const hash_table&)
        requires(TriviallyCopyable<Key> && (TriviallyCopyable<Value> || !is_map))
    = default;

    constexpr hash_table(const hash_table& other) {
        for (usize i{0}; i < Capacity; ++i) {
            metadata_[i] = other.metadata_[i];
            if (metadata_[i].is_used()) {
                std::construct_at(key_data() + i, *(other.key_data() + i));
                if constexpr (is_map) {
                    std::construct_at(value_data() + i, *(other.value_data() + i));
                }
            }
        }
        size_ = other.size_;
    }

    constexpr auto operator=(const hash_table&) -> hash_table&
        requires(TriviallyCopyable<Key> && (TriviallyCopyable<Value> || !is_map))
    = default;

    constexpr auto operator=(const hash_table& other) -> hash_table& {
        if (this != &other) {
            hash_table temp{other};
            swap(temp);
        }
        return *this;
    }

    constexpr hash_table(hash_table&& other) noexcept {
        for (usize i{0}; i < Capacity; ++i) {
            metadata_[i] = other.metadata_[i];
            if (metadata_[i].is_used()) {
                std::construct_at(key_data() + i, std::move(*(other.key_data() + i)));
                if constexpr (is_map) {
                    std::construct_at(value_data() + i, std::move(*(other.value_data() + i)));
                }
            }
        }
        size_ = other.size_;
        other.clear();
    }

    constexpr auto operator=(hash_table&& other) noexcept -> hash_table& {
        if (this != &other) {
            clear();
            hash_table temp{std::move(other)};
            swap(temp);
        }
        return *this;
    }

    [[nodiscard]] constexpr auto get_metadata() const noexcept
        -> gsl::span<const hash_table_metadata> {
        return metadata_;
    }

    // Constructs a value at the key or updates it if there was already an item present
    template <typename K, typename... Args>
        requires(is_map)
    constexpr auto emplace(const K& key, Args&&... args) {
        return emplace_impl(key, true, std::forward<Args>(args)...);
    }

    // Constructs and inserts the key or updates it was already present
    template <typename K> constexpr auto emplace(const K& key) { return emplace_impl(key, true); }

    // Constructs a value at the key  only it if there was already an item present
    template <typename K, typename... Args>
        requires(is_map)
    constexpr auto try_emplace(const K& key, Args&&... args) {
        return emplace_impl(key, false, std::forward<Args>(args)...);
    }

    // Constructs and inserts the key only if it was not present
    template <typename K> constexpr auto try_emplace(const K& key) {
        return emplace_impl(key, false);
    }

    template <typename K> constexpr auto contains(const K& key) const noexcept -> bool {
        return index_of(key).has_value();
    }

    // Returns a reference to the value at the key if present
    template <typename K>
        requires(is_map)
    [[nodiscard]] constexpr auto get(this auto&& self, const K& key) noexcept -> auto& {
        const auto idx{self.index_of(key)};
        ASSERT(idx, "Illegal get on missing key");
        return *(self.value_data() + *idx);
    }

    // Returns a reference to the value at the key or none if the key is not present
    template <typename K, typename Self>
        requires(is_map)
    [[nodiscard]] constexpr auto get_opt(this Self&& self, const K& key) noexcept
        -> option<const_dispatch_t<Self, Value>&> {
        if (const auto idx{self.index_of(key)}) { return *(self.value_data() + *idx); }
        return none;
    }

    // Removes the key value pair from the map, NOOP if not present
    template <typename K> constexpr auto remove(const K& key) noexcept -> void {
        const auto idx{index_of(key)};
        if (!idx) { return; }

        std::destroy_at(key_data() + *idx);
        if constexpr (is_map) { std::destroy_at(value_data() + *idx); }

        metadata_[*idx].bury();
        size_ -= 1;

        if (storage_.needs_rehash()) { rehash(); }
    }

    [[nodiscard]] constexpr auto        empty() const noexcept -> bool { return size_ == 0; }
    [[nodiscard]] constexpr auto        size() const noexcept -> usize { return size_; }
    [[nodiscard]] static constexpr auto capacity() noexcept -> usize { return Capacity; }

    template <typename Self> [[nodiscard]] constexpr auto begin(this Self&& self) noexcept {
        return hash_table_iterator<std::remove_reference_t<Self>, Key, Value, Capacity>{self, 0};
    }

    template <typename Self> [[nodiscard]] constexpr auto end(this Self&& self) noexcept {
        return hash_table_iterator<std::remove_reference_t<Self>, Key, Value, Capacity>{self,
                                                                                        Capacity};
    }

    [[nodiscard]] constexpr auto key_data(this auto&& self) noexcept -> auto* {
        return self.storage_.key_data();
    }

    [[nodiscard]] constexpr auto value_data(this auto&& self) noexcept -> auto* {
        return self.storage_.value_data();
    }

    // Destroys all key-value pairs and resets the tracked size
    constexpr auto clear() noexcept -> void {
        if constexpr (!TriviallyDestructible<Key> || !TriviallyDestructible<Value>) {
            for (usize i{0}; i < Capacity; ++i) {
                if (metadata_[i].is_used()) {
                    if constexpr (!TriviallyDestructible<Key>) { std::destroy_at(key_data() + i); }
                    if constexpr (is_map && !TriviallyDestructible<Value>) {
                        std::destroy_at(value_data() + i);
                    }
                }
            }
        }

        for (auto& m : metadata_) { m = hash_table_metadata::make_open_slot(); }
        size_ = 0;
    }

    // Rehashes the hash map in place.
    //
    // Useful when doing many insert/release cycles to clean tombstones
    constexpr auto rehash() noexcept -> void {
        // Nearly identical to C reference
        storage_.reset_churn();
        if (size_ == 0) {
            for (auto& m : metadata_) { m = hash_table_metadata::make_open_slot(); }
            return;
        }

        // Open up all metadata for temporary tracking
        for (auto& metadata : metadata_) {
            metadata =
                hash_table_metadata{hash_table_metadata::fingerprint::OPEN, metadata.is_used()};
        }

        // For each bucket, rehash to an index:
        // 1) before the cursor, probed into a free slot, or
        // 2) equal to the cursor, no need to move, or
        // 3) ahead of the cursor, probing over already rehashed
        usize current{0};
        while (current < Capacity) {
            if (!metadata_[current].is_used() && !metadata_[current].is_tombstone()) {
                current += 1;
                continue;
            }

            const auto hashed{Hash{}(*(key_data() + current))};
            const auto fingerprint{hash_table_metadata::take_fingerprint(hashed)};
            usize      probe{static_cast<usize>(hashed & HASH_MASK)};

            // Resolve probing conflicts
            while ((probe < current && metadata_[probe].is_used()) ||
                   (probe > current && metadata_[probe].is_tombstone())) {
                probe = (probe + 1) & HASH_MASK;
            }

            if (probe < current) {
                std::construct_at(key_data() + probe, std::move(*(key_data() + current)));
                std::destroy_at(key_data() + current);

                if constexpr (is_map) {
                    std::construct_at(value_data() + probe, std::move(*(value_data() + current)));
                    std::destroy_at(value_data() + current);
                }

                metadata_[probe].fill(fingerprint);
                metadata_[current].open_up();
            } else if (probe == current) {
                metadata_[probe].fill(fingerprint);
            } else {
                if (metadata_[probe].is_used()) {
                    using std::swap;
                    swap(*(key_data() + current), *(key_data() + probe));
                    if constexpr (is_map) {
                        swap(*(value_data() + current), *(value_data() + probe));
                    }

                    metadata_[probe].bury();
                    continue;
                }

                std::construct_at(key_data() + probe, std::move(*(key_data() + current)));
                std::destroy_at(key_data() + current);

                if constexpr (is_map) {
                    std::construct_at(value_data() + probe, std::move(*(value_data() + current)));
                    std::destroy_at(value_data() + current);
                }

                metadata_[probe].bury();
                metadata_[probe] = hash_table_metadata(metadata_[probe].get_fingerprint(), true);
                metadata_[current].open_up();
            }

            current += 1;
        }

        // Finalize by converting the graveyard into real fingerprints
        for (usize i{0}; auto& metadata : metadata_) {
            if (metadata.is_tombstone()) {
                const auto hashed = Hash{}(*(key_data() + i));
                metadata.fill(hash_table_metadata::take_fingerprint(hashed));
            }
            i++;
        }
    }

  private:
    static constexpr usize HASH_MASK{Capacity - 1};

  private:
    // This is needed for a deduplicated index_of to 'ignore' -Wconversion
    template <typename K>
    [[nodiscard]] static constexpr auto normalize_key(const K& key) noexcept -> decltype(auto) {
        if constexpr (std::is_arithmetic_v<Key> && std::is_arithmetic_v<std::remove_cvref_t<K>>) {
            return static_cast<Key>(key);
        } else {
            return key;
        }
    }

    template <typename K, typename... Args>
    [[nodiscard]] constexpr auto emplace_impl(const K& key, bool overwrite_existing, Args&&... args)
        -> emplace_result {
        decltype(auto) normalized_key{normalize_key(key)};
        const auto     hashed{Hash{}(normalized_key)};
        const auto     fingerprint{hash_table_metadata::take_fingerprint(hashed)};

        usize limit{Capacity};
        usize first_tombstone_idx{Capacity};
        usize probe{static_cast<usize>(hashed & HASH_MASK)};

        auto m{metadata_[probe]};
        while (!m.is_open() && limit != 0) {
            if (m.is_used() && m.get_fingerprint() == fingerprint) {
                if ((Equal{}(*(key_data() + probe), normalized_key))) {
                    if (overwrite_existing) {
                        std::destroy_at(key_data() + probe);
                        std::construct_at(key_data() + probe, normalized_key);
                    }

                    if constexpr (is_map) {
                        if (overwrite_existing) {
                            std::destroy_at(value_data() + probe);
                            std::construct_at(value_data() + probe, std::forward<Args>(args)...);
                        }
                    }
                    return {iterator{*this, probe}, overwrite_existing};
                }
            } else if (first_tombstone_idx == Capacity && m.is_tombstone()) {
                first_tombstone_idx = probe;
            }

            limit -= 1;
            probe = (probe + 1) & HASH_MASK;
            m     = metadata_[probe];
        }

        // It's cheaper to lower probing distance after deletions by recycling a tombstone
        if (first_tombstone_idx < Capacity) { probe = first_tombstone_idx; }
        ASSERT(limit != 0, "HashMap is full");
        metadata_[probe].fill(fingerprint);
        size_ += 1;

        std::construct_at(key_data() + probe, normalized_key);
        if constexpr (is_map) {
            std::construct_at(value_data() + probe, std::forward<Args>(args)...);
        }
        return {iterator{*this, probe}, true};
    }

    template <typename K> constexpr auto index_of(const K& key) const noexcept -> option<usize> {
        if (size_ == 0) { return none; }
        decltype(auto) normalized_key{normalize_key(key)};

        const auto hashed{Hash{}(normalized_key)};
        const auto fingerprint{hash_table_metadata::take_fingerprint(hashed)};

        usize limit{Capacity};
        usize probe{static_cast<usize>(hashed & HASH_MASK)};

        auto m{metadata_[probe]};
        while (!m.is_open() && limit != 0) {
            if (m.is_used() && m.get_fingerprint() == fingerprint) {
                if (Equal{}(*(key_data() + probe), normalized_key)) { return probe; }
            }

            limit -= 1;
            probe = (probe + 1) & HASH_MASK;
            m     = metadata_[probe];
        }
        return none;
    }

    // https://en.cppreference.com/cpp/algorithm/swap
    constexpr auto swap(hash_table& other) noexcept -> void {
        using std::swap;
        for (usize i{0}; i < Capacity; ++i) {
            const bool lhs_used{metadata_[i].is_used()};
            const bool rhs_used{other.metadata_[i].is_used()};

            // Metadata swap should always be done since it governs state
            swap(metadata_[i], other.metadata_[i]);

            // There's 3 state cases that need to be handled differently
            if (lhs_used && rhs_used) {
                swap(*(key_data() + i), *(other.key_data() + i));
                if constexpr (is_map) { swap(*(value_data() + i), *(other.value_data() + i)); }
            } else if (lhs_used && !rhs_used) {
                std::construct_at(other.key_data() + i, std::move(*(key_data() + i)));
                std::destroy_at(key_data() + i);

                if constexpr (is_map) {
                    std::construct_at(other.value_data() + i, std::move(*(value_data() + i)));
                    std::destroy_at(value_data() + i);
                }
            } else if (!lhs_used && rhs_used) {
                std::construct_at(key_data() + i, std::move(*(other.key_data() + i)));
                std::destroy_at(other.key_data() + i);

                if constexpr (is_map) {
                    std::construct_at(value_data() + i, std::move(*(other.value_data() + i)));
                    std::destroy_at(other.value_data() + i);
                }
            }
        }
        swap(size_, other.size_);
    }

    // ADL dispatcher for copy assignment
    constexpr friend auto swap(hash_table& lhs, hash_table& rhs) noexcept -> void { lhs.swap(rhs); }

  private:
    std::array<hash_table_metadata, Capacity>                         metadata_{};
    hash_table_storage<Key, Value, Capacity, AutoRehash, RehashLimit> storage_;
    usize                                                             size_{0};
};

} // namespace detail

// A fixed-size zero-allocation container supporting hash-map operations
template <typename Key,
          typename Value,
          usize Capacity,
          typename Hash = std::conditional_t<StringLike<Key>, crc::hash<Key>, hash<Key>>,
          typename Compare =
              std::conditional_t<StringLike<Key>, string_transparent_eq<Key>, std::equal_to<Key>>>
using hash_map =
    detail::hash_table<Key, Value, ceil_power_of_two(Capacity), Hash, Compare, false, 0>;

// Construct a hash map from a list of pairs
template <InsertablePair... Pairs>
    requires(sizeof...(Pairs) > 0)
[[nodiscard]] constexpr auto make_hash_map(Pairs&&... kv_pairs) noexcept {
    using std::get;
    hash_map<common_tuple_type_t<0, Pairs...>, common_tuple_type_t<1, Pairs...>, sizeof...(Pairs)>
        map;
    (...,
     map.emplace(get<0>(std::forward<decltype(kv_pairs)>(kv_pairs)),
                 get<1>(std::forward<decltype(kv_pairs)>(kv_pairs))));
    return map;
}

// A fixed-size zero-allocation container supporting hash-set operations
template <typename Key,
          usize Capacity,
          typename Hash = std::conditional_t<StringLike<Key>, crc::hash<Key>, hash<Key>>,
          typename Compare =
              std::conditional_t<StringLike<Key>, string_transparent_eq<Key>, std::equal_to<Key>>>
using hash_set =
    detail::hash_table<Key, void, ceil_power_of_two(Capacity), Hash, Compare, false, 0>;

// Construct a hash set from a list of keys
template <typename... Keys>
    requires(sizeof...(Keys) > 0)
[[nodiscard]] constexpr auto make_hash_set(Keys&&... keys) noexcept {
    using std::get;
    hash_set<std::common_type_t<std::decay_t<Keys>...>, sizeof...(Keys)> set;
    (..., set.emplace(std::forward<Keys>(keys)));
    return set;
}

// A fixed-size zero-allocation container supporting hash-map operations and automatic rehashing
template <typename Key,
          typename Value,
          usize Capacity,
          typename Hash = std::conditional_t<StringLike<Key>, crc::hash<Key>, hash<Key>>,
          typename Compare =
              std::conditional_t<StringLike<Key>, string_transparent_eq<Key>, std::equal_to<Key>>,
          usize RehashLimit = Capacity / 2 == 0 ? 1UZ : Capacity / 2>
using auto_hash_map =
    detail::hash_table<Key, Value, ceil_power_of_two(Capacity), Hash, Compare, true, RehashLimit>;

// Construct an auto hash map from a list of pairs
template <InsertablePair... Pairs>
    requires(sizeof...(Pairs) > 0)
[[nodiscard]] constexpr auto make_auto_hash_map(Pairs&&... kv_pairs) noexcept {
    using std::get;
    auto_hash_map<common_tuple_type_t<0, Pairs...>,
                  common_tuple_type_t<1, Pairs...>,
                  sizeof...(Pairs)>
        map;
    (...,
     map.emplace(get<0>(std::forward<decltype(kv_pairs)>(kv_pairs)),
                 get<1>(std::forward<decltype(kv_pairs)>(kv_pairs))));
    return map;
}

// A fixed-size zero-allocation container supporting hash-set operations and automatic rehashing
template <typename Key,
          usize Capacity,
          typename Hash = std::conditional_t<StringLike<Key>, crc::hash<Key>, hash<Key>>,
          typename Compare =
              std::conditional_t<StringLike<Key>, string_transparent_eq<Key>, std::equal_to<Key>>,
          usize RehashLimit = Capacity / 2 == 0 ? 1UZ : Capacity / 2>
using auto_hash_set =
    detail::hash_table<Key, void, ceil_power_of_two(Capacity), Hash, Compare, true, RehashLimit>;

// Construct an auto hash set from a list of keys
template <typename... Keys>
    requires(sizeof...(Keys) > 0)
[[nodiscard]] constexpr auto make_auto_hash_set(Keys&&... keys) noexcept {
    using std::get;
    auto_hash_set<std::common_type_t<std::decay_t<Keys>...>, sizeof...(Keys)> set;
    (..., set.emplace(std::forward<Keys>(keys)));
    return set;
}

} // namespace stdx::fixed
