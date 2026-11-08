// Temporal smoothing: each pixel is blended with where it was last frame, so the shimmer of leaves,
// grass and thin geometry, and the flicker of noisy effects, calm down. Vanilla gives the pack no
// jittered projection, so this is not true supersampling: nothing new is accumulated per frame, only
// the history is smoothed. Pixels are reprojected with depth (the sky by its view direction), the
// history is clipped to the current 3x3 neighbourhood in YCoCg so moving edges do not ghost, and the
// history is read through a 5-tap Catmull-Rom filter so it stays sharp.
// It runs second to last, so `history` is this pass's own output from last frame.
override taa: bool = false;
override debug_view: u32 = 0u;

// YCoCg holds brightness and colour more evenly than RGB, which makes the variance clip fit edges
// better. Y is luminance, Co orange-vs-blue, Cg green-vs-magenta.
fn rgb_to_ycocg(c: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
        dot(c, vec3<f32>(0.25, 0.5, 0.25)),
        dot(c, vec3<f32>(0.5, 0.0, -0.5)),
        dot(c, vec3<f32>(-0.25, 0.5, -0.25)));
}

fn ycocg_to_rgb(c: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
        c.x + c.y - c.z,
        c.x + c.z,
        c.x - c.y - c.z);
}

// Reinhard in brightness only: c / (1 + luminance(c)). Blending in this space keeps a single very
// bright history pixel (a firefly) from dominating the average; `untone` inverts it exactly.
fn tonemap(c: vec3<f32>) -> vec3<f32> {
    return c / (1.0 + luminance(c));
}

fn untone(c: vec3<f32>) -> vec3<f32> {
    return c / max(1.0 - luminance(c), 0.0001);
}

// Moves `c` toward the AABB centre only as far as it must to get inside (Salvi's intersection):
// a colour already inside is untouched, so a calm pixel keeps its full history. `extents` is the
// AABB's half-size.
fn clip_toward_centre(c: vec3<f32>, centre: vec3<f32>, extents: vec3<f32>) -> vec3<f32> {
    let d = centre - c;
    let ad = abs(d);
    let e = max(extents, vec3<f32>(1e-6));
    // The fraction of the way to the centre at which each axis first enters the box; the last axis
    // to enter decides. Inside the box every term is 0, so nothing moves.
    let tx = max(1.0 - e.x / max(ad.x, 1e-6), 0.0);
    let ty = max(1.0 - e.y / max(ad.y, 1e-6), 0.0);
    let tz = max(1.0 - e.z / max(ad.z, 1e-6), 0.0);
    return c + d * clamp(max(tx, max(ty, tz)), 0.0, 1.0);
}

// One bilinear tap of the history (this pass's own output last frame).
fn history_tap(uv: vec2<f32>) -> vec3<f32> {
    return textureSampleLevel(history, linear_sampler, uv, 0.0).rgb;
}

// A 5-tap bicubic (Catmull-Rom) reconstruction of the history, the same approximation MiniEngine
// uses: five bilinear taps, sharper than a single bilinear read, so reprojection softens only a
// little. The sampler clamps at the edges.
fn history_catmull_rom(uv: vec2<f32>) -> vec3<f32> {
    let size = vec2<f32>(textureDimensions(history));
    let rcp = vec2<f32>(1.0) / size;
    let st = uv * size - vec2<f32>(0.5);
    let fractional = fract(st);
    let base = (floor(st) + vec2<f32>(0.5)) * rcp;

    let t = fractional;
    let t2 = t * t;
    let t3 = t2 * t;
    let s = 0.5;
    let w0 = -s * t3 + 2.0 * s * t2 - s * t;
    let w1 = (2.0 - s) * t3 + (s - 3.0) * t2 + vec2<f32>(1.0);
    let w2 = (s - 2.0) * t3 + (3.0 - 2.0 * s) * t2 + s * t;
    let w3 = s * t3 - s * t2;
    let s0 = w1 + w2;
    let f0 = w2 / max(w1 + w2, vec2<f32>(1e-5));
    let m0 = base + f0 * rcp;
    let tc0 = base - rcp;
    let tc3 = base + 2.0 * rcp;

    let a = history_tap(vec2<f32>(m0.x, tc0.y));
    let b = history_tap(vec2<f32>(tc0.x, m0.y));
    let c = history_tap(vec2<f32>(m0.x, m0.y));
    let d = history_tap(vec2<f32>(tc3.x, m0.y));
    let e = history_tap(vec2<f32>(m0.x, tc3.y));
    return (0.5 * (a + b) * w0.x + a * s0.x + 0.5 * (a + b) * w3.x) * w0.y
        + (b * w0.x + c * s0.x + d * w3.x) * s0.y
        + (0.5 * (b + e) * w0.x + e * s0.x + 0.5 * (d + e) * w3.x) * w3.y;
}

