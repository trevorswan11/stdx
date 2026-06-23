pub const root = "random";

pub const random_internal_sources = [_][]const u8{
    "random/internal/entropy_pool.cc",
    "random/internal/gaussian_distribution_gentables.cc",
    "random/internal/randen.cc",
    "random/internal/randen_detect.cc",
    "random/internal/randen_hwaes.cc",
    "random/internal/randen_round_keys.cc",
    "random/internal/randen_slow.cc",
    "random/internal/seed_material.cc",
};

pub const distributions_sources = [_][]const u8{
    "random/discrete_distribution.cc",
    "random/gaussian_distribution.cc",
};

pub const seed_sequences_sources = [_][]const u8{
    "random/seed_gen_exception.cc",
    "random/seed_sequences.cc",
};
