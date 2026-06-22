#include <new>

#include <stdx/types.hh>

extern "C" {
auto alloc(usize size) -> void*;
auto dealloc(void* ptr) -> void;
}

auto operator new(usize size) -> void* {
    void* p{alloc(size)};
    return p ? p : throw std::bad_alloc();
}

auto operator delete(void* p) noexcept -> void { dealloc(p); }
auto operator delete(void* p, usize) noexcept -> void { dealloc(p); }

auto operator new[](usize size) -> void* { return operator new(size); }
auto operator delete[](void* p) noexcept -> void { operator delete(p); }
