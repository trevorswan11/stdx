#include "stdx/arena.hh"

#include "stdx/assert.hh"
#include "stdx/profiler.hh"
#include "stdx/types.hh"

namespace stdx {

// https://github.com/trevorswan11/stdx/blob/772707146faa9315c24fb079fd759f3715442db1/old/src/util/arena.c
auto arena::alloc(usize size, usize align) -> void* {
    PROFILE_FUNCTION();
    if (current_) {
        auto        raw_addr{reinterpret_cast<uptr>(current_ + 1)};
        uptr        current_ptr{raw_addr + offset_};
        uptr        aligned_ptr{(current_ptr + (align - 1)) & ~(align - 1)};
        const usize total_size{aligned_ptr - raw_addr + size};

        if (total_size <= BLOCK_SIZE) {
            offset_ = total_size;
            return reinterpret_cast<void*>(aligned_ptr);
        }

        if (current_->next) {
            current_ = current_->next;
            offset_  = 0;
            return alloc(size, align);
        }
    }

    // Otherwise a new block needs to be created for the memory
    return block::alloc(*this, size, align);
}

auto arena::clear() noexcept -> void {
    PROFILE_FUNCTION();
    block* blk = head_;
    while (blk) {
        block* next{blk->next};
        ::operator delete(blk);
        blk = next;
    }
    reset();
}

auto arena::block::alloc(arena& a, usize size, usize align) -> void* {
    PROFILE_FUNCTION();
    void* raw   = ::operator new(sizeof(block) + BLOCK_SIZE);
    auto* blk = new (raw) block{};

    if (!a.head_) {
        a.head_ = blk;
    } else {
        ASSERT(a.current_);
        a.current_->next = blk;
    }

    a.current_ = blk;
    a.offset_  = 0;
    return a.alloc(size, align);
}

} // namespace stdx
