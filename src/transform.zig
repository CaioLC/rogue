const std = @import("std");
const zmath = @import("zmath");

pub const Transform = struct {
    position: zmath.Vec,
    rotation: zmath.Vec,
    scale: zmath.Vec,
};

// rotate world view
const S = zmath.scaling(0.6, 0.6, 0.6);
const R1 = zmath.rotationX(-3.0 * 3.14 / 4.0);
const T = zmath.translation(0.0, 0.0, 0.0);
const M = mul(mul(S, R1), T);
