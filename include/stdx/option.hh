#pragma once

#include <concepts>
#include <functional>
#include <limits>
#include <optional>
#include <type_traits>
#include <utility>

#include <ankerl/unordered_dense.h>

#include "stdx/assert.hh"
#include "stdx/type_traits.hh"
#include "stdx/types.hh"

namespace stdx {

template <typename T> struct nullable;

// When true, allows the type to be used in a compact optional representation
template <typename T>
concept Compactable = !Reference<T> && requires(const T& t) {
    { nullable<T>::invalid() } -> std::same_as<T>;
    { nullable<T>::is_valid(t) } -> std::same_as<bool>;
};

template <ScopedEnum E> struct nullable<E> {
    [[nodiscard]] static constexpr auto invalid() noexcept -> E {
        return static_cast<E>(std::numeric_limits<std::underlying_type_t<E>>::max());
    }

    [[nodiscard]] static constexpr auto is_valid(const E& e) noexcept -> bool {
        return e != invalid();
    }
};

using none_t = std::nullopt_t;
constexpr none_t none{std::nullopt}; // NOLINT

namespace detail {

template <typename T> class ref {
  public:
    // cppcheck-suppress-begin noExplicitConstructor
    constexpr ref() noexcept : ptr_{nullptr} {}
    constexpr ref(none_t) noexcept : ptr_{nullptr} {}
    constexpr ref(T& ref) noexcept : ptr_{&ref} {}
    constexpr ref(T* ref) noexcept : ptr_{ref} {}
    ref(T&&) = delete;

    template <typename U>
        requires std::convertible_to<U*, T*>
    constexpr ref(const ref<U>& other) noexcept
        : ptr_{other.has_value() ? other.operator->() : nullptr} {}
    // cppcheck-suppress-end noExplicitConstructor

    [[nodiscard]] constexpr auto     has_value() const noexcept -> bool { return ptr_ != nullptr; }
    [[nodiscard]] constexpr explicit operator bool() const noexcept { return has_value(); }

    constexpr auto emplace(T& t) noexcept -> void { ptr_ = &t; }
    constexpr auto emplace(T* t) noexcept -> void { ptr_ = t; }
    constexpr auto reset() noexcept -> void { ptr_ = nullptr; }

    // Resets the optional and returns the stored reference
    [[nodiscard]] constexpr auto take() noexcept -> T* {
        ASSERT(ptr_, "Attempt to access empty optional reference");
        auto* ptr = ptr_;
        reset();
        return ptr;
    }

    [[nodiscard]] constexpr auto value() const noexcept -> T& { return *get(); }
    [[nodiscard]] constexpr auto get() const noexcept -> T* {
        ASSERT(has_value(), "Attempt to access empty optional reference");
        return ptr_;
    }

    [[nodiscard]] constexpr auto operator->() const noexcept -> T* { return get(); }
    [[nodiscard]] constexpr auto operator*() const noexcept -> T& { return *get(); }

    // Applies F to to underlying reference if present
    template <typename F> [[nodiscard]] constexpr auto transform(this auto&& self, F&& f) {
        using res_cv = std::invoke_result_t<F, T&>;
        using res    = std::remove_cv_t<res_cv>;

        // This is straight from clang's stdc++ C++23 optional implementation
        static_assert(!std::is_array_v<res>, "Result of f(value()) should not be an Array");
        static_assert(!std::is_same_v<res, std::in_place_t>,
                      "Result of f(value()) should not be std::in_place_t");
        static_assert(!std::is_same_v<res, none_t>,
                      "Result of f(value()) should not be stdx::none");

        // Also from clang, but generalized to support reference transform chains
        using ret = std::conditional_t<std::is_reference_v<res_cv>,
                                       ref<std::remove_reference_t<res_cv>>,
                                       std::optional<res_cv>>;
        if (self.has_value()) { return ret{std::forward<F>(f)(self.value())}; }
        return ret{};
    }

    template <typename Or>
        requires requires(T& t) { static_cast<Or&>(t); }
    [[nodiscard]] constexpr auto value_or(this auto&& self, Or& or_value) -> T& {
        return self.has_value() ? *self.get() : static_cast<T&>(or_value);
    }

    // Creates a copy of the underlying data and forwards it to the standard optional
    [[nodiscard]] constexpr auto materialize() const noexcept
        requires CopyConstructible<T>
    {
        return has_value() ? std::optional<std::remove_const_t<T>>{*ptr_} : none;
    }

    // Pointer comparison (just checks memory addresses)
    [[nodiscard]] constexpr auto operator==(const ref&) const noexcept -> bool = default;

  private:
    T* ptr_;
};

// Returns the Ref version of the optional type if required
template <typename T>
using dispatch_opt =
    std::conditional_t<Reference<T>, ref<std::remove_reference_t<T>>, std::optional<T>>;

// An efficient optional enum representation for enums with a sentinel value
template <Compactable T> class compact_opt {
  public:
    // cppcheck-suppress-begin noExplicitConstructor
    constexpr compact_opt() noexcept : value_{NO_VALUE} {}
    constexpr compact_opt(const T& value) noexcept : value_{value} {}
    constexpr compact_opt(none_t) noexcept : value_{NO_VALUE} {}
    constexpr compact_opt(const std::optional<T>& opt) noexcept : value_{opt.value_or(NO_VALUE)} {}
    // cppcheck-suppress-end noExplicitConstructor

    [[nodiscard]] constexpr auto has_value() const noexcept -> bool {
        return nullable<T>::is_valid(value_);
    }

    [[nodiscard]] constexpr explicit operator bool() const noexcept { return has_value(); }

    template <typename... Args> constexpr auto emplace(Args&&... args) noexcept -> void {
        value_ = T{std::forward<Args>(args)...};
    }

    constexpr auto reset() noexcept -> void { value_ = NO_VALUE; }

    // Resets the optional and returns the stored value
    [[nodiscard]] constexpr auto take() noexcept -> T {
        auto tmp{value_};
        reset();
        return tmp;
    }

    [[nodiscard]] constexpr auto value(this auto&& self) -> auto& {
        ASSERT(self.has_value(), "Attempt to access empty compact optional");
        return self.value_;
    }

    [[nodiscard]] constexpr auto get(this auto&& self) noexcept -> auto* { return &self.value(); }
    [[nodiscard]] constexpr auto operator->(this auto&& self) noexcept -> auto* {
        return self.get();
    }
    [[nodiscard]] constexpr auto operator*(this auto&& self) noexcept -> auto& {
        return *self.get();
    }
    [[nodiscard]] friend auto operator==(const compact_opt& lhs, const compact_opt& rhs) noexcept
        -> bool = default;

    template <typename F>
    [[nodiscard]] constexpr auto transform(this auto&& self, F&& f) -> decltype(auto) {
        using res = std::remove_cv_t<std::invoke_result_t<F, T>>;

        // This is straight from clang's stdc++ C++23 optional implementation
        static_assert(!std::is_array_v<res>, "Result of f(value()) should not be an Array");
        static_assert(!std::is_same_v<res, std::in_place_t>,
                      "Result of f(value()) should not be std::in_place_t");
        static_assert(!std::is_same_v<res, none_t>,
                      "Result of f(value()) should not be stdx::none");
        static_assert(std::is_object_v<res>, "Result of f(value()) should be an object type");

        // Also from clang, but generalized to support reference transform chains
        using ret = dispatch_opt<res>;
        return self.has_value() ? ret{std::forward<F>(f)(self.value())} : ret{};
    }

    template <CopyConstructible Or>
        requires requires(const T& t) { static_cast<Or>(t); }
    [[nodiscard]] constexpr auto value_or(this auto&& self, Or&& or_value) -> decltype(auto) {
        return self.has_value() ? *self.get() : static_cast<T>(std::forward<Or>(or_value));
    }

    [[nodiscard]] constexpr operator std::optional<T>() const noexcept {
        return has_value() ? std::optional<T>{value_} : none;
    }

  private:
    static constexpr auto NO_VALUE{nullable<T>::invalid()};

  private:
    T value_;
};

template <typename T> struct option_impl {
    using type = std::optional<T>;
};

template <Reference T> struct option_impl<T> {
    using type = ref<std::remove_reference_t<T>>;
};

template <Compactable T> struct option_impl<T> {
    using type = compact_opt<T>;
};

} // namespace detail

// A safe, reference-allowable optional type dispatcher
template <typename T> using option = typename detail::option_impl<T>::type;

// Compares two values, forwarding safety concerns to the comparator.
template <typename T, typename Comparator>
constexpr auto safe_eq(const option<T>& a, const option<T>& b, Comparator cmp) noexcept -> bool {
    if (a.has_value() != b.has_value()) { return false; }
    if (!a.has_value()) { return true; }
    return cmp(*a, *b);
}

// Compares two values, delegating equality to the default equality operator.
template <typename T>
constexpr auto safe_eq(const option<T>& a, const option<T>& b) noexcept -> bool {
    if (a.has_value() != b.has_value()) { return false; }
    if (!a.has_value()) { return true; }
    return *a == *b;
}

// An efficient optional representation of boolean values
class tribool {
  public:
    // cppcheck-suppress-begin noExplicitConstructor
    constexpr tribool() noexcept : value_{NO_VALUE} {}
    constexpr tribool(bool value) noexcept : value_{static_cast<u8>(value)} {}
    constexpr tribool(none_t) noexcept : value_{NO_VALUE} {}
    constexpr tribool(const std::optional<bool>& ob) noexcept
        : value_{ob.transform([](bool b) -> u8 { return b; }).value_or(NO_VALUE)} {}
    // cppcheck-suppress-end noExplicitConstructor

