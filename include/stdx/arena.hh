#pragma once

#include <cstddef>
#include <utility>

#include <gsl/pointers>
#include <gsl/span>

#include "stdx/assert.hh"
#include "stdx/memory.hh"
#include "stdx/profiler.hh"
#include "stdx/type_traits.hh"
#include "stdx/types.hh"

namespace stdx {

constexpr auto DEFAULT_ARENA_BLOCK_SIZE{[] -> usize {
    using namespace size_literals;
    return static_cast<usize>(64_KiB);
}()};

// Do not free returned memory directly!
template <usize BlockSize = DEFAULT_ARENA_BLOCK_SIZE> class arena {
  public:
    arena() noexcept = default;
    ~arena() { clear(); }

    arena(const arena&)                    = delete;
    auto operator=(const arena&) -> arena& = delete;
    arena(arena&& other) noexcept
        : offset_{other.offset_}, block_head_{other.block_head_},
          block_current_{other.block_current_}, cleanup_current_{other.cleanup_current_},
          cleanup_head_{other.cleanup_head_} {
        other.offset_          = 0;
        other.block_head_      = nullptr;
        other.block_current_   = nullptr;
        other.cleanup_head_    = nullptr;
        other.cleanup_current_ = nullptr;
    }
    auto operator=(arena&&) -> arena& = delete;

    // cppcheck-suppress-begin [unreadVariable, internalAstError]

    // Asserts that the requested type is at most the block size
    template <typename T, typename... Args>
        requires(sizeof(T) + alignof(T) <= BlockSize)
    [[nodiscard]] auto make(Args&&... args) -> gsl::not_null<T*> {
        void* mem{alloc(sizeof(T), alignof(T))};
        auto* obj{new (mem) T{std::forward<Args>(args)...}};
        if constexpr (!TriviallyDestructible<T>) {
            register_destructors(obj, [](void* ptr) -> void { static_cast<T*>(ptr)->~T(); });
        }
        return obj;
    }

    // Asserts that the requested type-count product can fit in the block size
    template <typename T>
        requires(sizeof(T) + alignof(T) <= BlockSize)
    [[nodiscard]] auto make_span(usize count) -> gsl::span<T> {
        if (count == 0) { return {}; }

        const auto size{sizeof(T) * count};
        ASSERT(size + alignof(T) - 1 <= BlockSize, "Block size cannot fit requested type count");
        void* mem{alloc(size, alignof(T))};
        auto* ptr{static_cast<T*>(mem)};
        for (usize i{0}; i < count; ++i) { new (static_cast<void*>(ptr + i)) T{}; }

        if constexpr (!TriviallyDestructible<T>) {
            void* ctx_mem{alloc(sizeof(span_context<T>), alignof(span_context<T>))};
            auto* ctx{new (ctx_mem) span_context<T>{ptr, count}};

            register_destructors(ctx, [](void* ptr) -> void {
                auto* context{static_cast<span_context<T>*>(ptr)};
                for (usize i{0}; i < context->size; ++i) { (context->data + i)->~T(); }
            });
        }
        return gsl::span{ptr, count};
    }
    // cppcheck-suppress-end [unreadVariable, internalAstError]

    auto reset() noexcept -> void {
        run_destructors();
        block_current_ = block_head_;
        offset_        = 0;
    }

    // Deallocates all memory associated with the arena.
    auto clear() noexcept -> void {
        PROFILE_FUNCTION();
        run_destructors();

        block* blk{block_head_};
        while (blk) {
            block* next{blk->next};
            ::operator delete(blk);
            blk = next;
        }
        block_head_ = nullptr;
        reset();
    }

  private:
    auto register_destructors(void* ptr, void (*destroy_fn)(void*)) -> void {
        void* node_mem{alloc(sizeof(cleanup_node), alignof(cleanup_node))};
        auto* node{new (node_mem) cleanup_node{
            .destroy     = destroy_fn,
            .storage_ptr = ptr,
            .next        = nullptr,
        }};

        if (cleanup_current_) {
            cleanup_current_->next = node;
            cleanup_current_       = node;
        } else {
            cleanup_head_    = node;
            cleanup_current_ = cleanup_head_;
        }
    }

    auto run_destructors() noexcept -> void {
        cleanup_node* current_cleanup{cleanup_head_};
        while (current_cleanup) {
            current_cleanup->destroy(current_cleanup->storage_ptr);
            current_cleanup = current_cleanup->next;
        }
        cleanup_head_    = nullptr;
        cleanup_current_ = nullptr;
    }

    [[nodiscard]] auto alloc(usize size, usize align) -> void* {
        PROFILE_FUNCTION();
        if (block_current_) {
            auto        raw_addr{reinterpret_cast<uptr>(block_current_ + 1)};
            uptr        current_ptr{raw_addr + offset_};
            uptr        aligned_ptr{(current_ptr + (align - 1)) & ~(align - 1)};
            const usize total_size{aligned_ptr - raw_addr + size};

            if (total_size <= BlockSize) {
                offset_ = total_size;
                return reinterpret_cast<void*>(aligned_ptr);
            }

            if (block_current_->next) {
                block_current_ = block_current_->next;
                offset_        = 0;
                return alloc(size, align);
            }
        }

        // Otherwise a new block needs to be created for the memory
        return block::alloc(*this, size, align);
    }

  private:
    struct cleanup_node {
        void (*destroy)(void*);
        void*         storage_ptr;
        cleanup_node* next;
    };

    template <typename T> struct span_context {
        T*    data;
        usize size;
    };

    struct block {
        block* next{nullptr};

        // Allocates a new block housed inside of its own memory region based on `BLOCK_SIZE`
        [[nodiscard]] static auto alloc(arena& a, usize size, usize align) -> void* {
            PROFILE_FUNCTION();
            void* raw{::operator new(sizeof(block) + BlockSize)};
            auto* blk{new (raw) block{}};

            if (!a.block_head_) {
                a.block_head_ = blk;
            } else {
                ASSERT(a.block_current_);
                a.block_current_->next = blk;
            }

            a.block_current_ = blk;
            a.offset_        = 0;
            return a.alloc(size, align);
        }
    };

  private:
    usize         offset_{0};
    block*        block_head_{nullptr};
    block*        block_current_{nullptr};
    cleanup_node* cleanup_head_{nullptr};
    cleanup_node* cleanup_current_{nullptr};
};

} // namespace stdx
