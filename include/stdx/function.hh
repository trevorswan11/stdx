#pragma once

#include <cstddef>
#include <functional>
#include <type_traits>
#include <utility>

#include "stdx/option.hh"
#include "stdx/types.hh"

namespace stdx {

namespace detail {

template <typename Ret, typename... Args> struct vtable {
    Ret (*invoke)(const void* storage, Args... args);
    void (*copy)(const void* src, void* dst);
    void (*move)(void* src, void* dst);
    void (*destroy)(void* storage);
};

template <typename F, typename Ret, typename... Args> struct vtable_for {
    static constexpr vtable<Ret, Args...> table = {
        .invoke = [](const void* storage, Args... args) -> Ret {
            auto* fn{static_cast<F*>(const_cast<void*>(storage))};
            if constexpr (std::is_void_v<Ret>) {
                std::invoke(*fn, std::forward<Args>(args)...);
            } else {
                return std::invoke(*fn, std::forward<Args>(args)...);
            }
        },
        .copy = [](const void* src, void* dst) -> void {
            if constexpr (std::is_copy_constructible_v<F>) {
                ::new (dst) F{*static_cast<const F*>(src)};
            }
        },
        .move = [](void* src, void* dst) -> void {
            ::new (dst) F{std::move(*static_cast<F*>(src))};
            static_cast<F*>(src)->~F();
        },
        .destroy = [](void* storage) -> void { static_cast<F*>(storage)->~F(); },
    };
};

} // namespace detail

// A marginally more efficient `std::function`
template <typename Signature, usize StorageSize = 32> class function;
template <typename Ret, typename... Args, usize StorageSize>
class function<Ret(Args...), StorageSize> {
  public:
    function() noexcept = default;
    function(std::nullptr_t) noexcept {}

    template <typename F>
        requires(!std::is_same_v<std::decay_t<F>, function> &&
                 !std::is_same_v<std::decay_t<F>, std::nullptr_t> &&
                 std::is_invocable_r_v<Ret, std::decay_t<F>&, Args...>)
    function(F&& callable) {
        using decayed_f = std::decay_t<F>;
        static_assert(sizeof(decayed_f) <= StorageSize,
                      "Callable object size exceeds function inline storage capacity");
        static_assert(alignof(decayed_f) <= alignof(std::max_align_t),
                      "Callable object alignment exceeds function inline storage alignment");

        ::new (static_cast<void*>(storage_)) decayed_f{std::forward<F>(callable)};
        vtable_ = &detail::vtable_for<decayed_f, Ret, Args...>::table;
    }

    ~function() { reset(); }

    function(const function& other) {
        if (other.vtable_) {
            other.vtable_->copy(static_cast<const void*>(other.storage_),
                                static_cast<void*>(storage_));
            vtable_ = other.vtable_;
        }
    }

    auto operator=(const function& other) -> function& {
        if (this != &other) {
            reset();
            if (other.vtable_) {
                other.vtable_->copy(static_cast<const void*>(other.storage_),
                                    static_cast<void*>(storage_));
                vtable_ = other.vtable_;
            }
        }
        return *this;
    }

    function(function&& other) noexcept {
        if (other.vtable_) {
            other.vtable_->move(static_cast<void*>(other.storage_), static_cast<void*>(storage_));
            vtable_ = other.vtable_;
            other.vtable_.reset();
        }
    }

    auto operator=(function&& other) noexcept -> function& {
        if (this != &other) {
            reset();
            if (other.vtable_) {
                other.vtable_->move(static_cast<void*>(other.storage_),
                                    static_cast<void*>(storage_));
                vtable_ = other.vtable_;
                other.vtable_.reset();
            }
        }
        return *this;
    }

    template <typename F>
        requires(!std::is_same_v<std::decay_t<F>, function> &&
                 !std::is_same_v<std::decay_t<F>, std::nullptr_t> &&
                 std::is_invocable_r_v<Ret, std::decay_t<F>&, Args...>)
    auto operator=(F&& callable) -> function& {
        reset();
        using decayed_f = std::decay_t<F>;
        static_assert(sizeof(decayed_f) <= StorageSize,
                      "Callable object size exceeds function inline storage capacity");
        static_assert(alignof(decayed_f) <= alignof(std::max_align_t),
                      "Callable object alignment exceeds function inline storage alignment");

        ::new (static_cast<void*>(storage_)) decayed_f{std::forward<F>(callable)};
        vtable_ = &detail::vtable_for<decayed_f, Ret, Args...>::table;
        return *this;
    }

    [[nodiscard]] auto     is_valid() const noexcept -> bool { return vtable_.has_value(); }
    [[nodiscard]] explicit operator bool() const noexcept { return is_valid(); }

    auto operator=(std::nullptr_t) noexcept -> function& {
        reset();
        return *this;
    }

    auto operator()(Args... args) const -> Ret {
        if (!vtable_) {
            if constexpr (std::is_void_v<Ret>) {
                return;
            } else {
                return Ret{};
            }
        }
        return vtable_->invoke(static_cast<const void*>(storage_), std::forward<Args>(args)...);
    }

    auto reset() noexcept -> void {
        if (vtable_) {
            vtable_->destroy(static_cast<void*>(storage_));
            vtable_.reset();
        }
    }

  private:
    stdx::option<const detail::vtable<Ret, Args...>&> vtable_;
    alignas(std::max_align_t) std::byte storage_[StorageSize]{};
};

} // namespace stdx
