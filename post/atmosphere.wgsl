// Ambient occlusion first, then the air: both in one pass, so the picture is read and written once.
//
// The air itself: aerial perspective that thickens toward a far horizon in rain and around sunrise,
// golden in-scattering toward a low sun, a little ground mist at dawn, and a thin coloured haze in
// the Nether and the End. It runs right after ambient occlusion, on the LDR picture vanilla has
// already fogged, and leaves the sky, everything within about 24 blocks, and the view while blind
// or under the Darkness effect alone. Kept cheap: a handful of exp() calls and no texture reads.
override fog_amount: f32 = 1.0;
override ao_strength: f32 = 0.6;
override morning_mist: bool = true;
override water_clarity: f32 = 1.0;
override debug_view: u32 = 0u;
override fog_adjust: f32 = 1.0;

// A cheap hash in 0..1 for the mist's value noise.
fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// Smooth value noise on a grid: four hashed corners, eased between them. Only the dawn mist uses it.
fn value_noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Henyey-Greenstein scattering: how much light a particle throws toward the eye, from the cosine
// between the view ray and the sun. `g` near 1 gives a tight glow around the sun.
fn phase_hg(cos_angle: f32, g: f32) -> f32 {
    let g2 = g * g;
    let denom = max(1.0 + g2 - 2.0 * g * cos_angle, 0.0001);
    return (1.0 - g2) / (12.566371 * pow(denom, 1.5));
}

// The optical path through an exponential height fog, from world height `y0` along a ray that rises
// `dy` over `path` blocks. The fog is densest at y = 62 and thins by e every 40 blocks of height.
// Integrating exp(-(y - 62) / 40) along the ray has this closed form; a near-horizontal ray (dy near
// zero) falls back to the plain path length, so nothing ever divides by zero.
fn height_path(y0: f32, dy: f32, path: f32) -> f32 {
    let base = 62.0;
    let scale = 40.0;
    // The camera's own density, kept sane far above or below the fog's base.
    let start = exp(-clamp((y0 - base) / scale, -1.5, 6.0));
    let x = dy / scale;
    let flat = abs(x) < 0.0001;
    let x_safe = select(x, 1.0, flat);
    let shape = select((1.0 - exp(-x_safe)) / x_safe, 1.0, flat);
    return path * start * shape;
}

// Underwater, the game's fog drowns everything in one flat blue a few blocks out. Its fog is linear
// from `fog_start` to `fog_end`, so most of it can be taken back out, and water put in its place
// that absorbs red first and scatters a clear teal, the way it does. What is near keeps its own
// colours; the far water turns deep teal, not saturated blue.
fn underwater(input: PostInput) -> vec3<f32> {
    let c = input.color.rgb;
    let sky_pixel = input.depth <= 0.0;
    let distance = select(length(view_position(input.uv, input.depth)), 64.0, sky_pixel);
    let fogged = clamp((distance - frame.fog_start) / max(frame.fog_end - frame.fog_start, 0.001), 0.0, 0.8);
    let clear = max((c - frame.fog_color * fogged) / (1.0 - fogged), vec3<f32>(0.0));
    let light = max(frame.eye_light_smooth.y, 0.25 * frame.eye_light_smooth.x) * (0.25 + 0.75 * daylight());
    let scatter = vec3<f32>(0.06, 0.26, 0.28) * light + vec3<f32>(0.01, 0.02, 0.03);
    let through = exp(-vec3<f32>(0.11, 0.04, 0.035) / max(water_clarity, 0.1) * distance);
    var water = clear * through + scatter * (1.0 - through);
    // Looking up at the surface keeps the game's own light-from-above look, just tinted teal.
    water = select(water, mix(c, grade_saturation(c, 0.7) * vec3<f32>(0.85, 1.05, 1.0), 0.5), sky_pixel);
    return water;
}

