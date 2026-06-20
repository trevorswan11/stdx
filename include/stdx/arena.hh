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
        : block_offset_{other.block_offset_}, block_head_{other.block_head_},
          block_current_{other.block_current_}, cleanup_current_{other.cleanup_current_},
          cleanup_head_{other.cleanup_head_} {
        other.block_offset_    = 0;
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
        auto* data{new (mem) T{std::forward<Args>(args)...}};
        if constexpr (!TriviallyDestructible<T>) {
            register_destructor(data, [](void* ptr) -> void { static_cast<T*>(ptr)->~T(); });
        }
        return data;
    }

    // Asserts that the requested type-count product can fit in the block size
    template <typename T>
        requires(sizeof(T) + alignof(T) <= BlockSize)
    [[nodiscard]] auto make_span(usize count) -> gsl::span<T> {
        if (count == 0) { return {}; }

        const auto size{sizeof(T) * count};
        ASSERT(size + alignof(T) - 1 <= BlockSize, "Block size cannot fit requested type count");
        void* mem{alloc(size, alignof(T))};
        auto* data{static_cast<T*>(mem)};
        for (usize i{0}; i < count; ++i) { new (static_cast<void*>(data + i)) T{}; }

        if constexpr (!TriviallyDestructible<T>) {
            using cleanup_span = cleanup_node::template span<T>;
            void* ctx_mem{alloc(sizeof(cleanup_span), alignof(cleanup_span))};
            auto* ctx{new (ctx_mem) cleanup_span{data, count}};

            register_destructor(ctx, [](void* ptr) -> void {
                auto* context{static_cast<cleanup_span*>(ptr)};
                for (usize i{0}; i < context->size; ++i) { (context->data + i)->~T(); }
            });
        }
        return gsl::span{data, count};
    }
    // cppcheck-suppress-end [unreadVariable, internalAstError]

    auto reset() noexcept -> void {
        run_destructors();
        block_current_ = block_head_;
        block_offset_  = 0;
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
    using destructor_t = void (*)(void*);

    struct cleanup_node {
        template <typename T> struct span {
            T*    data;
            usize size;
        };

        destructor_t  destructor;
        void*         data;
        cleanup_node* next;
    };

    struct block {
        block* next{nullptr};

        // Allocates a new block housed inside of its own memory region based on `BLOCK_SIZE`
        [[nodiscard]] static auto alloc(arena& a, usize size, usize align) -> void* {
            PROFILE_FUNCTION();
            void* raw{::operator new(sizeof(block) + BlockSize)};
            auto* blk{new (raw) block{}};

            if (a.block_current_) {
                a.block_current_->next = blk;
            } else {
                a.block_head_ = blk;
            }
            a.block_current_ = blk;

            a.block_offset_ = 0;
            return a.alloc(size, align);
        }
    };

  private:
    auto register_destructor(void* data, destructor_t destructor) -> void {
        void* node_mem{alloc(sizeof(cleanup_node), alignof(cleanup_node))};
        auto* node{new (node_mem) cleanup_node{
            .destructor = destructor,
            .data       = data,
            .next       = nullptr,
        }};

        if (cleanup_current_) {
            cleanup_current_->next = node;
        } else {
            cleanup_head_ = node;
        }
        cleanup_current_ = node;
    }

    auto run_destructors() noexcept -> void {
        cleanup_node* current_cleanup{cleanup_head_};
        while (current_cleanup) {
            current_cleanup->destructor(current_cleanup->data);
            current_cleanup = current_cleanup->next;
        }
        cleanup_head_    = nullptr;
        cleanup_current_ = nullptr;
    }

    [[nodiscard]] auto alloc(usize size, usize align) -> void* {
        PROFILE_FUNCTION();
        if (block_current_) {
            auto        raw_addr{reinterpret_cast<uptr>(block_current_ + 1)};
            uptr        current_ptr{raw_addr + block_offset_};
            uptr        aligned_ptr{(current_ptr + (align - 1)) & ~(align - 1)};
            const usize total_size{aligned_ptr - raw_addr + size};

            if (total_size <= BlockSize) {
                block_offset_ = total_size;
                return reinterpret_cast<void*>(aligned_ptr);
            }

            if (block_current_->next) {
                block_current_ = block_current_->next;
                block_offset_  = 0;
                return alloc(size, align);
            }
        }

        // Otherwise a new block needs to be created for the memory
        return block::alloc(*this, size, align);
    }

  private:
    usize         block_offset_{0};
    block*        block_head_{nullptr};
    block*        block_current_{nullptr};
    cleanup_node* cleanup_head_{nullptr};
    cleanup_node* cleanup_current_{nullptr};
};

} // namespace stdx