    [[nodiscard]] constexpr auto has_value() const noexcept -> bool { return value_ != NO_VALUE; }
    [[nodiscard]] constexpr explicit operator bool() const noexcept { return has_value(); }

    constexpr auto emplace(bool value) noexcept -> void { value_ = value; }
    constexpr auto reset() noexcept -> void { value_ = NO_VALUE; }

    // Resets the optional and returns the stored bool
    [[nodiscard]] constexpr auto take() noexcept -> bool {
        const auto value{value_};
        reset();
        return value;
    }

    [[nodiscard]] constexpr auto value() const noexcept -> bool { return get(); }

    [[nodiscard]] constexpr auto get() const noexcept -> bool {
        ASSERT(has_value(), "Attempt to access empty optional boolean");
        return static_cast<bool>(value_);
    }

    [[nodiscard]] constexpr auto operator*() const noexcept -> bool { return get(); }

    template <std::convertible_to<bool> Or>
        requires CopyConstructible<Or>
    [[nodiscard]] constexpr auto value_or(Or&& or_value) -> bool {
        return has_value() ? get() : static_cast<bool>(std::forward<Or>(or_value));
    }

    [[nodiscard]] constexpr operator std::optional<bool>() const noexcept {
        return has_value() ? std::optional<bool>{value_} : none;
    }

