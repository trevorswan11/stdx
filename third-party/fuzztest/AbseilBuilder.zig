const std = @import("std");

const Dependency = @import("../Dependency.zig");
const Config = Dependency.Config;
const Artifact = Dependency.Artifact;

const base_mod = @import("sources/abseil/base.zig");
const strings_mod = @import("sources/abseil/strings.zig");
const synchronization_mod = @import("sources/abseil/synchronization.zig");
const time_mod = @import("sources/abseil/time.zig");
const log_mod = @import("sources/abseil/log.zig");
const random_mod = @import("sources/abseil/random.zig");

const Self = @This();

const Metadata = struct {
    upstream: *std.Build.Dependency,
    config: Config,
    /// The absl/ subdirectory
    root: std.Build.LazyPath,
    /// The abseil-cpp repo root
    upstream_root: std.Build.LazyPath,
};

const Base = struct {
    raw_logging_internal: Artifact = undefined,
    spinlock_wait: Artifact = undefined,
    throw_delegate: Artifact = undefined,
    strerror: Artifact = undefined,
    base: Artifact = undefined,
    malloc_internal: Artifact = undefined,
    tracing_internal: Artifact = undefined,
};

const Numeric = struct {
    int128: Artifact = undefined,
};

const Types = struct {
    source_location: Artifact = undefined,
};

const Strings = struct {
    internal: Artifact = undefined,
    strings: Artifact = undefined,
    str_format_internal: Artifact = undefined,
    cord_internal: Artifact = undefined,
    cordz_handle: Artifact = undefined,
    cordz_functions: Artifact = undefined,
    cordz_info: Artifact = undefined,
    cord: Artifact = undefined,
};

const Time = struct {
    cctz: Artifact = undefined,
    time: Artifact = undefined,
    clock_interface: Artifact = undefined,
    simulated_clock: Artifact = undefined,
};

const Debugging = struct {
    debugging_internal: Artifact = undefined,
    demangle_internal: Artifact = undefined,
    stacktrace: Artifact = undefined,
    symbolize: Artifact = undefined,
    failure_signal_handler: Artifact = undefined,
    leak_check: Artifact = undefined,
};

const Synchronization = struct {
    graphcycles_internal: Artifact = undefined,
    kernel_timeout_internal: Artifact = undefined,
    synchronization: Artifact = undefined,
};

const Profiling = struct {
    exponential_biased: Artifact = undefined,
    periodic_sampler: Artifact = undefined,
};

const Hash = struct {
    city: Artifact = undefined,
    hash: Artifact = undefined,
};

const Crc = struct {
    crc_internal: Artifact = undefined,
    non_temporal_memcpy: Artifact = undefined,
    crc32c: Artifact = undefined,
    crc_cord_state: Artifact = undefined,
};

const Container = struct {
    hashtablez_sampler: Artifact = undefined,
    raw_hash_set: Artifact = undefined,
};

const Status = struct {
    status: Artifact = undefined,
    statusor: Artifact = undefined,
    status_builder: Artifact = undefined,
};

const Log = struct {
    foundation: Artifact = undefined,
    sink_set: Artifact = undefined,
    message: Artifact = undefined,
    globals: Artifact = undefined,
    initialize: Artifact = undefined,
    die_if_null: Artifact = undefined,
    flags: Artifact = undefined,
};

const Flags = struct {
    commandlineflag: Artifact = undefined,
    marshalling: Artifact = undefined,
    reflection: Artifact = undefined,
    flag: Artifact = undefined,
    parse: Artifact = undefined,
};

const Random = struct {
    random_internal: Artifact = undefined,
    distributions: Artifact = undefined,
    seed_sequences: Artifact = undefined,
};

b: *std.Build,
metadata: Metadata,

base: Base = .{},
numeric: Numeric = .{},
types: Types = .{},
strings: Strings = .{},
time: Time = .{},
debugging: Debugging = .{},
synchronization: Synchronization = .{},
profiling: Profiling = .{},
hash: Hash = .{},
crc: Crc = .{},
container: Container = .{},
status: Status = .{},
log: Log = .{},
flags: Flags = .{},
random: Random = .{},

