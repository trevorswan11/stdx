pub const root = "base";

pub const raw_logging_sources = [_][]const u8{
    "base/internal/raw_logging.cc",
};

pub const spinlock_wait_sources = [_][]const u8{
    "base/internal/spinlock_wait.cc",
};

pub const throw_delegate_sources = [_][]const u8{
    "base/throw_delegate.cc",
};

pub const strerror_sources = [_][]const u8{
    "base/internal/strerror.cc",
};

pub const base_sources = [_][]const u8{
    "base/casts.cc",
    "base/internal/cpu_detect.cc",
    "base/internal/cycleclock.cc",
    "base/internal/hardening.cc",
    "base/internal/spinlock.cc",
    "base/internal/sysinfo.cc",
    "base/internal/thread_identity.cc",
    "base/internal/unscaledcycleclock.cc",
    "base/log_severity.cc",
};

pub const malloc_internal_sources = [_][]const u8{
    "base/internal/low_level_alloc.cc",
    "base/internal/poison.cc",
};

pub const tracing_internal_sources = [_][]const u8{
    "base/internal/tracing.cc",
};
