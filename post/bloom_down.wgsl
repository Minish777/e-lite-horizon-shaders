// Keeps only the brightest parts of the picture, at half size. Over the sky only the sun and
// moon pass, so the sun gets a glow that follows the disc the game actually drew. A setting sun is
// orange and no longer near white, so close to the sun or moon on the screen the sky passes by its
// brightest channel instead, and the glow carries on until the disc is gone.
override bloom_amount: f32 = 0.5;

// Where the sun (or, once it has set, the moon) is on the screen, and whether it is in front.
fn body_uv() -> vec3<f32> {
    let body = select(frame.moon_direction, frame.sun_direction, frame.sun_direction.y > -0.08);
    let clip = frame.projection * (frame.view * vec4<f32>(normalize(body), 0.0));
    let w = select(1.0, clip.w, clip.w > 0.0);
    return vec3<f32>(clip.x / w * 0.5 + 0.5, 0.5 - clip.y / w * 0.5, select(0.0, 1.0, clip.w > 0.0));
}

fn bright(uv: vec2<f32>, body: vec3<f32>) -> vec4<f32> {
    let c = textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
    let lum = luminance(c);
    let depth = depth_at(uv);
    // Over the sky only the sun and moon glow, near where they are on the screen: the pale sky at
    // the horizon is nearly as bright, and letting it through smeared the skyline into the bloom
    // and the lens streak, as ghost copies of hills and trees.
    var keep = smoothstep(0.96, 1.0, lum);
    if depth > 0.0 {
        // On land only light sources glow (lava, glowstone, torches, lanterns): the material stage
        // marks them. Sunlit snow or sand is bright but not a light, and glowing it smears a halo
        // over and past its edges. Entities and water aren't marked, so they never glow.
        let surface = surface_at(vec2<i32>(uv * frame.resolution));
        let light_source = surface.present && surface.data > 1.5;
        // Where the terrain doesn't show (water, glass, entities), only the very brightest glow:
        // the sun's glints on water, which look like flat white specks without it.
        let glint = !surface.present && lum > 0.97;
        keep = smoothstep(0.6, 1.0, lum) * select(0.0, 1.0, light_source || glint)
            * (1.0 - smoothstep(60.0, 140.0, length(view_position(uv, depth))));
    } else {
        let aspect = vec2<f32>(frame.resolution.x / frame.resolution.y, 1.0);
        let near_body = (1.0 - smoothstep(0.02, 0.07, length((uv - body.xy) * aspect))) * body.z;
        let peak = max(c.r, max(c.g, c.b));
        keep = smoothstep(0.8, 0.98, peak) * near_body;
    }
    // Alpha: the same, but only over the sky. The wide sun glow is built from it, so it grows from
    // the sun and moon alone, never from bright ground.
    let kept = c * keep;
    return vec4<f32>(kept, select(0.0, luminance(kept), depth <= 0.0));
}

fn post(input: PostInput) -> vec4<f32> {
    if bloom_amount <= 0.0 {
        return vec4<f32>(0.0);
    }
    let body = body_uv();
    let texel = 1.5 / frame.resolution;
    var sum = bright(input.uv, body) * 0.25;
    for (var i = 0; i < 8; i++) {
        let angle = f32(i) * 0.7853982;
        sum += bright(input.uv + vec2<f32>(cos(angle), sin(angle)) * texel, body) * 0.09375;
    }
    return sum;
}
