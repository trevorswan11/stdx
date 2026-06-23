pub const root = "time";

pub const cctz_sources = [_][]const u8{
    "time/internal/cctz/src/civil_time_detail.cc",
    "time/internal/cctz/src/time_zone_fixed.cc",
    "time/internal/cctz/src/time_zone_format.cc",
    "time/internal/cctz/src/time_zone_if.cc",
    "time/internal/cctz/src/time_zone_impl.cc",
    "time/internal/cctz/src/time_zone_info.cc",
    "time/internal/cctz/src/time_zone_libc.cc",
    "time/internal/cctz/src/time_zone_lookup.cc",
    "time/internal/cctz/src/zone_info_source.cc",
    "time/internal/cctz/src/time_zone_posix.cc",
};

pub const win_sources = [_][]const u8{
    "time/internal/cctz/src/time_zone_name_win.cc",
};

pub const time_sources = [_][]const u8{
    "time/civil_time.cc",
    "time/clock.cc",
    "time/duration.cc",
    "time/format.cc",
    "time/time.cc",
};