pub fn init(b: *std.Build, config: Config) ?*Self {
    const upstream = b.lazyDependency("abseil", .{}) orelse return null;

    const self = b.allocator.create(Self) catch @panic("OOM");
    self.* = .{
        .b = b,
        .metadata = .{
            .upstream = upstream,
            .config = config,
            .root = upstream.path("absl"),
            .upstream_root = upstream.path(""),
        },
    };
    return self;
}

/// This function was written mostly by Claude
pub fn build(self: *Self) void {
    const b = self.b;
    const cctz_include = self.metadata.root.path(b, "time/internal/cctz/include");

    // Tier 0: No compiled absl dependencies
    self.base.raw_logging_internal = self.buildAbslLib(.{
        .name = "raw_logging_internal",
        .sources = &base_mod.raw_logging_sources,
    });

    self.base.spinlock_wait = self.buildAbslLib(.{
        .name = "spinlock_wait",
        .sources = &base_mod.spinlock_wait_sources,
    });

    self.base.strerror = self.buildAbslLib(.{
        .name = "strerror",
        .sources = &base_mod.strerror_sources,
    });

    self.numeric.int128 = self.buildAbslLib(.{
        .name = "int128",
        .sources = &.{"numeric/int128.cc"},
    });

    self.types.source_location = self.buildAbslLib(.{
        .name = "source_location",
        .sources = &.{"types/source_location.cc"},
    });

    // Tier 1: depend only on tier-0 artifacts
    self.base.throw_delegate = self.buildAbslLib(.{
        .name = "throw_delegate",
        .sources = &base_mod.throw_delegate_sources,
        .link_libraries = &.{self.base.raw_logging_internal},
    });

    self.base.base = self.buildAbslLib(.{
        .name = "base",
        .sources = &base_mod.base_sources,
        .link_libraries = &.{
            self.base.raw_logging_internal,
            self.base.spinlock_wait,
        },
    });

    // Tier 2: depend on base
    self.base.malloc_internal = self.buildAbslLib(.{
        .name = "malloc_internal",
        .sources = &base_mod.malloc_internal_sources,
        .link_libraries = &.{
            self.base.base,
            self.base.raw_logging_internal,
        },
    });

    self.base.tracing_internal = self.buildAbslLib(.{
        .name = "tracing_internal",
        .sources = &base_mod.tracing_internal_sources,
        .link_libraries = &.{self.base.base},
    });

    // Tier 3: strings (depend on base + numeric)
    self.strings.internal = self.buildAbslLib(.{
        .name = "strings_internal",
        .sources = &strings_mod.internal_sources,
        .link_libraries = &.{self.base.raw_logging_internal},
    });

    self.strings.strings = self.buildAbslLib(.{
        .name = "strings",
        .sources = &strings_mod.strings_sources,
        .link_libraries = &.{
            self.strings.internal,
            self.base.base,
            self.base.throw_delegate,
            self.base.raw_logging_internal,
            self.numeric.int128,
        },
    });

    self.strings.str_format_internal = self.buildAbslLib(.{
        .name = "str_format_internal",
        .sources = &strings_mod.str_format_sources,
        .link_libraries = &.{
            self.strings.strings,
            self.strings.internal,
            self.numeric.int128,
        },
    });

    // Tier 4: CRC (depends on base + strings + str_format)
    self.crc.crc_internal = self.buildAbslLib(.{
        .name = "crc_internal",
        .sources = &.{
            "crc/internal/crc.cc",
            "crc/internal/crc_memcpy_fallback.cc",
            "crc/internal/crc_memcpy_x86_arm_combined.cc",
            "crc/internal/crc_x86_arm_combined.cc",
        },
        .link_libraries = &.{
            self.base.base,
            self.base.raw_logging_internal,
        },
    });

    self.crc.non_temporal_memcpy = self.buildAbslLib(.{
        .name = "non_temporal_memcpy",
        .sources = &.{"crc/internal/crc_non_temporal_memcpy.cc"},
    });

    self.crc.crc32c = self.buildAbslLib(.{
        .name = "crc32c",
        .sources = &.{"crc/crc32c.cc"},
        .link_libraries = &.{
            self.crc.crc_internal,
            self.crc.non_temporal_memcpy,
            self.strings.strings,
            self.strings.str_format_internal,
            self.base.base,
        },
    });

    self.crc.crc_cord_state = self.buildAbslLib(.{
        .name = "crc_cord_state",
        .sources = &.{"crc/internal/crc_cord_state.cc"},
        .link_libraries = &.{
            self.crc.crc32c,
            self.base.base,
        },
    });

    // Tier 5: CCTZ and core time

    // cctz needs its own include directory for the short-form cctz/ prefix.
    {
        const lib = self.addLibrary(.{
            .name = "cctz",
            .root = self.metadata.root,
            .sources = &time_mod.cctz_sources,
        });
        lib.root_module.addIncludePath(self.metadata.upstream_root);
        lib.root_module.addIncludePath(cctz_include);
        self.time.cctz = lib;
    }

    {
        const lib = self.addLibrary(.{
            .name = "time",
            .root = self.metadata.root,
            .sources = &time_mod.time_sources,
            .link_libraries = &.{
                self.time.cctz,
                self.base.base,
                self.base.raw_logging_internal,
                self.numeric.int128,
                self.strings.strings,
            },
        });
        lib.root_module.addIncludePath(self.metadata.upstream_root);
        lib.root_module.addIncludePath(cctz_include);
        self.time.time = lib;
    }

    // Tier 6: debugging
    self.debugging.debugging_internal = self.buildAbslLib(.{
        .name = "debugging_internal",
        .sources = &.{
            "debugging/internal/address_is_readable.cc",
            "debugging/internal/elf_mem_image.cc",
            "debugging/internal/vdso_support.cc",
        },
        .link_libraries = &.{self.base.raw_logging_internal},
    });

    self.debugging.demangle_internal = self.buildAbslLib(.{
        .name = "demangle_internal",
        .sources = &.{
            "debugging/internal/decode_rust_punycode.cc",
            "debugging/internal/demangle.cc",
            "debugging/internal/demangle_rust.cc",
            "debugging/internal/utf8_for_code_point.cc",
        },
        .link_libraries = &.{
            self.debugging.debugging_internal,
            self.base.base,
        },
    });

    self.debugging.stacktrace = self.buildAbslLib(.{
        .name = "stacktrace",
        .sources = &.{"debugging/stacktrace.cc"},
        .link_libraries = &.{
            self.debugging.debugging_internal,
            self.base.base,
            self.base.malloc_internal,
            self.base.raw_logging_internal,
        },
    });

    self.debugging.leak_check = self.buildAbslLib(.{
        .name = "leak_check",
        .sources = &.{"debugging/leak_check.cc"},
        .link_libraries = &.{self.base.base},
    });

    self.debugging.symbolize = self.buildAbslLib(.{
        .name = "symbolize",
        .sources = &.{"debugging/symbolize.cc"},
        .link_libraries = &.{
            self.debugging.debugging_internal,
            self.debugging.demangle_internal,
            self.base.base,
            self.base.malloc_internal,
            self.base.raw_logging_internal,
            self.strings.strings,
        },
    });

    // failure_signal_handler bundles examine_stack
    self.debugging.failure_signal_handler = self.buildAbslLib(.{
        .name = "failure_signal_handler",
        .sources = &.{
            "debugging/failure_signal_handler.cc",
            "debugging/internal/examine_stack.cc",
        },
        .link_libraries = &.{
            self.debugging.stacktrace,
            self.debugging.symbolize,
            self.base.base,
            self.base.raw_logging_internal,
        },
    });

    // Tier 7: synchronization
    self.synchronization.graphcycles_internal = self.buildAbslLib(.{
        .name = "graphcycles_internal",
        .sources = &synchronization_mod.graphcycles_sources,
        .link_libraries = &.{
            self.base.base,
            self.base.malloc_internal,
            self.base.raw_logging_internal,
        },
    });

    self.synchronization.kernel_timeout_internal = self.buildAbslLib(.{
        .name = "kernel_timeout_internal",
        .sources = &synchronization_mod.kernel_timeout_sources,
        .link_libraries = &.{
            self.base.base,
            self.base.raw_logging_internal,
            self.time.time,
        },
    });

    self.synchronization.synchronization = self.buildAbslLib(.{
        .name = "synchronization",
        .sources = &synchronization_mod.synchronization_sources,
        .link_libraries = &.{
            self.synchronization.graphcycles_internal,
            self.synchronization.kernel_timeout_internal,
            self.base.base,
            self.base.malloc_internal,
            self.base.raw_logging_internal,
            self.base.tracing_internal,
            self.debugging.stacktrace,
            self.debugging.symbolize,
            self.time.time,
        },
    });

    // Tier 7b: time artifacts that require synchronization
    {
        const lib = self.addLibrary(.{
            .name = "clock_interface",
            .root = self.metadata.root,
            .sources = &time_mod.clock_interface_sources,
            .link_libraries = &.{
                self.time.time,
                self.base.base,
                self.base.raw_logging_internal,
                self.synchronization.synchronization,
            },
        });
        lib.root_module.addIncludePath(self.metadata.upstream_root);
        lib.root_module.addIncludePath(cctz_include);
        self.time.clock_interface = lib;
    }

    {
        const lib = self.addLibrary(.{
            .name = "simulated_clock",
            .root = self.metadata.root,
            .sources = &time_mod.simulated_clock_sources,
            .link_libraries = &.{
                self.time.clock_interface,
                self.time.time,
                self.base.base,
                self.synchronization.synchronization,
            },
        });
        lib.root_module.addIncludePath(self.metadata.upstream_root);
        lib.root_module.addIncludePath(cctz_include);
        self.time.simulated_clock = lib;
    }

    // Tier 8: profiling (needs sync + time)
    self.profiling.exponential_biased = self.buildAbslLib(.{
        .name = "exponential_biased",
        .sources = &.{"profiling/internal/exponential_biased.cc"},
    });

    self.profiling.periodic_sampler = self.buildAbslLib(.{
        .name = "periodic_sampler",
        .sources = &.{"profiling/internal/periodic_sampler.cc"},
        .link_libraries = &.{self.profiling.exponential_biased},
    });

    // Tier 9: hash (depends on strings + numeric)
    self.hash.city = self.buildAbslLib(.{
        .name = "hash_city",
        .sources = &.{"hash/internal/city.cc"},
    });

    self.hash.hash = self.buildAbslLib(.{
        .name = "hash",
        .sources = &.{"hash/internal/hash.cc"},
        .link_libraries = &.{
            self.hash.city,
            self.strings.strings,
            self.numeric.int128,
            self.base.base,
        },
    });

    // Tier 10: cord (depends on crc, sync, time, debugging, profiling)
    self.strings.cord_internal = self.buildAbslLib(.{
        .name = "cord_internal",
        .sources = &strings_mod.cord_internal_sources,
        .link_libraries = &.{
            self.strings.strings,
            self.crc.crc_cord_state,
            self.base.base,
            self.base.raw_logging_internal,
        },
    });

    self.strings.cordz_handle = self.buildAbslLib(.{
        .name = "cordz_handle",
        .sources = &strings_mod.cordz_handle_sources,
        .link_libraries = &.{
            self.base.base,
            self.base.raw_logging_internal,
            self.synchronization.synchronization,
        },
    });

    self.strings.cordz_functions = self.buildAbslLib(.{
        .name = "cordz_functions",
        .sources = &strings_mod.cordz_functions_sources,
        .link_libraries = &.{
            self.base.base,
            self.base.raw_logging_internal,
            self.profiling.exponential_biased,
        },
    });

    self.strings.cordz_info = self.buildAbslLib(.{
        .name = "cordz_info",
        .sources = &strings_mod.cordz_info_sources,
        .link_libraries = &.{
            self.strings.cord_internal,
            self.strings.cordz_handle,
            self.strings.cordz_functions,
            self.base.base,
            self.base.raw_logging_internal,
            self.debugging.stacktrace,
            self.synchronization.synchronization,
            self.time.time,
        },
    });

    self.strings.cord = self.buildAbslLib(.{
        .name = "cord",
        .sources = &strings_mod.cord_sources,
        .link_libraries = &.{
            self.strings.cord_internal,
            self.strings.cordz_info,
            self.strings.cordz_handle,
            self.strings.cordz_functions,
            self.strings.strings,
            self.strings.internal,
            self.strings.str_format_internal,
            self.crc.crc32c,
            self.crc.crc_cord_state,
            self.base.base,
            self.base.raw_logging_internal,
        },
    });

    // Tier 11: container (depends on hash, strings, sync, time, profiling, debugging)
    self.container.hashtablez_sampler = self.buildAbslLib(.{
        .name = "hashtablez_sampler",
        .sources = &.{
            "container/internal/hashtablez_sampler.cc",
            "container/internal/hashtablez_sampler_force_weak_definition.cc",
        },
        .link_libraries = &.{
            self.base.base,
            self.base.raw_logging_internal,
            self.debugging.stacktrace,
            self.profiling.exponential_biased,
            self.synchronization.synchronization,
            self.time.time,
        },
    });

    self.container.raw_hash_set = self.buildAbslLib(.{
        .name = "raw_hash_set",
        .sources = &.{"container/internal/raw_hash_set.cc"},
        .link_libraries = &.{
            self.container.hashtablez_sampler,
            self.base.base,
            self.base.raw_logging_internal,
            self.base.throw_delegate,
            self.hash.hash,
            self.strings.strings,
        },
    });

    // Tier 12: status (depends on cord, hash, debugging, container)
    self.status.status = self.buildAbslLib(.{
        .name = "status",
        .sources = &.{
            "status/status.cc",
            "status/status_payload_printer.cc",
            "status/internal/status_internal.cc",
        },
        .link_libraries = &.{
            self.base.base,
            self.base.raw_logging_internal,
            self.base.strerror,
            self.debugging.leak_check,
            self.debugging.stacktrace,
            self.debugging.symbolize,
            self.hash.hash,
            self.strings.strings,
            self.strings.cord,
            self.strings.str_format_internal,
            self.types.source_location,
        },
    });

    self.status.statusor = self.buildAbslLib(.{
        .name = "statusor",
        .sources = &.{"status/statusor.cc"},
        .link_libraries = &.{
            self.status.status,
            self.base.base,
            self.base.raw_logging_internal,
            self.strings.strings,
            self.strings.str_format_internal,
        },
    });

    self.status.status_builder = self.buildAbslLib(.{
        .name = "status_builder",
        .sources = &.{"status/status_builder.cc"},
        .link_libraries = &.{
            self.status.status,
            self.base.base,
            self.strings.strings,
            self.strings.cord,
            self.strings.internal,
            self.strings.str_format_internal,
            self.time.time,
            self.types.source_location,
        },
    });

    // Tier 13a: log foundation (no sync dep)
    self.log.foundation = self.buildAbslLib(.{
        .name = "log_foundation",
        .sources = &log_mod.foundation_sources,
        .link_libraries = &.{
            self.base.base,
            self.base.raw_logging_internal,
            self.strings.strings,
            self.strings.internal,
            self.strings.str_format_internal,
            self.time.time,
            self.types.source_location,
        },
    });

    // Tier 13b: log with sync dep
    self.log.sink_set = self.buildAbslLib(.{
        .name = "log_sink_set",
        .sources = &log_mod.sink_set_sources,
        .link_libraries = &.{
            self.log.foundation,
            self.base.base,
            self.base.raw_logging_internal,
            self.strings.strings,
            self.synchronization.synchronization,
        },
    });

    self.log.message = self.buildAbslLib(.{
        .name = "log_message",
        .sources = &log_mod.message_sources,
        .link_libraries = &.{
            self.log.foundation,
            self.log.sink_set,
            self.base.base,
            self.base.raw_logging_internal,
            self.strings.strings,
            self.strings.str_format_internal,
            self.synchronization.synchronization,
            self.time.time,
        },
    });

    self.log.globals = self.buildAbslLib(.{
        .name = "log_globals",
        .sources = &log_mod.globals_sources,
        .link_libraries = &.{
            self.log.foundation,
            self.base.base,
            self.base.raw_logging_internal,
            self.hash.hash,
            self.strings.strings,
        },
    });

    self.log.initialize = self.buildAbslLib(.{
        .name = "log_initialize",
        .sources = &log_mod.initialize_sources,
        .link_libraries = &.{
            self.log.globals,
            self.log.foundation,
            self.time.time,
        },
    });

    self.log.die_if_null = self.buildAbslLib(.{
        .name = "log_die_if_null",
        .sources = &log_mod.die_if_null_sources,
        .link_libraries = &.{
            self.log.message,
            self.log.globals,
            self.base.base,
            self.base.raw_logging_internal,
            self.strings.strings,
            self.types.source_location,
        },
    });

    // Tier 14: flags (depends on sync, container, strings)

    // commandlineflag: base class, program-name, usage-config.
    self.flags.commandlineflag = self.buildAbslLib(.{
        .name = "flags_commandlineflag",
        .sources = &.{
            "flags/commandlineflag.cc",
            "flags/internal/commandlineflag.cc",
            "flags/internal/program_name.cc",
            "flags/usage_config.cc",
        },
        .link_libraries = &.{
            self.base.base,
            self.base.raw_logging_internal,
            self.strings.strings,
            self.synchronization.synchronization,
        },
    });

    // marshalling: flag value parse/unparse, including int128 and log_severity.
    self.flags.marshalling = self.buildAbslLib(.{
        .name = "flags_marshalling",
        .sources = &.{"flags/marshalling.cc"},
        .link_libraries = &.{
            self.base.base,
            self.strings.strings,
            self.strings.str_format_internal,
            self.numeric.int128,
        },
    });

    // reflection: flag registry + private_handle_accessor.
    self.flags.reflection = self.buildAbslLib(.{
        .name = "flags_reflection",
        .sources = &.{
            "flags/reflection.cc",
            "flags/internal/private_handle_accessor.cc",
        },
        .link_libraries = &.{
            self.flags.commandlineflag,
            self.flags.marshalling,
            self.base.base,
            self.base.raw_logging_internal,
            self.container.raw_hash_set,
            self.strings.strings,
            self.synchronization.synchronization,
        },
    });

    // flag: the actual flag object implementation.
    self.flags.flag = self.buildAbslLib(.{
        .name = "flags_flag",
        .sources = &.{"flags/internal/flag.cc"},
        .link_libraries = &.{
            self.flags.commandlineflag,
            self.flags.marshalling,
            self.flags.reflection,
            self.base.base,
            self.base.raw_logging_internal,
            self.strings.strings,
            self.synchronization.synchronization,
        },
    });

    // parse: command-line parsing + usage text generation.
    self.flags.parse = self.buildAbslLib(.{
        .name = "flags_parse",
        .sources = &.{
            "flags/parse.cc",
            "flags/usage.cc",
            "flags/internal/usage.cc",
        },
        .link_libraries = &.{
            self.flags.commandlineflag,
            self.flags.flag,
            self.flags.marshalling,
            self.flags.reflection,
            self.base.base,
            self.base.raw_logging_internal,
            self.container.raw_hash_set,
            self.strings.strings,
            self.strings.str_format_internal,
            self.synchronization.synchronization,
        },
    });

    // Tier 14b: log::flags bridge (built after flags)
    self.log.flags = self.buildAbslLib(.{
        .name = "log_flags",
        .sources = &log_mod.flags_sources,
        .link_libraries = &.{
            self.log.globals,
            self.log.foundation,
            self.flags.flag,
            self.flags.marshalling,
            self.base.base,
            self.base.raw_logging_internal,
            self.strings.strings,
        },
    });

    // Tier 15: random (depends on base + strings; no sync dep)
    self.random.random_internal = self.buildAbslLib(.{
        .name = "random_internal",
        .sources = &random_mod.random_internal_sources,
        .link_libraries = &.{
            self.base.base,
            self.base.raw_logging_internal,
            self.strings.strings,
        },
    });

    self.random.distributions = self.buildAbslLib(.{
        .name = "random_distributions",
        .sources = &random_mod.distributions_sources,
        .link_libraries = &.{
            self.random.random_internal,
            self.base.base,
            self.strings.strings,
        },
    });

    self.random.seed_sequences = self.buildAbslLib(.{
        .name = "random_seed_sequences",
        .sources = &random_mod.seed_sequences_sources,
        .link_libraries = &.{
            self.random.random_internal,
            self.base.base,
            self.base.raw_logging_internal,
            self.strings.strings,
        },
    });
}

