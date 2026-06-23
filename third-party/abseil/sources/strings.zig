pub const root = "strings";

pub const internal_sources = [_][]const u8{
    "strings/internal/damerau_levenshtein_distance.cc",
    "strings/internal/escaping.cc",
    "strings/internal/memutil.cc",
    "strings/internal/ostringstream.cc",
    "strings/internal/pow10_helper.cc",
    "strings/internal/stringify_sink.cc",
    "strings/internal/utf8.cc",
};

pub const strings_sources = [_][]const u8{
    "strings/ascii.cc",
    "strings/charconv.cc",
    "strings/escaping.cc",
    "strings/internal/charconv_bigint.cc",
    "strings/internal/charconv_parse.cc",
    "strings/match.cc",
    "strings/numbers.cc",
    "strings/str_cat.cc",
    "strings/str_replace.cc",
    "strings/str_split.cc",
    "strings/substitute.cc",
};

pub const str_format_sources = [_][]const u8{
    "strings/internal/str_format/arg.cc",
    "strings/internal/str_format/bind.cc",
    "strings/internal/str_format/extension.cc",
    "strings/internal/str_format/float_conversion.cc",
    "strings/internal/str_format/output.cc",
    "strings/internal/str_format/parser.cc",
};

pub const cord_internal_sources = [_][]const u8{
    "strings/internal/cord_internal.cc",
    "strings/internal/cord_rep_btree.cc",
    "strings/internal/cord_rep_btree_navigator.cc",
    "strings/internal/cord_rep_btree_reader.cc",
    "strings/internal/cord_rep_consume.cc",
    "strings/internal/cord_rep_crc.cc",
};

pub const cordz_handle_sources = [_][]const u8{
    "strings/internal/cordz_handle.cc",
};

pub const cordz_functions_sources = [_][]const u8{
    "strings/internal/cordz_functions.cc",
};

pub const cordz_info_sources = [_][]const u8{
    "strings/internal/cordz_info.cc",
    "strings/internal/cordz_sample_token.cc",
};

pub const cord_sources = [_][]const u8{
    "strings/cord.cc",
    "strings/cord_analysis.cc",
};
