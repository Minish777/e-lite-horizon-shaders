// Lighting for terrain: a warm sun (or cool moon) with shadow-mapped shadows, a blue sky fill,
// coloured block light, and water that refracts, reflects and absorbs. Output stays within 0..1
// so the post passes work on a stable picture.
override shadow_strength: f32 = 0.85;
override shadow_softness: f32 = 0.5;
override ambient_level: f32 = 1.0;
override wave_strength: f32 = 1.0;
override water_clarity: f32 = 1.0;
override reflections: bool = true;
override debug_view: u32 = 0u;
override rain_puddles: f32 = 1.0;
override torch_flicker: f32 = 1.0;
override night_bright: f32 = 1.0;
override water_absorption: f32 = 1.0;
override caustics_intensity: f32 = 1.0;
override blocklight_warmth: f32 = 1.0;
override emissive_strength: f32 = 1.0;
override avoid_dark: f32 = 0.04;
override refraction: bool = true;

// The light's colour after the glass and water between a shadow-map point and the sun, and in w
// how much of it is water (so the sea floor can show caustics).
fn translucent_tint(p: vec3<f32>, bias: f32) -> vec4<f32> {
    let open = textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, p.xy, p.z - bias);
    let dims = vec2<f32>(textureDimensions(shadow_color));
    let texel = vec2<i32>(clamp(p.xy, vec2<f32>(0.0), vec2<f32>(0.9999)) * dims);
    let sample = textureLoad(shadow_color, texel, 0);
    let tint = min(sample.rgb * 1.3, vec3<f32>(1.0));
    return vec4<f32>(mix(tint, vec3<f32>(1.0), open), (1.0 - open) * step(0.999, sample.a));
}

// 1 where the sun reaches, 0 in shadow, tinted by glass and water in its way (xyz); in w, how much
// water the light crosses. The point is pushed off the surface by a few shadow texels (more at a
// grazing angle) and the depth bias is in blocks, so shadows meet what casts them. Sixteen taps on
// a disk, each a 2x2 hardware filter, blur the map's texels into an edge about two texels wide.
// A shadow stays that sharp at its base and widens only with its distance from what casts it.
// Far shadows fade out before the map's edge, where the
// map re-centring every few blocks would make them visibly jump.
fn sun_light(position: vec3<f32>, normal: vec3<f32>, facing: f32, noise: f32, tinted: bool, soft: f32) -> vec4<f32> {
    let probe = shadow_position(position);
    let texel = shadow_texel_at(probe.xy);
    let p = shadow_position(position + normal * texel * (1.0 + 2.0 * (1.0 - facing)));
    let bias = (texel * 0.75 + 0.01) / shadow_range();
    let res = max(frame.shadow_resolution, 1.0);
    let away = length(position.xz);

    // A tap a few texels to the side reads the map where the surface itself is nearer or farther
    // from the light, by its slope toward the light: without allowing for that, a lit floor shadows
    // itself in blocky patches. So each tap's bias grows with how far out it reads. Only half the
    // slope, and at most a steep one: allowing it all at a low sun lifted the bias of the outer
    // taps past a block, so a shadow came loose from the block casting it, leaving a lit seam.
    let slope = min(sqrt(max(1.0 - facing * facing, 0.0)) / max(facing, 0.15), 2.0) * 0.5;
    let per_texel = texel * slope / shadow_range();

    // Blocker search: how far in front of this point the shadow map's occluders are. It reaches past
    // the widest filter below, so no edge it could blur is ever missed: a missed thin leaf edge was
    // what left hard, jagged steps.
    let search_texels = 9.0;
    var blockers = 0.0;
    var blocker_depth = 0.0;
    for (var i = 0; i < 12; i++) {
        let reach = sqrt(f32(i) / 11.0);
        let angle = f32(i) * 2.3999632;
        let uv = clamp(p.xy + vec2<f32>(cos(angle), sin(angle)) * reach * search_texels / res, vec2<f32>(0.0), vec2<f32>(0.9999));
        let depth = textureLoad(shadow_map, vec2<i32>(uv * res), 0);
        let hit = select(0.0, 1.0, depth < p.z - bias - per_texel * reach * search_texels);
        blockers += hit;
        blocker_depth += depth * hit;
    }

    // Nothing in reach: fully lit, no filtering needed (most of a sunny screen).
    var sunlit = 1.0;
    if blockers > 0.5 {
        let gap = max(p.z - blocker_depth / max(blockers, 1.0), 0.0) * shadow_range();
        // A real sun is half a degree wide: a shadow's edge grows by about a hundredth of the gap.
        // Kept small, so the pixel-sized holes in leaves stay as sharp dapples, not blobs.
        let widen = mix(0.002, 0.012, shadow_softness);
        let radius_texels = clamp(gap * widen / texel, mix(1.5, 5.0, soft), 8.0);
        // Only a wide, soft edge is turned (by a value fixed to the block's texels, so it holds still
        // as the camera moves), to hide banding; a narrow one keeps the fixed pattern, which is smooth.
        let spin = noise * 6.2831853 * smoothstep(2.5, 4.5, radius_texels);
        var sum = 0.0;
        for (var i = 0; i < 16; i++) {
            let reach = sqrt((f32(i) + 0.5) / 16.0);
            let angle = f32(i) * 2.3999632 + spin;
            let offset = vec2<f32>(cos(angle), sin(angle)) * reach * radius_texels / res;
            let tap_bias = bias + per_texel * reach * radius_texels;
            sum += textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy + offset, p.z - tap_bias);
        }
        sunlit = sum / 16.0;
    }
    let inside = all(p.xy > vec2<f32>(0.0)) && all(p.xy < vec2<f32>(1.0)) && p.z < 1.0;
    let fade = 1.0 - smoothstep(0.65 * frame.shadow_distance, 0.9 * frame.shadow_distance, away);
    let visible = mix(0.8, select(1.0, sunlit, inside), fade);
    let tint = select(vec4<f32>(1.0, 1.0, 1.0, 0.0), translucent_tint(p, bias), tinted && inside);
    return vec4<f32>(visible * tint.rgb, tint.w);
}

