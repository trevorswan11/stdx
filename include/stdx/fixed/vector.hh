#pragma once

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <memory>
#include <utility>

#include <gsl/span>

#include "stdx/assert.hh"
#include "stdx/fixed/storage.hh"
#include "stdx/type_traits.hh"
#include "stdx/types.hh"

namespace stdx::fixed {

// A fixed-size zero-allocation container with a vector-like interface
template <typename Item, usize Capacity>
    requires(Capacity > 0)
class vector {
  public:
    using value_type      = Item;
    using size_type       = usize;
    using reference       = Item&;
    using const_reference = const Item&;
    using iterator        = Item*;
    using const_iterator  = const Item*;

  public:
    vector() = default;
    ~vector() { clear(); }
    ~vector()
        requires TriviallyDestructible<Item>
    = default;

    // Constructs the vector in place by emplacing each item into the buffer
    template <typename... Is>
        requires(sizeof...(Is) <= Capacity)
    constexpr explicit vector(Is&&... items) {
        (..., emplace_back(std::forward<Is>(items)));
    }

    constexpr vector(const vector&)
        requires TriviallyCopyable<Item>
    = default;

    constexpr vector(const vector& other) {
        if constexpr (TriviallyCopyable<Item>) {
            size_ = other.size_;
            std::copy(other.begin(), other.end(), data());
        } else {
            for (const auto& item : other) { emplace_back(item); }
        }
    }

    constexpr auto operator=(const vector&) -> vector&
        requires TriviallyCopyable<Item>
    = default;

    constexpr auto operator=(const vector& other) -> vector& {
        if (this != &other) {
            vector temp{other};
            swap(temp);
        }
        return *this;
    }

    constexpr vector(vector&& other) noexcept {
        if constexpr (TriviallyCopyable<Item>) {
            size_ = other.size_;
            std::copy(other.begin(), other.end(), data());
        } else {
            for (auto& item : other) { emplace_back(std::move(item)); }
        }
        other.clear();
    }

    constexpr auto operator=(vector&& other) noexcept -> vector& {
        if (this != &other) {
            clear();
            if constexpr (TriviallyCopyable<Item>) {
                size_ = other.size_;
                std::copy(other.begin(), other.end(), data());
            } else {
                for (auto& item : other) { emplace_back(std::move(item)); }
            }
            other.clear();
        }
        return *this;
    }

    // Constructs an object in place at the end of the vector with the provided args
    template <typename... Args> constexpr auto emplace_back(Args&&... args) -> void {
        ASSERT(size_ < Capacity, "size out of range");
        std::construct_at(data() + size_, std::forward<Args>(args)...);
        size_++;
    }

    constexpr auto push_back(const Item& item) -> void { emplace_back(item); }
    constexpr auto push_back(Item&& item) -> void { emplace_back(std::move(item)); }

    constexpr auto pop_back() noexcept -> void {
        ASSERT(size_ > 0, "pop_back on empty vector");
        std::destroy_at(data() + --size_);
    }

    [[nodiscard]] constexpr auto front(this auto&& self) noexcept -> decltype(auto) {
        ASSERT(self.size_ > 0, "front on empty vector");
        return self.data()[0];
    }

    [[nodiscard]] constexpr auto back(this auto&& self) noexcept -> decltype(auto) {
        ASSERT(self.size_ > 0, "back on empty vector");
        return self.data()[self.size_ - 1];
    }

    // Removes the element at `pos`, shifting the tail down one slot
    //
    // Returns an iterator to the element that followed the erased one (or end())
    constexpr auto erase(iterator pos) -> iterator {
        ASSERT(pos >= begin() && pos < end(), "erase position out of range");
        std::move(pos + 1, end(), pos);
        std::destroy_at(data() + --size_);
        return pos;
    }

    // Grows (constructing and copying a value) or shrinks the vector
    //
    // The value is never constructed if shrinking or if the size if unchanging
    template <typename... Args> constexpr auto resize(usize new_size, Args&&... args) -> void {
        if (size_ >= new_size) {
            while (size_ > new_size) { pop_back(); }
            return;
        }

        ASSERT(new_size <= Capacity, "resize beyond capacity");
        Item value{std::forward<Args>(args)...};
        while (size_ < new_size) { push_back(value); }
    }

    [[nodiscard]] constexpr explicit operator gsl::span<Item>() noexcept { return {data(), size_}; }
    [[nodiscard]] constexpr explicit operator gsl::span<const Item>() const noexcept {
        return {data(), size_};
    }

    [[nodiscard]] constexpr auto operator[](this auto&& self, usize idx) noexcept
        -> decltype(auto) {
        ASSERT(idx < self.size_, "index out of bounds");
        return self.data()[idx];
    }

    [[nodiscard]] constexpr auto begin(this auto&& self) noexcept -> auto* { return self.data(); }
    [[nodiscard]] constexpr auto end(this auto&& self) noexcept -> auto* {
        return self.data() + self.size_;
    }

    [[nodiscard]] constexpr auto empty() const noexcept -> bool { return size_ == 0; }
    [[nodiscard]] constexpr auto size() const noexcept -> usize { return size_; }
    [[nodiscard]] constexpr auto capacity() const noexcept -> usize { return Capacity; }

    [[nodiscard]] constexpr auto data(this auto&& self) noexcept -> auto* {
        return self.items_.data();
    }

    constexpr auto clear() noexcept -> void {
        if constexpr (!TriviallyDestructible<Item>) {
            // The lion is now concerned with freeing non-trivial resources
            for (usize i{0}; i < size_; ++i) { std::destroy_at(data() + i); }
        }
        size_ = 0;
    }

  private:
    // https://en.cppreference.com/cpp/algorithm/swap
    constexpr auto swap(vector& other) noexcept -> void
        requires(!TriviallyCopyable<Item>)
    {
        auto& smaller{(size_ < other.size_) ? *this : other};
        auto& larger{(size_ < other.size_) ? other : *this};

        std::swap_ranges(smaller.begin(), smaller.end(), larger.begin());
        const auto smaller_size{smaller.size_};
        const auto larger_size{larger.size_};

        // Manually destroy the moved-from object after moving it
        for (usize i{smaller_size}; i < larger_size; ++i) {
            smaller.emplace_back(std::move(larger[i]));
            std::destroy_at(larger.data() + i);
        }

        smaller.size_ = larger_size;
        larger.size_  = smaller_size;
    }

  private:
    detail::storage<Item, Capacity> items_;
    usize                           size_{0};
};

} // namespace stdx::fixed