// One pixel of the picture: mix it toward the colour of the air along its view ray, by the share of
// that ray's light the air scatters away. Sky pixels (depth 0) are left exactly as drawn.
fn atmosphere(input: PostInput) -> vec4<f32> {
    if frame.in_water > 0.01 {
        let water = mix(input.color.rgb, underwater(input), frame.in_water);
        return vec4<f32>(clamp(water, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
    }
    if fog_amount <= 0.0 || input.depth <= 0.0 {
        return input.color;
    }
    // Water and lava own the picture's colour themselves, as do blindness and Darkness.
    if max(frame.in_water, frame.in_lava) > 0.5 {
        return input.color;
    }
    if max(frame.blindness, frame.darkness) > 0.01 {
        return input.color;
    }

    let here = view_position(input.uv, input.depth);
    let distance = length(here);
    // Nothing within about 24 blocks is touched; the haze fades in over the next stretch.
    let near_fade = smoothstep(24.0, 64.0, distance);
    if near_fade <= 0.0 {
        return input.color;
    }
    // Underground and indoors the sky light is low, so there is no aerial perspective to add.
    let inside = smoothstep(0.2, 0.7, frame.eye_light_smooth.y);
    if inside <= 0.0 {
        return input.color;
    }

    let render_distance = max(frame.render_distance, 1.0);
    let along = distance / render_distance;
    // At most 45% coverage in clear weather, a little more in rain. A hard cap keeps the picture
    // readable even on crowded settings or a low camera.
    let max_opacity = 0.45 + 0.15 * clamp(frame.wetness, 0.0, 1.0);

    if frame.dimension == -1 {
        // The Nether: a thin reddish haze built from vanilla's own fog colour.
        let haze = mix(frame.fog_color, vec3<f32>(0.55, 0.16, 0.10), 0.3);
        let tau = 0.30 * along * inside * clamp(fog_amount, 0.0, 2.0);
        let opacity = min(1.0 - exp(-tau), 0.35);
        let color = mix(input.color.rgb, haze, opacity);
        return vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
    }
    if frame.dimension == 1 {
        // The End: barely there, a faint purple wash.
        let haze = mix(frame.fog_color, vec3<f32>(0.52, 0.38, 0.72), 0.45);
        let tau = 0.16 * along * inside * clamp(fog_amount, 0.0, 2.0);
        let opacity = min(1.0 - exp(-tau), 0.20);
        let color = mix(input.color.rgb, haze, opacity);
        return vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
    }
    if frame.dimension != 0 {
        return input.color;
    }

    // Overworld: the air the ray crossed, in density units, then the extinction.
    let path = height_path(frame.camera_position.y, here.y, distance);
    let day = daylight();
    // Denser around sunrise and sunset and in rain; at altitude height_path does the thinning.
    let thickness = 1.0 + 0.9 * sun_low() + 0.8 * clamp(frame.wetness, 0.0, 1.0);
    let tau = 0.38 * (path / render_distance) * thickness * near_fade * inside * fog_amount * fog_adjust * profile_scale();
    let opacity = min(1.0 - exp(-max(tau, 0.0)), max_opacity);

    // By day the haze is vanilla's fog and sky colours. Toward a low sun it glows warm orange; at
    // noon it is pale white. At night the same colour, drained of saturation and left dim.
    let day_base = mix(frame.fog_color, frame.sky_color, 0.45);
    let to_point = here / max(distance, 0.001);
    let cos_angle = dot(to_point, normalize(frame.sun_direction));
    let sun_tint = mix(vec3<f32>(0.95, 0.97, 1.0), vec3<f32>(1.0, 0.52, 0.22), sun_low());
    let scatter = sun_tint * phase_hg(cos_angle, 0.7) * (0.30 + 0.90 * sun_low()) * day
        * (1.0 - 0.6 * frame.wetness);
    let day_haze = day_base + scatter;
    let night_haze = grade_saturation(mix(frame.fog_color, frame.sky_color, 0.5), 0.25)
        * vec3<f32>(0.55, 0.72, 1.0) * 0.25;
    let haze = mix(night_haze, day_haze, smoothstep(0.0, 0.6, day));

    var color = mix(input.color.rgb, haze, opacity);

    // Dawn ground mist: a thin fog lying on the land below about y = 70, only near the camera's own
    // altitude, broken up by slowly drifting value noise. Subtle enough to walk through.
    if morning_mist {
        let dawn = 1.0 - smoothstep(0.07, 0.11, min(frame.day_time, 1.0 - frame.day_time));
        let world = here + frame.camera_position;
        let low = 1.0 - smoothstep(58.0, 70.0, world.y);
        let nearby = 1.0 - smoothstep(8.0, 28.0, abs(world.y - frame.camera_position.y));
        let drift = value_noise(world.xz * 0.06 + vec2<f32>(frame.time * 0.015, frame.time * 0.008)) * 0.65
            + value_noise(world.xz * 0.15 - vec2<f32>(frame.time * 0.010, frame.time * 0.022)) * 0.35;
        let mist_near = smoothstep(24.0, 56.0, distance);
        let mist = dawn * inside * low * nearby * mist_near
            * (0.04 + 0.09 * drift) * clamp(fog_amount, 0.0, 1.0);
        // Spend only what the haze left of the weather's opacity budget.
        let budget = max(max_opacity - opacity, 0.0);
        let mist_opacity = min(mist, budget);
        let mist_color = mix(frame.fog_color, vec3<f32>(1.0, 0.84, 0.68), 0.4 * sun_low());
        color = mix(color, mist_color, mist_opacity);
    }

    return vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}


// Screen-space ambient occlusion that knows which way the surface faces: eight taps on a ring,
// rotated per pixel, each counting only as far as it rises above the surface (the angle between
// the surface's normal, stored by the material stage, and the direction to the tap). Flat ground
// seen at a grazing angle has nearer ground below it on the screen, and an occlusion that only
// compared distances darkened all of it a little, except along the edges of blocks, where taps
// landed on farther terrain: every edge got a pale ghost of a band, wider the farther away it
// was. Taps in the surface's own plane now add nothing. Returns how much light is left, 0..1.
fn ambient_occlusion(input: PostInput) -> f32 {
    if ao_strength <= 0.0 || input.depth == 0.0 {
        return 1.0;
    }
    let here = view_position(input.uv, input.depth);
    let distance = length(here);
    // Far things (and the clouds) get none: it would only dither them.
    let near = 1.0 - smoothstep(40.0, 90.0, distance);
    if near <= 0.0 {
        return 1.0;
    }
    // Only the solid terrain stores a normal; entities, water and glass keep their own shading.
    let surface = surface_at(vec2<i32>(input.pixel));
    if !surface.present {
        return 1.0;
    }
    // Leaves are full of holes that show a surface a block behind: to this pass every one looks
    // like a deep crease, and the canopy would turn speckled black. They keep only a little.
    let leafy = surface.data > 0.5 && surface.data < 1.5;
    let strength = ao_strength * profile_scale() * select(1.0, 0.15, leafy);
    let normal = surface.normal;
    let noise = ign(input.pixel);
    let aspect = vec2<f32>(frame.resolution.y / frame.resolution.x, 1.0);
    let radius = clamp(1.4 / distance, 0.004, 0.035);

    var occlusion = 0.0;
    for (var i = 0; i < 8; i++) {
        let angle = (f32(i) + noise) * 0.7853982;
        let reach = radius * select(0.55, 1.0, (i & 1) == 1);
        let uv = input.uv + vec2<f32>(cos(angle), sin(angle)) * reach * aspect;
        let depth = depth_at(uv);
        if depth > 0.0 {
            let to_tap = view_position(uv, depth) - here;
            let gap = length(to_tap);
            // How far above the surface the tap rises (0 in its plane), fading out past a block
            // and a half so a wall far behind doesn't shade the ground in front of it.
            let rise = max(dot(normal, to_tap / max(gap, 0.0001)) - 0.15, 0.0);
            occlusion += rise * (1.0 - smoothstep(0.8, 1.6, gap));
        }
    }
    return clamp(1.0 - (occlusion / 8.0) * strength * 2.0 * near, 0.0, 1.0);
}
// The air above lava shimmers: pixels with lava a little below them on the screen (the material
// stage marks it) read the picture from a slightly wavering place.
fn heat_shimmer(input: PostInput) -> vec3<f32> {
    let pixel = vec2<i32>(input.pixel);
    let below = surface_at(pixel + vec2<i32>(0, 10));
    let here = surface_at(pixel);
    let hot = (below.present && abs(below.data - 2.0) < 0.5) || (here.present && abs(here.data - 2.0) < 0.5);
    if !hot {
        return input.color.rgb;
    }
    let t = frame.time * 3.0;
    let wobble = vec2<f32>(sin(input.uv.y * 140.0 + t) * 1.5, sin(input.uv.x * 90.0 + t * 1.3) * 1.0)
        / frame.resolution;
    return textureSampleLevel(previous, linear_sampler, input.uv + wobble, 0.0).rgb;
}

fn post(input: PostInput) -> vec4<f32> {
    // The Shadows and No post effects debug views skip this pass.
    if debug_view >= 2u {
        return input.color;
    }
    var shaded = input;
    shaded.color = vec4<f32>(heat_shimmer(input) * ambient_occlusion(input), input.color.a);
    return atmosphere(shaded);
}