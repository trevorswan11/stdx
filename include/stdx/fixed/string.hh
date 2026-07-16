#pragma once

#include <ostream>
#include <string>
#include <string_view>

#include <ankerl/unordered_dense.h>
#include <fmt/base.h>
#include <fmt/format.h>

#include "stdx/assert.hh"
#include "stdx/memory.hh"
#include "stdx/option.hh"
#include "stdx/type_traits.hh"
#include "stdx/types.hh"

namespace stdx::fixed {

// A dynamically allocated string that is not resizable without recreation
template <typename CharT> class basic_string {
  public:
    using str_t = std::basic_string<CharT>;
    using sv_t  = std::basic_string_view<CharT>;

    using iterator        = CharT*;
    using const_iterator  = const CharT*;
    using value_type      = CharT;
    using traits_type     = std::char_traits<CharT>;
    using size_type       = usize;
    using difference_type = idiff;
    using pointer         = CharT*;
    using const_pointer   = const CharT*;
    using reference       = CharT&;
    using const_reference = const CharT&;

  public:
    constexpr basic_string() noexcept = default;
    ~basic_string()                   = default;

    basic_string(const CharT* c_str) : basic_string{sv_t{c_str}} {}

    basic_string(sv_t sv) {
        if (!sv.empty()) {
            size_ = sv.size();
            data_ = stdx::make_nullable_box<CharT[]>(size_ + 1);
            std::copy_n(sv.data(), size_, data_.get());
            data_[size_] = '\0';
        }
    }

    basic_string(str_t&& str) {
        if (!str.empty()) {
            size_ = str.size();
            data_ = stdx::make_nullable_box<CharT[]>(size_ + 1);
            std::copy_n(str.data(), size_, data_.get());
            data_[size_] = '\0';
            str.clear();
        }
    }

    basic_string(const basic_string& other) : size_{other.size_} {
        if (size_ > 0) {
            data_ = stdx::make_nullable_box<CharT[]>(size_ + 1);
            std::copy_n(other.data(), size_ + 1, data_.get());
        }
    }

    auto operator=(const basic_string& other) -> basic_string& {
        if (this != &other) {
            size_ = other.size_;
            if (size_ == 0) {
                data_.reset();
            } else {
                data_ = stdx::make_nullable_box<CharT[]>(size_ + 1);
                std::copy_n(other.data(), size_ + 1, data_.get());
            }
        }
        return *this;
    }

    basic_string(basic_string&& other) noexcept
        : data_{std::move(other.data_)}, size_{other.size_} {
        other.size_ = 0;
    }

    auto operator=(basic_string&& other) noexcept -> basic_string& {
        if (this != &other) {
            data_       = std::move(other.data_);
            size_       = other.size_;
            other.size_ = 0;
        }
        return *this;
    }

    // Always returns a valid, null-terminated pointer (never nullptr)
    [[nodiscard]] auto c_str() const noexcept -> const CharT* {
        return data_ ? data_.get() : empty_string;
    }

    // This is a raw accessor that might be null, see `c_str` for a valid pointer
    [[nodiscard]] auto data(this auto&& self) -> auto* { return self.data_.get(); }
    [[nodiscard]] auto size() const noexcept -> usize { return size_; }
    [[nodiscard]] auto empty() const noexcept -> bool { return size_ == 0; }
    [[nodiscard]] auto front(this auto&& self) noexcept -> auto& {
        ASSERT(!self.empty(), "front called on empty fixed::basic_string");
        return self.data()[0];
    }

    [[nodiscard]] auto back(this auto&& self) noexcept -> auto& {
        ASSERT(!self.empty(), "back called on empty fixed::basic_string");
        return self.data()[self.size_ - 1];
    }

    [[nodiscard]] auto begin() const noexcept -> const_iterator { return c_str(); }
    [[nodiscard]] auto end() const noexcept -> const_iterator { return c_str() + size_; }
    [[nodiscard]] auto cbegin() const noexcept -> const_iterator { return begin(); }
    [[nodiscard]] auto cend() const noexcept -> const_iterator { return end(); }

    [[nodiscard]] auto view() const noexcept -> sv_t { return {c_str(), size_}; }
    [[nodiscard]]      operator sv_t() const noexcept { return view(); }

    [[nodiscard]] auto operator[](this auto&& self, usize idx) noexcept -> auto& {
        ASSERT(idx < self.size_, "index out of range");
        return self.data()[idx];
    }

    template <typename Self> [[nodiscard]] constexpr auto at(this Self&& self, usize idx) noexcept {
        using opt_t = stdx::option<const_dispatch_t<Self, CharT>&>;
        if (idx < self.size_) { return opt_t{self.data()[idx]}; }
        return opt_t{};
    }

    template <typename Self>
    [[nodiscard]] constexpr auto find(this Self&& self, CharT ch) noexcept {
        using opt_t = stdx::option<const_dispatch_t<Self, CharT>&>;
        for (usize i{0}; i < self.size_; ++i) {
            if (self.data()[i] == ch) { return opt_t{self.data()[i]}; }
        }
        return opt_t{};
    }

    [[nodiscard]] constexpr auto contains(CharT ch) const noexcept -> bool {
        return view().contains(ch);
    }

    [[nodiscard]] constexpr auto contains(sv_t sv) const noexcept -> bool {
        return view().contains(sv);
    }

    [[nodiscard]] friend auto operator<=>(const basic_string& lhs,
                                          const basic_string& rhs) noexcept {
        return lhs.view() <=> rhs.view();
    }

    [[nodiscard]] friend auto operator==(const basic_string& lhs,
                                         const basic_string& rhs) noexcept {
        return lhs.view() == rhs.view();
    }

    [[nodiscard]] friend auto operator<=>(const basic_string& lhs, sv_t rhs) noexcept {
        return lhs.view() <=> rhs;
    }

    [[nodiscard]] friend auto operator==(const basic_string& lhs, sv_t rhs) noexcept {
        return lhs.view() == rhs;
    }

    [[nodiscard]] friend auto operator<=>(const basic_string& lhs, const CharT* rhs) noexcept {
        return lhs.view() <=> rhs;
    }

    [[nodiscard]] friend auto operator==(const basic_string& lhs, const CharT* rhs) noexcept {
        return lhs.view() == rhs;
    }

    friend auto operator<<(std::basic_ostream<CharT, traits_type>& os,
                           const basic_string<CharT>&              str)
        -> std::basic_ostream<CharT, traits_type>& {
        return os << str.view();
    }

  private:
    static constexpr CharT empty_string[1]{CharT{}};

  private:
    nullable_box<CharT[]> data_;
    usize                 size_{0};
};

using string  = basic_string<char>;
using wstring = fixed::basic_string<wchar_t>;

} // namespace stdx::fixed

template <typename CharT> struct ankerl::unordered_dense::hash<stdx::fixed::basic_string<CharT>> {
    using string = stdx::fixed::basic_string<CharT>;
    static auto operator()(const string& str) noexcept {
        return ankerl::unordered_dense::hash<typename string::sv_t>{}(str.view());
    }
};

template <typename CharT>
struct fmt::formatter<stdx::fixed::basic_string<CharT>, CharT>
    : fmt::formatter<std::basic_string_view<CharT>, CharT> {
    template <typename FormatContext>
    auto format(const stdx::fixed::basic_string<CharT>& str, FormatContext& ctx) const {
        return fmt::formatter<std::basic_string_view<CharT>, CharT>::format(str.view(), ctx);
    }
};