// A 0..1 value per integer cell of the world's xz plane, exact however far out.
fn cell_hash(i: vec2<f32>) -> f32 {
    return hash3(vec3<u32>(bitcast<u32>(i32(i.x)), bitcast<u32>(i32(i.y)), 7u));
}

// Smooth value noise in 0..1, for where puddles gather.
fn value_noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = cell_hash(i);
    let b = cell_hash(i + vec2<f32>(1.0, 0.0));
    let c = cell_hash(i + vec2<f32>(0.0, 1.0));
    let d = cell_hash(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// The slope of smooth value noise at `p`, worked out exactly (not by finite differences), roughly
// -1..1 per axis: an irregular surface for small ripples.
fn noise_gradient(p: vec2<f32>) -> vec2<f32> {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let du = 6.0 * f * (1.0 - f);
    let a = cell_hash(i);
    let b = cell_hash(i + vec2<f32>(1.0, 0.0));
    let c = cell_hash(i + vec2<f32>(0.0, 1.0));
    let d = cell_hash(i + vec2<f32>(1.0, 1.0));
    return du * vec2<f32>((b - a) + (a - b - c + d) * u.y, (c - a) + (a - b - c + d) * u.x);
}
// Bright, shifting web lines like light through a rippling surface: two layers at different scales.
fn caustic_pattern(p: vec2<f32>) -> f32 {
    let t = frame.time * 0.7;
    let a = sin(p.x * 1.7 + sin(p.y * 1.1 + t) * 1.3 + t) + sin(p.y * 1.9 - t * 1.1 + sin(p.x * 0.9) * 1.2)
        + sin((p.x + p.y) * 1.3 + t * 0.7);
    let b = sin(p.x * 3.1 - t * 1.3 + sin(p.y * 2.3 - t)) + sin(p.y * 3.4 + t + sin(p.x * 1.7 + t * 0.6))
        + sin((p.x - p.y) * 2.6 - t * 0.9);
    return pow(max(1.0 - abs(a) * 0.45, 0.0), 3.0) * 0.6 + pow(max(1.0 - abs(b) * 0.45, 0.0), 3.0) * 0.4;
}

// The slope of the water's surface at a world position, d(height)/d(x, z): four layers of smooth
// noise, each finer one smaller and drifting its own way, the way wind roughens water. Noise has no
// direction or period, so there are no stripes or bands. `detail` (0..1) fades the fine layers
// out with distance, where they would only shimmer.
fn wave_gradient(p: vec2<f32>, detail: f32) -> vec2<f32> {
    let t = frame.time;
    var g = noise_gradient(p * 0.22 + vec2<f32>(t * 0.05, t * 0.03)) * 0.22 * 0.05;
    g += noise_gradient(p * 0.55 + vec2<f32>(-t * 0.09, t * 0.07) + vec2<f32>(17.3, 5.1)) * 0.55 * 0.028;
    g += noise_gradient(p * 1.3 + vec2<f32>(t * 0.16, -t * 0.12) + vec2<f32>(3.7, 29.9)) * 1.3 * 0.011 * detail;
    g += noise_gradient(p * 3.1 + vec2<f32>(-t * 0.25, -t * 0.3) + vec2<f32>(41.2, 11.6)) * 3.1 * 0.004 * detail;
    return g;
}
// How far from the camera the opaque world is at a pixel, in blocks; far where there is only sky.
fn scene_distance(pixel: vec2<i32>) -> f32 {
    let depth = textureLoad(opaque_depth, pixel, 0);
    if depth <= 0.0 {
        return 10000.0;
    }
    let uv = (vec2<f32>(pixel) + 0.5) / frame.resolution;
    let v = frame.projection_inverse * vec4<f32>(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    return length(v.xyz / v.w);
}

// What a ray leaving the water in `dir` sees of the sky: the same deep zenith and pale horizon the
// sky stage draws, so a lake mirrors the sky above it.
fn sky_reflection(dir: vec3<f32>) -> vec3<f32> {
    let up = smoothstep(0.0, 0.55, dir.y);
    let horizon = mix(mix(frame.fog_color, frame.sky_color, 0.35), vec3<f32>(0.86, 0.90, 0.97), 0.3 * daylight());
    let zenith = grade_saturation(frame.sky_color * vec3<f32>(0.55, 0.78, 1.1), 1.2);
    return mix(horizon, zenith, up);
}

// Whether the sun, along `dir`, is in sight from the camera-relative point `p`: steps reaching from
// 1.5 to about 200 blocks out are checked against the opaque world's depth on the screen. A step
// that lands behind something drawn there, within 48 blocks of it (a hill, not a thin edge far in
// front), is blocked. Where the march leaves the screen before it can tell, the shadow map takes
// over from the last point it checked: whether anything between there and the sun casts a shadow.
fn sun_path_open(p: vec3<f32>, dir: vec3<f32>) -> f32 {
    let top = vec2<f32>(frame.resolution) - vec2<f32>(1.0);
    var t = 1.5;
    var last = p;
    var left_screen = false;
    var saw_sky = false;
    for (var i = 0; i < 16; i++) {
        let q = p + dir * t;
        t *= 1.38;
        let clip = frame.projection * (frame.view * vec4<f32>(q, 1.0));
        let w = select(1.0, clip.w, clip.w > 0.0);
        let uv = vec2<f32>(clip.x / w * 0.5 + 0.5, 0.5 - clip.y / w * 0.5);
        if clip.w <= 0.0 || any(uv < vec2<f32>(0.0)) || any(uv > vec2<f32>(1.0)) {
            left_screen = true;
            break;
        }
        let scene = scene_distance(vec2<i32>(clamp(uv * frame.resolution, vec2<f32>(0.0), top)));
        let ray = length(q);
        if scene < ray - 0.5 && scene > ray - 48.0 {
            return 0.0;
        }
        saw_sky = saw_sky || scene > 9999.0;
        last = q;
    }
    if !left_screen || saw_sky {
        return 1.0;
    }
    let s = shadow_position(last);
    let inside = all(s.xy > vec2<f32>(0.0)) && all(s.xy < vec2<f32>(1.0)) && s.z < 1.0;
    let bias = (shadow_texel_at(s.xy) * 2.0 + 0.05) / shadow_range();
    let open = textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy, s.z - bias);
    // The shadows' own light must be the sun for this to say anything about it. When nothing can
    // tell (no sky crossed on the screen, no shadow map of the sun), a low sun's path is taken as
    // hidden: the jagged strip of a guessed `open` along a hill's outline looks far worse.
    let by_sun = dot(frame.light_direction, dir) > 0.9 && frame.has_shadow != 0u;
    return select(select(0.0, 1.0, by_sun), open, inside && by_sun);
}
// Raindrops on still water: in each cell of a grid, a ring spreads out from a random point and
// fades, each cell on its own clock; two offset grids so rings overlap. Returns the slope they
// give the surface, like wave_gradient.
fn rain_ripples(p: vec2<f32>) -> vec2<f32> {
    var g = vec2<f32>(0.0);
    for (var layer = 0; layer < 2; layer++) {
        let q = p * 1.3 + vec2<f32>(f32(layer) * 0.5, f32(layer) * 0.37);
        let cell = floor(q);
        let key = vec3<u32>(bitcast<u32>(i32(cell.x)), bitcast<u32>(i32(cell.y)), u32(layer) + 11u);
        let centre = cell + vec2<f32>(0.2, 0.2) + vec2<f32>(hash3(key), hash3(key + vec3<u32>(5u, 9u, 0u))) * 0.6;
        let age = fract(frame.time * 0.9 + hash3(key + vec3<u32>(17u, 3u, 0u)));
        let offset = q - centre;
        let d = length(offset);
        let ring = d - age * 0.5;
        let wave = sin(ring * 40.0) * exp(-ring * ring * 300.0) * (1.0 - age) * (1.0 - age);
        g += offset / max(d, 0.001) * wave * 0.25;
    }
    return g;
}

// Schlick's Fresnel for water (2% straight on, all at a grazing angle).
fn fresnel_at(cos_angle: f32) -> f32 {
    return 0.02 + 0.98 * pow(1.0 - clamp(cos_angle, 0.0, 1.0), 5.0);
}

// The surface of water seen from above: what lies behind it, bent by the waves and tinted the way
// water absorbs light (red first), the sky and the shore mirrored in it more at a low angle, the
// sun's path across it, and foam where it is shallow.
fn water_colour(input: MaterialInput, albedo: vec3<f32>, lit: vec3<f32>, light_colour: vec3<f32>,
                to_light: vec3<f32>, visible: f32) -> vec3<f32> {
    let world = input.position + frame.camera_position;
    let distance_fade = 1.0 - smoothstep(48.0, 160.0, length(input.position));
    let detail = 1.0 - smoothstep(12.0, 48.0, length(input.position));
    let g = (wave_gradient(world.xz, detail) * (1.0 + frame.rain * 1.5)
        + rain_ripples(world.xz) * frame.rain * smoothstep(0.8, 0.95, input.light.y) * detail) * wave_strength * distance_fade;
    let n = normalize(vec3<f32>(-g.x, 1.0, -g.y));
    let view = normalize(-input.position);
    let fresnel = 0.04 + 0.96 * pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 5.0);

    let top = vec2<f32>(frame.resolution) - vec2<f32>(1.0);
    let here = vec2<i32>(clamp(input.screen * frame.resolution, vec2<f32>(0.0), top));
    let own = length(input.position);
    let thickness_here = max(scene_distance(here) - own, 0.0);

    // Refraction: look through the bent surface, but never at something in front of the water.
    let bend = vec2<f32>(g.x, g.y) * 24.0 * clamp(thickness_here, 0.0, 2.0) * wave_strength * select(0.0, 1.0, refraction);
    let there = vec2<i32>(clamp(vec2<f32>(here) + bend, vec2<f32>(0.0), top));
    let in_front = scene_distance(there) < own - 0.05;
    let sample_at = select(there, here, in_front);
    let thickness = max(scene_distance(sample_at) - own, 0.0);
    let behind = textureLoad(opaque_color, sample_at, 0).rgb;

    let absorb = vec3<f32>(0.30, 0.10, 0.08) * water_absorption / max(water_clarity, 0.1);
    let through = exp(-absorb * min(thickness, 40.0));
    // The light the water itself scatters back: a muted green-teal, darker where it is deep. Shallow
    // water mostly shows its bed through it, so this matters only where it is a few blocks deep.
    let shallow_tint = vec3<f32>(0.07, 0.20, 0.19);
    let deep_tint = vec3<f32>(0.025, 0.085, 0.10);
    let body = mix(shallow_tint, deep_tint, smoothstep(2.0, 16.0, thickness));
    let scatter = mix(body, albedo * 0.35, 0.3) * min(lit * 1.4, vec3<f32>(1.0));
    var refracted = behind * through + scatter * (1.0 - through);
    // Light through the crest of a wave toward a low sun: a green-teal glow on the far side of the
    // swell, as in the sea at sunset.
    let crest = clamp(dot(vec2<f32>(g.x, g.y), -to_light.xz) * 12.0, 0.0, 1.0);
    let backlit = pow(clamp(dot(view, -to_light), 0.0, 1.0), 3.0);
    refracted += vec3<f32>(0.08, 0.45, 0.35) * light_colour * crest * backlit * visible * 0.3 * daylight();

    // Reflection: the mirrored world where Horizon draws it, else the sky.
    let mirror_uv = clamp(input.screen + vec2<f32>(g.x, -g.y) * 0.05, vec2<f32>(0.0), vec2<f32>(1.0));
    let mirrored = textureSampleLevel(reflection, reflection_sampler, mirror_uv, 0.0).rgb;
    let toward = reflect(-view, n);
    let reflected = select(sky_reflection(toward), mirrored, reflections && frame.has_reflection != 0u);

    // Water is a mirror, but straight down a mirror of 2% looks like dull glass in a game: a little
    // more of the sky and shore stays in it at every angle, as on a real lake under a bright sky.
    var colour = mix(refracted, reflected, clamp(fresnel * 0.9 + 0.1, 0.0, 1.0));

    // The sun's path: a glossy highlight from the surface as the waves tilt it (a microfacet lobe,
    // bright in the middle with soft shoulders), and glitter: a much finer, faster ripple seen by the
    // highlight alone, so the path sparkles without the picture beneath it shimmering.
    let half_vector = normalize(view + to_light);
    let world_xz = (input.position + frame.camera_position).xz;
    let fine = noise_gradient(world_xz * 7.0 + vec2<f32>(frame.time * 1.1, -frame.time * 0.8))
        + noise_gradient(world_xz * 13.0 - vec2<f32>(frame.time * 0.9, frame.time * 1.3));
    let sparkle_n = normalize(n + vec3<f32>(-fine.x, 0.0, -fine.y) * 0.035 * detail);
    let roughness = 0.07;
    let a2 = roughness * roughness;
    let nh = max(dot(n, half_vector), 0.0);
    let lobe = a2 / (3.14159 * pow(nh * nh * (a2 - 1.0) + 1.0, 2.0));
    let sheen = min(lobe * fresnel_at(max(dot(view, half_vector), 0.0)) * 0.6, 6.0);
    let glint = pow(max(dot(sparkle_n, half_vector), 0.0), 1500.0) * 18.0;
    colour += light_colour * (sheen + glint) * visible * (1.0 - frame.rain);

    let shore = (1.0 - smoothstep(0.0, 0.7, thickness)) * select(0.0, 1.0, thickness_here < 1000.0);
    // Foam: broken, drifting patches along the shore, from two layers of noise moving apart.
    let drift = frame.time * 0.35;
    let froth = value_noise(world.xz * 2.2 + vec2<f32>(drift, -drift * 0.6)) * 0.6
        + value_noise(world.xz * 5.3 - vec2<f32>(drift * 0.8, drift)) * 0.4;
    let foam = shore * smoothstep(0.55, 0.85, froth + shore * 0.25);
    colour = mix(colour, min(lit * 1.6 + vec3<f32>(0.18), vec3<f32>(1.0)), foam * 0.25 * wave_strength);

    return colour;
}

