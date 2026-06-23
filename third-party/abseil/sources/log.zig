pub const root = "log";

pub const foundation_sources = [_][]const u8{
    "log/internal/check_op.cc",
    "log/internal/conditions.cc",
    "log/internal/fnmatch.cc",
    "log/internal/globals.cc",
    "log/internal/log_format.cc",
    "log/internal/nullguard.cc",
    "log/internal/proto.cc",
    "log/internal/structured_proto.cc",
    "log/internal/vlog_config.cc",
    "log/log_entry.cc",
    "log/log_sink.cc",
};

pub const sink_set_sources = [_][]const u8{
    "log/internal/log_sink_set.cc",
};

pub const message_sources = [_][]const u8{
    "log/internal/log_message.cc",
};

pub const globals_sources = [_][]const u8{
    "log/globals.cc",
};

pub const initialize_sources = [_][]const u8{
    "log/initialize.cc",
};

pub const die_if_null_sources = [_][]const u8{
    "log/die_if_null.cc",
};

pub const flags_sources = [_][]const u8{
    "log/flags.cc",
};