/// Convenience wrapper around addLibrary for standard absl libraries
fn buildAbslLib(self: *const Self, config: struct {
    name: []const u8,
    sources: []const []const u8,
    link_libraries: []const Artifact = &.{},
}) Artifact {
    const lib = self.addLibrary(.{
        .name = config.name,
        .root = self.metadata.root,
        .sources = config.sources,
        .link_libraries = config.link_libraries,
    });
    lib.root_module.addIncludePath(self.metadata.upstream_root);
    return lib;
}

/// Adds a library to the build graph that can be linked against
fn addLibrary(self: *const Self, config: struct {
    name: []const u8,
    root: std.Build.LazyPath,
    sources: []const []const u8,
    link_libraries: []const Artifact = &.{},
    extra_include_paths: []const std.Build.LazyPath = &.{},
    config_headers: []const *std.Build.Step.ConfigHeader = &.{},
}) Artifact {
    const b = self.b;
    const mod = b.createModule(.{
        .target = self.metadata.config.target,
        .optimize = self.metadata.config.optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    mod.addCSourceFiles(.{
        .root = config.root,
        .files = config.sources,
        .flags = &compile_flags,
    });
    mod.addIncludePath(config.root);
    for (config.extra_include_paths) |inc| mod.addIncludePath(inc);
    for (config.config_headers) |header| mod.addConfigHeader(header);
    for (config.link_libraries) |link| mod.linkLibrary(link);

    const lib = b.addLibrary(.{
        .name = b.fmt("absl_{s}", .{config.name}),
        .root_module = mod,
    });

    lib.installHeadersDirectory(config.root, "absl", .{
        .include_extensions = &.{ ".h", ".inc" },
    });
    for (config.link_libraries) |link| lib.installLibraryHeaders(link);
    for (config.config_headers) |header| lib.installConfigHeader(header);

    return lib;
}

const compile_flags = [_][]const u8{
    "-std=c++23",
    "-Wall",
    "-Wmost",
    "-Wextra",
    "-Wc++98-compat-extra-semi",
    "-Wcast-qual",
    "-Wconversion",
    "-Wdeprecated-pragma",
    "-Wfloat-overflow-conversion",
    "-Wfloat-zero-conversion",
    "-Wfor-loop-analysis",
    "-Wformat-security",
    "-Wgnu-redeclared-enum",
    "-Winfinite-recursion",
    "-Winvalid-constexpr",
    "-Wliteral-conversion",
    "-Wmissing-declarations",
    "-Wnullability-completeness",
    "-Woverlength-strings",
    "-Wpointer-arith",
    "-Wself-assign",
    "-Wshadow-all",
    "-Wshorten-64-to-32",
    "-Wsign-conversion",
    "-Wstring-conversion",
    "-Wtautological-overlap-compare",
    "-Wtautological-unsigned-zero-compare",
    "-Wthread-safety",
    "-Wundef",
    "-Wuninitialized",
    "-Wunreachable-code",
    "-Wunused-comparison",
    "-Wunused-local-typedefs",
    "-Wunused-result",
    "-Wvla",
    "-Wwrite-strings",
    "-Wno-float-conversion",
    "-Wno-implicit-float-conversion",
    "-Wno-implicit-int-float-conversion",
    "-Wno-unknown-warning-option",
    "-Wno-unused-command-line-argument",
    "-DNOMINMAX",
};
