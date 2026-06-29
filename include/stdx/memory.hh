#pragma once

#include <concepts>
#include <cstddef>
#include <memory>
#include <new>
#include <type_traits>
#include <utility>

#include "stdx/assert.hh"
#include "stdx/types.hh"
#include "stdx/utility.hh"

namespace stdx {

// https://wunkolo.github.io/post/2022/02/memory-size-literals/
namespace size_literals {

constexpr auto operator""_KiB(unsigned long long int x) noexcept -> u64 { return 1'024ULL * x; }
constexpr auto operator""_MiB(unsigned long long int x) noexcept -> u64 { return 1'024_KiB * x; }
constexpr auto operator""_GiB(unsigned long long int x) noexcept -> u64 { return 1'024_MiB * x; }
constexpr auto operator""_TiB(unsigned long long int x) noexcept -> u64 { return 1'024_GiB * x; }
constexpr auto operator""_PiB(unsigned long long int x) noexcept -> u64 { return 1'024_TiB * x; }

} // namespace size_literals

namespace sizes {

#define NAMEOF(name) name

#define MAKE_SIZE_FN(name, literal)                                \
    template <std::unsigned_integral U>                            \
    [[nodiscard]] constexpr auto NAMEOF(name)(U x) noexcept -> U { \
        using namespace size_literals;                             \
        return static_cast<U>(x * CONCAT(1, literal));             \
    }

MAKE_SIZE_FN(kib, _KiB)
MAKE_SIZE_FN(mib, _MiB)
MAKE_SIZE_FN(gib, _GiB)
MAKE_SIZE_FN(tib, _TiB)
MAKE_SIZE_FN(pib, _PiB)

#undef MAKE_SIZE_FN
#undef NAMEOF

} // namespace sizes

// Returns a pointer to the object of type T constructed within the given byte storage
template <typename T> [[nodiscard]] auto object_at(std::byte* bytes) noexcept -> T* {
    return std::launder(reinterpret_cast<T*>(bytes));
}

// Returns a constant pointer to the object of type T constructed within the given byte storage
template <typename T> [[nodiscard]] auto object_at(const std::byte* bytes) noexcept -> const T* {
    return std::launder(reinterpret_cast<const T*>(bytes));
}

// cppcheck-suppress-begin noExplicitConstructor

// An alias for a unique pointer which should be seldom used
template <typename T, typename D = std::default_delete<T>>
using nullable_box = std::unique_ptr<T, D>;
template <typename T, typename... Args>
[[nodiscard]] constexpr auto make_nullable_box(Args&&... args) -> nullable_box<T> {
    return std::make_unique<T>(std::forward<Args>(args)...);
}

// A light unique pointer wrapper that ensures pointer validity at initialization.
//
// All methods besides constructors and factories ASSERT this invariant.
template <typename T, typename D = std::default_delete<T>> class box {
  public:
    constexpr box() noexcept = default;
    explicit box(nullable_box<T, D>&& ptr) : ptr_{std::move(ptr)} {
        ASSERT(ptr_, "Box cannot be created from nullptr");
    }

    template <typename P> explicit box(P* ptr) : ptr_{nullable_box<T>{static_cast<T*>(ptr)}} {
        ASSERT(ptr_, "Box cannot be created from nullptr");
    }

    template <typename U, typename E>
        requires(std::is_convertible_v<U*, T*>)
    box(box<U, E>&& other) : ptr_{std::move(other.ptr_)} {}

    ~box()                             = default;
    box(const box&)                    = delete;
    auto operator=(const box&) -> box& = delete;
    box(box&&)                         = default;
    auto operator=(box&&) -> box&      = default;

    [[nodiscard]] auto operator*() const noexcept -> T& { return *get(); }
    [[nodiscard]] auto operator->() const noexcept -> T* { return get(); }

    [[nodiscard]] auto release() noexcept -> T* {
        ASSERT(ptr_, "Attempted to release a moved-from Box");
        return ptr_.release();
    }

    [[nodiscard]] auto get() const noexcept -> T* {
        ASSERT(ptr_, "Attempted to access a moved-from Box");
        return ptr_.get();
    }

    template <typename... Args> [[nodiscard]] static auto make(Args&&... args) -> box<T> {
        return box{make_nullable_box<T>(std::forward<Args>(args)...)};
    }

    operator bool() const noexcept { return ptr_.operator bool(); }

  private:
    nullable_box<T, D> ptr_;

    template <typename U, typename E> friend class box;
};

template <typename T, typename D> class box<T[], D> {
  public:
    constexpr box() noexcept = default;
    explicit box(nullable_box<T[], D>&& ptr) : ptr_{std::move(ptr)} {
        ASSERT(ptr_, "Box cannot be created from nullptr");
    }

    template <typename P> explicit box(P* ptr) : ptr_{nullable_box<T[], D>{static_cast<T*>(ptr)}} {
        ASSERT(ptr_, "Box cannot be created from nullptr");
    }

    template <typename U, typename E>
        requires(std::is_convertible_v<U (*)[], T (*)[]>)
    box(box<U[], E>&& other) : ptr_{std::move(other.ptr_)} {}

    ~box()                             = default;
    box(const box&)                    = delete;
    auto operator=(const box&) -> box& = delete;
    box(box&&)                         = default;
    auto operator=(box&&) -> box&      = default;

    [[nodiscard]] auto operator[](std::size_t i) const -> T& {
        ASSERT(ptr_, "Attempted to access a moved-from Box");
        return get()[i];
    }

    [[nodiscard]] auto release() noexcept -> T* {
        ASSERT(ptr_, "Attempted to release a moved-from Box");
        return ptr_.release();
    }

    [[nodiscard]] auto get() const noexcept -> T* {
        ASSERT(ptr_, "Attempted to access a moved-from Box");
        return ptr_.get();
    }

    [[nodiscard]] static auto make(std::size_t size) -> box<T[]> {
        return box{make_nullable_box<T[]>(size)};
    }

    operator bool() const noexcept { return ptr_.operator bool(); }

  private:
    nullable_box<T[], D> ptr_;

    template <typename U, typename E> friend class box;
};

template <typename T, typename... Args>
[[nodiscard]] constexpr auto make_box(Args&&... args) -> box<T> {
    return box<T>::make(std::forward<Args>(args)...);
}

template <typename T> using rc = std::shared_ptr<T>;
template <typename T, typename... Args>
[[nodiscard]] constexpr auto make_rc(Args&&... args) -> rc<T> {
    return std::make_shared<T>(std::forward<Args>(args)...);
}

// cppcheck-suppress-end noExplicitConstructor

} // namespace stdx
