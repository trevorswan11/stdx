pub const root = "synchronization";

pub const graphcycles_sources = [_][]const u8{
    "synchronization/internal/graphcycles.cc",
};

pub const kernel_timeout_sources = [_][]const u8{
    "synchronization/internal/kernel_timeout.cc",
};

pub const synchronization_sources = [_][]const u8{
    "synchronization/barrier.cc",
    "synchronization/blocking_counter.cc",
    "synchronization/internal/create_thread_identity.cc",
    "synchronization/internal/futex_waiter.cc",
    "synchronization/internal/per_thread_sem.cc",
    "synchronization/internal/pthread_waiter.cc",
    "synchronization/internal/sem_waiter.cc",
    "synchronization/internal/stdcpp_waiter.cc",
    "synchronization/internal/waiter_base.cc",
    "synchronization/internal/win32_waiter.cc",
    "synchronization/mutex.cc",
    "synchronization/notification.cc",
};
