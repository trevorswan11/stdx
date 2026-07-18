#pragma once

#include <concepts>
#include <expected>
#include <type_traits>

#include "stdx/option.hh"
#include "stdx/type_traits.hh"

namespace stdx {

template <typename E> using err = std::unexpected<E>;

namespace detail {

// A result type that has no associated value
template <typename E> class empty_result {
  public:
    // cppcheck-suppress-begin noExplicitConstructor
    constexpr empty_result() noexcept = default;

    // Constructs the error type in place
    template <typename... Args> constexpr empty_result(Args&&... args) {
        error_.emplace(std::forward<Args>(args)...);
    }

    constexpr empty_result(err<E>&& err) : error_{std::move(err.error())} {}
    // cppcheck-suppress-end noExplicitConstructor

    // Checks for the lack of presence of the underlying error, mirrors std::expected
    [[nodiscard]] constexpr auto has_value() const noexcept -> bool { return !has_error(); }
    constexpr auto               value() const -> void {}
    constexpr auto               operator*() const -> void {}
    [[nodiscard]] constexpr auto has_error() const noexcept -> bool { return error_.has_value(); }
    [[nodiscard]] constexpr auto error(this auto&& self) -> auto& { return *self.error_; }
    [[nodiscard]] constexpr explicit operator bool() const noexcept { return has_value(); }

    template <std::convertible_to<E> Or = E>
        requires CopyConstructible<Or>
    constexpr auto error_or(Or&& or_value) const& {
        if (has_value()) { return std::forward<Or>(or_value); }
        return error();
    }

    [[nodiscard]] constexpr auto operator==(const empty_result&) const noexcept -> bool = default;

  private:
    option<E> error_;
};

// Uses explicit inline namespace due to name collisions in std
template <typename T, typename E> using valued_result = std::expected<T, E>;

template <typename T, typename E> struct result_impl {
    using type = valued_result<T, E>;
};

template <std::same_as<void> T, typename E> struct result_impl<T, E> {
    using type = empty_result<E>;
};

} // namespace detail

template <typename T, typename E> using result = detail::result_impl<T, E>::type;

template <typename E, typename... Args>
[[nodiscard]] constexpr auto make_err(Args&&... args) -> err<E> {
    return err<E>{E{std::forward<Args>(args)...}};
}

// A hack to imitate the 'try' keyword in zig using GNU Statement Expressions
// https://gcc.gnu.org/onlinedocs/gcc/Statement-Exprs.html
#define TRY(expr)                                                           \
    __extension__({                                                         \
        auto&& _e = (expr);                                                 \
        if (!_e.has_value()) { return ::stdx::err{std::move(_e).error()}; } \
        std::move(_e).value();                                              \
    })

template <typename T> struct is_result : std::false_type {};
template <typename T, typename E> struct is_result<detail::valued_result<T, E>> : std::true_type {};
template <typename E> struct is_result<detail::empty_result<E>> : std::true_type {};

template <typename T>
concept Result = is_result<T>::value;

} // namespace stdx