fn material(input: MaterialInput) -> Surface {
    let base = input.albedo * input.tint;
    let n = normalize(input.normal);
    let block_light = input.light.x;
    let sky_light = input.light.y;

    let overworld = frame.dimension == 0;
    let day = daylight();
    let wet = 1.0 - frame.rain * 0.6;
    let water = input.fluid == 1u && input.face == 1u && frame.in_water < 0.5;

    // Direct light: sun by day, a faint blue moon by night. Gated by sky light so caves stay dark.
    let to_light = normalize(select(frame.sun_direction, frame.light_direction, frame.has_shadow != 0u));
    // E-LITE LIGHT_DAY_COLOR (0.90, 0.84, 0.79) to LIGHT_SUNSET_COLOR (1.0, 0.59, 0.35).
    let sun_colour = mix(vec3<f32>(0.90, 0.84, 0.79), vec3<f32>(1.0, 0.59, 0.35), sun_low()) * 1.15;
    // E-LITE NIGHT_BRIGHT scales the moon and the night ambient.
    let moon_colour = vec3<f32>(0.30, 0.40, 0.75) * 0.22 * night_bright;
    let direct_colour = mix(moon_colour, sun_colour, day);
    let exposure = smoothstep(0.35, 0.95, sky_light);
    // Leaves let light through, so they are lit a little even facing away (wrapped lighting), and
    // their shadows are filtered wider and lifted: a leaf block's own holes would otherwise speckle
    // it with pixel-sized dots of shade at a low sun.
    let leaves = input.material == 1u;
    let facing = select(max(dot(n, to_light), 0.0), clamp(dot(n, to_light) * 0.6 + 0.4, 0.0, 1.0), leaves);
    // One value per texel of the block's 16x16 texture, nudged off the face so the face's own plane
    // never sits on a cell boundary.
    let texel_cell = vec3<i32>(floor((input.position + frame.camera_position - n * 0.01) * 16.0));
    let noise = hash3(bitcast<vec3<u32>>(texel_cell));
    // Leaves take one shade per block, read from just beyond the block toward the light with the
    // widest filter: a leaf face can't show the hole pattern of the leaves around it, which at a
    // low sun crawls across it as the sun moves. A block in deep canopy is shaded whole; one on the
    // sunny edge is lit whole, much as a real tree's foliage reads from a distance.
    let block_centre = floor(input.position + frame.camera_position - n * 0.01) + vec3<f32>(0.5) - frame.camera_position;
    let shade_at = select(input.position, block_centre + to_light * 1.0, leaves);
    let shade_normal = select(n, to_light, leaves);
    // A face turned away from the light gets none of it whatever the shadow map says, so it skips
    // the lookup: about half the faces on screen, and the most expensive part of this stage.
    var raw_sample = vec4<f32>(1.0, 1.0, 1.0, 0.0);
    if facing > 0.0 || water {
        raw_sample = sun_light(shade_at, shade_normal, select(facing, 1.0, leaves), noise, !water, select(0.0, 1.0, leaves));
    }
    let sun_sample = vec4<f32>(select(raw_sample.xyz, mix(raw_sample.xyz, vec3<f32>(1.0), 0.3), leaves), raw_sample.w);
    let sun = mix(vec3<f32>(1.0), sun_sample.xyz, shadow_strength);
    let shadowed = select(vec3<f32>(1.0), sun, frame.has_shadow != 0u);

    var out: Surface;
    if debug_view == 2u {
        out.color = vec4<f32>(shadowed * (0.3 + 0.7 * facing), 1.0);
        return out;
    }

    // Light on the sea floor ripples with the water's surface.
    let world = input.position + frame.camera_position;
    let caustics = 1.0 + caustic_pattern(world.xz) * sun_sample.w * 0.6 * caustics_intensity;
    let direct = direct_colour * facing * shadowed * caustics * exposure * wet * select(0.0, 1.0, overworld);

    // Ambient: blue sky light, stronger on upward faces; a flat tint in the Nether and End.
    let hemisphere = 0.55 + 0.45 * n.y;
    let sky_fill = mix(vec3<f32>(0.14, 0.18, 0.30), vec3<f32>(0.36, 0.46, 0.64), day);
    // Light that reaches under a canopy: a gentler curve than sky_light squared, plus a share of the
    // sun's own light bounced around, so shade is dim and coloured instead of black.
    let under = smoothstep(0.05, 0.7, sky_light);
    var ambient = (sky_fill * pow(sky_light, 1.4) + sun_colour * 0.09 * day * under) * hemisphere * wet;
    if frame.dimension == -1 {
        ambient = vec3<f32>(0.50, 0.26, 0.20) * hemisphere;
    } else if frame.dimension == 1 {
        ambient = vec3<f32>(0.32, 0.26, 0.46) * hemisphere;
    }
    // Warm light bounced up from the ground onto faces that look down.
    ambient += vec3<f32>(0.18, 0.14, 0.09) * max(-n.y, 0.0) * pow(sky_light, 2.0) * day;
    ambient = (ambient + vec3<f32>(0.05 + frame.night_vision * 0.35)) * ambient_level * mix(1.0, night_bright, 1.0 - day);

    if water {
        // The picture behind the water is already lit and shaped, so it skips the shoulder below.
        let lit = ambient + direct * 0.6;
        // The sun's path on the water follows the sun until it has set, even after the shadows
        // have turned to the moon; the reflection itself then says whether a hill hides it.
        let sun_up = smoothstep(-0.08, 0.02, frame.sun_direction.y);
        let by_sun = sun_up > 0.0;
        let shadows_from_moon = dot(frame.light_direction, frame.sun_direction) < 0.0 && frame.has_shadow != 0u;
        let glint_dir = select(to_light, normalize(frame.sun_direction), by_sun);
        let glint_colour = select(direct_colour, sun_colour * sun_up, by_sun) * exposure;
        // The reflected ray toward the sun is the same line as the shadow ray, so the sun is in the
        // water exactly where it lights the water: the shadow map says, read without the fade-out
        // the ground gets (it captures hills far along the sun's direction too). Past the map, or
        // once the shadows are the moon's, a march over the screen decides.
        let s = shadow_position(input.position + vec3<f32>(0.0, 0.05, 0.0));
        let in_map = all(s.xy > vec2<f32>(0.0)) && all(s.xy < vec2<f32>(1.0)) && s.z < 1.0;
        let s_bias = (shadow_texel_at(s.xy) + 0.02) / shadow_range();
        let sun_reaches = textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy, s.z - s_bias);
        let map_usable = in_map && frame.has_shadow != 0u && !shadows_from_moon;
        let glint_visible = select(select(shadowed.x, sun_path_open(input.position, glint_dir), by_sun),
            sun_reaches, by_sun && map_usable);
        out.color = vec4<f32>(water_colour(input, base.rgb, lit, glint_colour, glint_dir, glint_visible), 1.0);
        return out;
    }

    // Block light: warm by default, tinted by the nearest coloured sources. Fire breathes a little:
    // a slow, faint flicker that varies across the world, so nearby torches don't pulse together.
    let nearby = block_light_color(input.position);
    let strongest = max(max(nearby.r, nearby.g), max(nearby.b, 0.001));
    // E-LITE BLOCKLIGHT_TEMP: warm orange by default, cooler as warmth drops.
    let warm_tint = mix(vec3<f32>(0.80, 0.88, 1.0), vec3<f32>(1.0, 0.62, 0.30), clamp(blocklight_warmth, 0.0, 1.0));
    let tint = mix(warm_tint, nearby.rgb / strongest, step(0.001, nearby.a));
    let cell = floor(world * 0.25);
    let flicker = 1.0 + torch_flicker * 0.05 * (sin(frame.time * 7.3 + cell.x * 3.1 + cell.z * 1.7)
        * sin(frame.time * 3.1 + cell.y * 2.3));
    let blocks = tint * pow(block_light, 2.4) * 1.15 * flicker + input.colored_light;

    // Leaves seen against the sun let it through and glow, tinted by their own colour. Whether the
    // light reaches them is the block's one shade from above, so the glow has no speckle either.
    var through = vec3<f32>(0.0);
    if input.material == 1u {
        let to_eye = normalize(-input.position);
        let backlit = pow(max(-dot(to_eye, to_light), 0.0), 2.0);
        let open = raw_sample.x;
        let reaches = select(1.0, open, frame.has_shadow != 0u);
        through = base.rgb * base.rgb * direct_colour * (backlit * reaches * exposure * wet * 2.2)
            * select(0.0, 1.0, overworld);
    }

    // Rain soaks what is open to the sky. Wet stone, dirt and wood go darker and a little richer in
    // colour (water fills the pores, so less light scatters back), and every soaked surface carries
    // a thin film that mirrors the sky: strongly on the ground, faintly on walls. On flat ground,
    // puddles gather in patches that spread as the rain goes on, ringed by falling drops. It all
    // follows `wetness`, which rises over half a minute of rain and dries over a few seconds after.
    let view = normalize(-input.position);
    let soaked = frame.wetness * rain_puddles * smoothstep(0.8, 0.95, sky_light) * select(0.0, 1.0, overworld)
        * select(1.0, 0.0, input.translucent);
    let pooling = value_noise(world.xz * 0.18) * 0.7 + value_noise(world.xz * 0.9) * 0.3;
    let spread = mix(0.72, 0.45, frame.wetness);
    let patches = smoothstep(spread, spread + 0.12, pooling);
    let flat_top = smoothstep(0.9, 0.99, n.y) * select(1.0, 0.0, leaves);
    let puddle = soaked * patches * flat_top * (1.0 - smoothstep(32.0, 96.0, length(input.position)));
    let albedo_wet = mix(base.rgb, grade_saturation(base.rgb, 1.2) * 0.58, soaked * select(0.85, 0.4, leaves));

    var colour = albedo_wet * (direct + ambient + blocks) + base.rgb * input.emission * 1.6 * emissive_strength + through;
    // E-LITE AVOID_DARK_LEVEL: a soft floor so night and caves never go pure black.
    colour += vec3<f32>(0.55, 0.62, 0.75) * avoid_dark * (1.0 - colour) * 0.35;

    // LabPBR maps, when a resource pack ships them: the normal map bends the light across the face,
    // the specular map's smoothness sharpens the sun's highlight (metals tint it with their own
    // colour), and its emission makes parts of a texture glow. Without them nothing changes.
    var lit_normal = n;
    var smoothness = 0.0;
    var metal = false;
    if block_pbr_maps() && !leaves {
        let nm = block_normal_map(input.uv);
        let xy = nm.xy * 2.0 - 1.0;
        let z = sqrt(max(1.0 - dot(xy, xy), 0.0));
        let t = input.tangent.xyz;
        let b = cross(n, t) * input.tangent.w;
        lit_normal = normalize(t * xy.x + b * xy.y + n * z);
        let spec = block_specular_map(input.uv);
        smoothness = spec.r;
        metal = spec.g > 0.898;
        if spec.a < 0.999 {
            colour += base.rgb * spec.a * 2.0;
        }
        // The normal map's own ambient occlusion darkens its crevices.
        colour *= mix(1.0, nm.b, 0.6);
        // Light falls on the bent normal: re-weight the sun by how the bumps face it.
        let bent = max(dot(lit_normal, to_light), 0.0);
        colour += albedo_wet * direct_colour * (bent - facing) * shadowed * exposure * wet
            * select(0.0, 1.0, overworld && facing > 0.0);
    }

    // A soft highlight from the sun or moon on everything it lights, stronger on wet ground.
    let half_vector = normalize(view + to_light);
    let gloss = mix(mix(24.0, 400.0, smoothness * smoothness), 300.0, puddle);
    let shine = mix(0.04, select(0.5, 1.0, metal), smoothness * smoothness);
    let highlight = pow(max(dot(lit_normal, half_vector), 0.0), gloss) * mix(shine, 1.5, max(puddle, soaked * 0.15));
    let highlight_tint = select(vec3<f32>(1.0), base.rgb, metal);
    colour += direct_colour * highlight_tint * highlight * facing * shadowed * exposure * select(0.0, 1.0, overworld);
    if soaked > 0.0 {
        // Raindrop rings on the puddles bend what they mirror; the film elsewhere is too thin to.
        let rings = rain_ripples(world.xz) * frame.rain * puddle;
        let wet_n = normalize(n + vec3<f32>(-rings.x, 0.0, -rings.y));
        let toward = reflect(-view, wet_n);
        let fresnel = fresnel_at(max(dot(wet_n, view), 0.0));
        // Under a rain sky the reflection is the grey of the clouds; it dims with the day.
        let mirrored = sky_reflection(toward) * (0.2 + 0.8 * day);
        // How much of the sky the surface mirrors: a film on the ground, less on walls; a puddle
        // is still water and mirrors like the lake does.
        let film = soaked * mix(0.15, 0.45, max(n.y, 0.0)) * select(1.0, 0.3, leaves);
        let mirror = max(film * (fresnel * 0.8 + 0.2), puddle * clamp(fresnel * 0.9 + 0.12, 0.0, 1.0));
        colour = mix(colour, mirrored, mirror);
        // A puddle's own glint of whatever light gets through the clouds.
        let wet_half = normalize(view + to_light);
        colour += direct_colour * pow(max(dot(wet_n, wet_half), 0.0), 600.0) * 4.0 * puddle * facing * shadowed
            * exposure * select(0.0, 1.0, overworld);
    }

    // Soft shoulder so bright values roll off instead of clipping. Maps 1.0 to 1.0.
    colour = colour / (1.0 + colour * 0.35) * 1.35;

    // Underwater, the surroundings keep their own colours instead of all going blue.
    colour = mix(colour, grade_saturation(colour, 0.75) * vec3<f32>(0.95, 1.0, 0.97), frame.in_water * 0.5);

    // Tells the post passes what this is: leaves (data 1), whose see-through holes ambient
    // occlusion would otherwise mistake for deep creases; lava (data 2), over which the air
    // shimmers; anything else that gives off light (data 3), the only land that blooms; and how
    // glossy it is.
    let glows = input.emission > 0.0;
    let kind = select(select(select(0.0, 3.0, glows), 2.0, input.fluid == 2u), 1.0, leaves);
    set_surface(n, max(puddle, smoothness), kind);
    out.color = vec4<f32>(colour, base.a);
    return out;
}