  private:
    static constexpr u8 NO_VALUE{3};

  private:
    u8 value_;
};

// A minimal, zero-cost optional usize wrapper
class opt_size {
  public:
    constexpr opt_size() noexcept = default;

    // cppcheck-suppress-begin noExplicitConstructor
    constexpr opt_size(usize idx) noexcept : value_{idx} {}
    constexpr opt_size(std::nullopt_t) noexcept {}

    // Any negative value is treated as a sentinel
    template <NumericIntegral Int> constexpr opt_size(Int i) noexcept {
        if (i >= 0) { value_ = static_cast<usize>(i); }
    }

    constexpr opt_size(const std::optional<usize>& oi) noexcept : value_{oi.value_or(NO_VALUE)} {}
    // cppcheck-suppress-end noExplicitConstructor

    [[nodiscard]] constexpr auto has_value() const noexcept -> bool { return value_ != NO_VALUE; }
    [[nodiscard]] constexpr explicit operator bool() const noexcept { return has_value(); }

    constexpr auto emplace(usize idx) noexcept -> void { value_ = idx; }

    constexpr auto               reset() noexcept -> void { value_ = NO_VALUE; }
    [[nodiscard]] constexpr auto take() noexcept -> usize {
        const usize idx{value_};
        reset();
        return idx;
    }

    [[nodiscard]] constexpr auto value() const -> usize { return get(); }
    [[nodiscard]] constexpr auto get() const noexcept -> usize {
        ASSERT(has_value(), "Attempt to access empty optional enum");
        return value_;
    }

    [[nodiscard]] constexpr auto operator*() const noexcept -> usize { return get(); }

    [[nodiscard]] constexpr operator std::optional<usize>() const noexcept {
        return has_value() ? std::optional<usize>{value_} : none;
    }

    [[nodiscard]] constexpr auto operator==(const opt_size&) const noexcept -> bool = default;

    [[nodiscard]] auto hash() const noexcept -> u64 { return std::hash<usize>{}(value_); }

  private:
    static constexpr usize NO_VALUE{std::numeric_limits<usize>::max()};

  private:
    usize value_{NO_VALUE};
};

template <typename T> struct is_option : std::false_type {};
template <typename T> struct is_option<std::optional<T>> : std::true_type {};
template <typename T> struct is_option<detail::ref<T>> : std::true_type {};
template <typename T> struct is_option<detail::compact_opt<T>> : std::true_type {};

template <typename T>
concept Option = is_option<T>::value;

template <typename T> struct is_opt_size : std::false_type {};
template <> struct is_opt_size<opt_size> : std::true_type {};

template <typename T>
concept OptSize = is_opt_size<T>::value;

} // namespace stdx

template <> struct ankerl::unordered_dense::hash<stdx::opt_size> {
    using is_avalanching = void;
    [[nodiscard]] auto operator()(const stdx::opt_size& o) const noexcept { return o.hash(); }
};