fn post(input: PostInput) -> vec4<f32> {
    if !taa || debug_view != 0u {
        return input.color;
    }

    // Where this pixel's surface was on screen last frame. The sky (depth 0) is at infinity, so only
    // the camera's rotation moves it: reproject a point far along its view ray.
    var p: vec3<f32>;
    if input.depth > 0.0 {
        p = view_position(input.uv, input.depth);
    } else {
        let raw = view_position(input.uv, 0.0001);
        let len = length(raw);
        let direction = select(vec3<f32>(0.0, 0.0, -1.0), raw / max(len, 1e-6), len > 1e-6);
        p = direction * 1000.0;
    }
    let clip = frame.previous_view_projection * vec4<f32>(p + frame.camera_motion, 1.0);
    let prev_uv = vec2<f32>(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5);
    let valid = clip.w > 0.0
        && prev_uv.x >= 0.0 && prev_uv.x <= 1.0
        && prev_uv.y >= 0.0 && prev_uv.y <= 1.0
        && frame.delta_time > 0.0;
    if !valid {
        return vec4<f32>(max(input.color.rgb, vec3<f32>(0.0)), input.color.a);
    }

    // The current 3x3 neighbourhood, in YCoCg: its mean and standard deviation are the AABB the
    // history must lie in. Gamma 1.0 keeps a little more history than a tighter box would.
    let dims = vec2<i32>(textureDimensions(previous));
    let here = vec2<i32>(input.pixel);
    var m1 = vec3<f32>(0.0);
    var m2 = vec3<f32>(0.0);
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let coords = clamp(here + vec2<i32>(x, y), vec2<i32>(0), dims - vec2<i32>(1));
            let sample = rgb_to_ycocg(max(textureLoad(previous, coords, 0).rgb, vec3<f32>(0.0)));
            m1 += sample;
            m2 += sample * sample;
        }
    }
    let inv = 1.0 / 9.0;
    let mean = m1 * inv;
    let sigma = sqrt(max(m2 * inv - mean * mean, vec3<f32>(0.0))) * 1.0;

    // Bring last frame's colour back inside that box, moving toward its centre rather than clamping
    // each channel separately (which would drag colour toward the box's corner).
    let hist_ycocg = rgb_to_ycocg(max(history_catmull_rom(prev_uv), vec3<f32>(0.0)));
    let clipped = ycocg_to_rgb(clip_toward_centre(hist_ycocg, mean, sigma));
    let history = max(clipped, vec3<f32>(0.0));

    // Trust the history less when the pixel travelled far this frame, and when the surface at the
    // reprojected point is at a very different depth (something moved in front of it).
    let motion = length((prev_uv - input.uv) * frame.resolution);
    let movement = smoothstep(2.0, 12.0, motion);
    let depth_here = input.depth;
    let depth_prev = depth_at(prev_uv);
    let depth_scale = max(max(depth_here, depth_prev), 0.0001);
    let depth_gap = abs(depth_here - depth_prev) / depth_scale;
    let disocclusion = smoothstep(0.02, 0.2, depth_gap);
    let weight = mix(0.9, 0.6, clamp(max(movement, disocclusion), 0.0, 1.0));

    // Blend in tone-mapped space so a bright firefly in either frame cannot swamp the result, then
    // recover the linear colour. Nothing is allowed to come out negative.
    let current = max(input.color.rgb, vec3<f32>(0.0));
    let mixed = mix(tonemap(current), tonemap(history), weight);
    return vec4<f32>(max(untone(mixed), vec3<f32>(0.0)), input.color.a);
}
