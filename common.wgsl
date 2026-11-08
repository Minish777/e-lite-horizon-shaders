// E-LITE quality profile (ACERCADE / OptiFine profiles): 0 No effects, 1 Very low, 2 Low,
// 3 Medium, 4 High, 5 Max. Scales the screen-space effects; the shadow map size is fixed
// in horizon-shaders.toml [shadow] (Medium: 2048, 128 blocks).
override quality_profile: u32 = 3u;

fn profile_scale() -> f32 {
    if quality_profile == 0u { return 0.0; }
    if quality_profile == 1u { return 0.25; }
    if quality_profile == 2u { return 0.55; }
    if quality_profile == 4u { return 1.1; }
    if quality_profile == 5u { return 1.35; }
    return 0.85;
}

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

// 1 while the sun is up in the Overworld, fading out around the horizon.
fn daylight() -> f32 {
    return select(0.0, smoothstep(-0.1, 0.1, frame.sun_direction.y), frame.dimension == 0);
}

// 1 when the sun is on the horizon, 0 from a third of the way up.
fn sun_low() -> f32 {
    return 1.0 - smoothstep(0.0, 0.35, abs(frame.sun_direction.y));
}

fn grade_saturation(c: vec3<f32>, amount: f32) -> vec3<f32> {
    return mix(vec3<f32>(luminance(c)), c, amount);
}

// Interleaved gradient noise: a fixed 0..1 pattern per pixel, so nothing flickers from frame to frame.
fn ign(pixel: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(pixel, vec2<f32>(0.06711056, 0.00583715))));
}

// A 0..1 hash of three integers (PCG), exact at any distance from the world's origin.
fn hash3(v: vec3<u32>) -> f32 {
    var s = v.x * 1664525u + v.y * 22695477u + v.z * 134775813u + 1013904223u;
    s = s * 747796405u + 2891336453u;
    let w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
    return f32((w >> 22u) ^ w) / 4294967296.0;
}

// The shadow camera's depth range in blocks: 256 in front, 100 + 2 * distance + 384 behind
// (native_shadow.rs `camera`). A depth bias in blocks divides by this.
fn shadow_range() -> f32 {
    return 740.0 + 2.0 * frame.shadow_distance;
}

// The ground one shadow texel covers where the map is read at `xy` (0..1 texture coordinates), in blocks.
// The map is distorted toward its centre, so its texels grow with the distance from it.
fn shadow_texel_at(xy: vec2<f32>) -> f32 {
    let k = frame.shadow_distortion;
    let stored = min(length(vec2<f32>(xy.x * 2.0 - 1.0, 1.0 - 2.0 * xy.y)), 0.999);
    let clip = stored * (1.0 - k) / max(1.0 - k * stored, 0.001);
    let magnify = (1.0 - k) / pow(k * clip + 1.0 - k, 2.0);
    return 2.0 * frame.shadow_distance / max(frame.shadow_resolution, 1.0) / max(magnify, 0.05);
}
