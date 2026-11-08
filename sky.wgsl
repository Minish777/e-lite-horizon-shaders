// A cinematic but natural sky: a deep blue day with a thin pale haze at the horizon, layered gold,
// pink and violet at sunrise and sunset, and a quiet night with a faint Milky Way. The glow toward
// a low sun is wide on purpose: the game draws the sky's rays without view-bobbing and the sun
// itself with it, so a tight glow would slip off the sun as you walk. The sun's own bright halo
// comes from the bloom, which follows what is drawn.
override sky_warmth: f32 = 0.6;
override night_sky: bool = true;
override clouds: bool = true;
override cloud_amount: f32 = 0.5;
override stars: bool = true;
override stars_brightness: f32 = 1.0;
override stars_coverage: f32 = 1.0;
override aurora: f32 = 0.0;

// A fixed 0..1 value per point, used to break the Milky Way into soft clouds.
fn sky_hash(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
}

// Smooth value noise: a trilinear blend of eight hashed cell corners.
fn sky_noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let n000 = sky_hash(i + vec3<f32>(0.0, 0.0, 0.0));
    let n100 = sky_hash(i + vec3<f32>(1.0, 0.0, 0.0));
    let n010 = sky_hash(i + vec3<f32>(0.0, 1.0, 0.0));
    let n110 = sky_hash(i + vec3<f32>(1.0, 1.0, 0.0));
    let n001 = sky_hash(i + vec3<f32>(0.0, 0.0, 1.0));
    let n101 = sky_hash(i + vec3<f32>(1.0, 0.0, 1.0));
    let n011 = sky_hash(i + vec3<f32>(0.0, 1.0, 1.0));
    let n111 = sky_hash(i + vec3<f32>(1.0, 1.0, 1.0));
    let nx00 = mix(n000, n100, u.x);
    let nx10 = mix(n010, n110, u.x);
    let nx01 = mix(n001, n101, u.x);
    let nx11 = mix(n011, n111, u.x);
    let nxy0 = mix(nx00, nx10, u.y);
    let nxy1 = mix(nx01, nx11, u.y);
    return mix(nxy0, nxy1, u.z);
}

// A precise 0..1 hash of a 2D integer cell. The bit hash stays exact at any coordinate, where a
// hash built from sin() would break into visible bands far from the world's origin.
fn sky_cell_hash(ix: i32, iy: i32) -> f32 {
    return hash3(bitcast<vec3<u32>>(vec3<i32>(ix, iy, 0)));
}

// 2D value noise: a smooth blend of the four hashed corners of a cell.
fn sky_value_noise(p: vec2<f32>) -> f32 {
    let i = vec2<i32>(floor(p));
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let n00 = sky_cell_hash(i.x, i.y);
    let n10 = sky_cell_hash(i.x + 1, i.y);
    let n01 = sky_cell_hash(i.x, i.y + 1);
    let n11 = sky_cell_hash(i.x + 1, i.y + 1);
    return mix(mix(n00, n10, u.x), mix(n01, n11, u.x), u.y);
}

// Five octaves of value noise, each twice as fine and half as strong: broad cloud masses with
// smaller puffs riding on them. Kept in 0..1.
fn sky_fbm(p: vec2<f32>) -> f32 {
    var total = 0.0;
    var amplitude = 0.5;
    var q = p;
    for (var i = 0; i < 5; i = i + 1) {
        total = total + sky_value_noise(q) * amplitude;
        q = q * 2.03 + vec2<f32>(11.3, 5.9);
        amplitude = amplitude * 0.5;
    }
    return total * 1.032258;
}

// One domain warp: two smooth noise fields push the cloud coordinates about, turning round
// blobs into curling, billowing shapes.
fn sky_cloud_warp(p: vec2<f32>) -> vec2<f32> {
    let wx = sky_value_noise(p * 0.45 + vec2<f32>(2.3, 7.7)) * 0.66
        + sky_value_noise(p * 1.15 + vec2<f32>(5.1, 1.9)) * 0.34;
    let wy = sky_value_noise(p * 0.45 + vec2<f32>(9.2, 3.4)) * 0.66
        + sky_value_noise(p * 1.15 + vec2<f32>(1.7, 8.6)) * 0.34;
    return p + (vec2<f32>(wx, wy) - vec2<f32>(0.5)) * 2.0;
}

// A field of point stars seen along `d`: one candidate per cell of a grid over the sky, kept
// sparsely, dimmer and twinkling more near the horizon. The whole field turns about the
// east-west axis with the time of day, so the sky wheels overhead through the night.
fn sky_stars(d: vec3<f32>) -> vec3<f32> {
    let angle = frame.game_time * 6.2831853;
    let c = cos(angle);
    let s = sin(angle);
    let r = vec3<f32>(d.x, d.y * c - d.z * s, d.y * s + d.z * c);

    // Cells of about a third of a degree: hash each one and keep a few percent of them.
    let cell = vec3<i32>(floor(r * 180.0));
    let key = bitcast<vec3<u32>>(cell);
    let keep = select(0.0, 1.0, hash3(key) > 1.0 - 0.03 * clamp(stars_coverage, 0.0, 2.0));
    let bright = hash3(key + vec3<u32>(941u, 337u, 613u));
    let tint = hash3(key + vec3<u32>(73u, 521u, 887u));

    // The star sits a little off the cell's centre, so the grid itself never shows through.
    let jitter = vec3<f32>(
        hash3(key + vec3<u32>(191u, 71u, 433u)),
        hash3(key + vec3<u32>(277u, 991u, 53u)),
        hash3(key + vec3<u32>(619u, 197u, 769u)));
    let centre = (vec3<f32>(cell) + jitter) / 180.0;
    let point = 1.0 - smoothstep(0.0, 0.0025, length(r - centre));

    // Slow twinkling, stronger low down where the air is thickest.
    let phase = frame.time * (0.9 + 1.8 * tint) + bright * 31.0;
    let amount = 0.30 + 0.45 * (1.0 - smoothstep(0.0, 0.45, d.y));
    let twinkle = mix(1.0, 0.70 + 0.30 * sin(phase), amount);

    // A little colour temperature: some stars warm and orange, some cool and blue.
    let star_col = mix(vec3<f32>(0.72, 0.82, 1.00), vec3<f32>(1.00, 0.84, 0.68), tint);
    let strength = keep * point * twinkle * (0.20 + 0.80 * bright * bright) * stars_brightness;
    return star_col * strength;
}

// E-LITE AURORA: ribbons of mint, lilac and pink drifting across the night sky.
fn aurora_light(d: vec3<f32>, t: f32) -> vec3<f32> {
    if d.y <= 0.05 { return vec3<f32>(0.0); }
    let plane = d.xz / (d.y + 0.25);
    var sum = vec3<f32>(0.0);
    for (var i = 0; i < 3; i++) {
        let k = f32(i);
        let q = plane * (0.6 + k * 0.25) + vec2<f32>(k * 3.1, t * 0.015 * (1.0 + k));
        let bend = (sky_value_noise(vec2<f32>(q.x * 0.5, t * 0.03 + k)) - 0.5) * 2.5;
        let band = exp(-pow((q.y - bend - (k - 1.0) * 0.9) * 1.6, 2.0));
        let rays = 0.45 + 0.55 * sky_value_noise(vec2<f32>(q.x * 9.0 + t * 0.2, k * 5.0));
        let hue = mix(vec3<f32>(0.45, 0.95, 0.75), mix(vec3<f32>(0.75, 0.65, 1.0), vec3<f32>(1.0, 0.7, 0.9), k * 0.5), k * 0.5);
        sum += hue * band * rays;
    }
    let height = smoothstep(0.05, 0.35, d.y) * (1.0 - smoothstep(0.8, 1.0, d.y) * 0.5);
    return sum * height * 0.65;
}

fn sky(input: SkyInput) -> vec4<f32> {
    // The Nether, the End and modded dimensions keep vanilla's sky.
    if frame.dimension != 0 {
        return input.color;
    }

    let d = input.direction;
    let sun_dir = frame.sun_direction;
    let base = input.color.rgb;
    let up = max(d.y, 0.0);

    // Day: vanilla's colour deepened to a saturated blue overhead, and a pale haze at the horizon.
    let height = smoothstep(0.0, 0.55, up);
    let haze = 1.0 - smoothstep(0.0, 0.15, up);
    // E-LITE ZENITH_DAY_COLOR (0.14, 0.24, 0.36), HORIZON_DAY_COLOR (0.65, 0.91, 1.30).
    let zenith = mix(grade_saturation(base * vec3<f32>(0.46, 0.72, 1.12), 1.2), vec3<f32>(0.14, 0.24, 0.36), 0.30);
    let horizon = mix(base, vec3<f32>(0.65, 0.91, 1.30), 0.55);
    var day_color = mix(horizon, zenith, height);
    day_color = mix(day_color, vec3<f32>(0.90, 0.94, 1.0), haze * 0.30);
    // Just under the horizon the sky settles into a slightly darker band.
    day_color = day_color * mix(1.0, 0.62, smoothstep(0.0, 0.28, -d.y));

    // Which side of the sky, ignoring height: the sun's or the one opposite it.
    let hd = normalize(vec3<f32>(d.x, 0.0, d.z) + vec3<f32>(0.0001, 0.0, 0.0001));
    let hs = normalize(vec3<f32>(sun_dir.x, 0.0, sun_dir.z) + vec3<f32>(0.0001, 0.0, 0.0001));
    let anti_side = clamp(-dot(hd, hs), 0.0, 1.0);

    // The glow toward a low sun is wide: squashing the rays' y spreads it upward instead of making
    // a tight halo around the sun's drawn disc.
    let squashed_d = normalize(vec3<f32>(d.x, d.y * 0.45, d.z));
    let squashed_sun = normalize(vec3<f32>(sun_dir.x, sun_dir.y * 0.45, sun_dir.z));
    let toward = max(dot(squashed_d, squashed_sun), 0.0);

    // 1 while the sun sits low but the sky still has daylight in it.
    let sunset = sun_low() * smoothstep(-0.15, 0.02, sun_dir.y);
    let warm = clamp(sky_warmth, 0.0, 1.0);

    // Layered dusk: orange right at the horizon toward the sun, pink above it, violet overhead.
    let gold = vec3<f32>(1.00, 0.55, 0.22);
    let pink = vec3<f32>(0.95, 0.38, 0.58);
    let violet = vec3<f32>(0.15, 0.14, 0.34);
    let gold_band = (1.0 - smoothstep(0.0, 0.16, up)) * pow(toward, 1.6);
    let pink_band = smoothstep(0.0, 0.05, up) * (1.0 - smoothstep(0.16, 0.55, up)) * pow(toward, 1.1);
    var twilight = mix(base * vec3<f32>(0.78, 0.70, 0.88), violet, smoothstep(0.10, 0.65, up) * 0.70);
    twilight = mix(twilight, gold, gold_band * warm * 0.85);
    twilight = mix(twilight, pink, pink_band * warm * 0.55);

    // Opposite the sun: a faint pink Belt of Venus over a bluish earth shadow.
    let above = smoothstep(-0.04, 0.0, d.y);
    let earth_band = (1.0 - smoothstep(0.0, 0.075, up)) * above;
    let belt_band = smoothstep(0.0, 0.03, up) * (1.0 - smoothstep(0.06, 0.24, up)) * above;
    let anti = pow(anti_side, 2.5);
    twilight = mix(twilight, vec3<f32>(0.13, 0.16, 0.30), earth_band * anti * 0.45);
    twilight = mix(twilight, vec3<f32>(0.86, 0.50, 0.58), belt_band * anti * warm * 0.35);

    var color = mix(day_color, twilight, sunset);

    // Night: deep blue-black overhead, a slightly lighter horizon and a faint airglow.
    let night = 1.0 - smoothstep(-0.18, 0.02, sun_dir.y);
    // E-LITE ZENITH_NIGHT_COLOR (0.014, 0.019, 0.025), HORIZON_NIGHT_COLOR (0.021, 0.031, 0.039).
    var night_color = mix(vec3<f32>(0.021, 0.031, 0.039), vec3<f32>(0.014, 0.019, 0.025),
        smoothstep(0.0, 0.55, up));
    night_color += base * vec3<f32>(0.045, 0.055, 0.085);
    night_color += vec3<f32>(0.025, 0.070, 0.050) * ((1.0 - smoothstep(0.0, 0.30, up)) * 0.35);

    // A faint Milky Way: a soft band along a fixed great circle, broken into clouds by value noise.
    // It adds at most 0.03 and only shows on a clear night, with vanilla's stars over it.
    let mw_axis = normalize(vec3<f32>(0.55, 0.42, -0.72));
    let mw_band = 1.0 - smoothstep(0.05, 0.30, abs(dot(d, mw_axis)));
    let mw_cloud = sky_noise(d * 5.0 + vec3<f32>(4.2, 9.1, 2.7));
    let mw_visible = smoothstep(-0.05, 0.12, d.y) * (1.0 - frame.rain) * (1.0 - daylight())
        * select(0.0, 1.0, night_sky);
    night_color += vec3<f32>(0.74, 0.80, 1.0) * (mw_band * (0.20 + 0.80 * mw_cloud) * mw_visible * 0.03);
    night_color += aurora_light(d, frame.time) * aurora * smoothstep(-0.05, 0.12, d.y) * (1.0 - frame.rain) * (1.0 - daylight());

    color = mix(color, night_color, night);

    // Rain flattens the sky: less colour, and a nearly even grey from horizon to zenith.
    let rain_amount = clamp(frame.rain, 0.0, 1.0);
    let grey = vec3<f32>(luminance(color));
    let overcast = mix(vec3<f32>(0.020, 0.026, 0.038), vec3<f32>(0.34, 0.37, 0.41), daylight());
    let flattened = mix(grey, overcast, 0.55);
    color = mix(color, flattened, rain_amount * 0.85);

    // The moon's soft halo on a clear night: a wide, faint blue-white glow that the clouds draw
    // over afterwards. The rain washes it out.
    let moon_dot = max(dot(d, frame.moon_direction), 0.0);
    let moon_night = (1.0 - daylight()) * smoothstep(-0.04, 0.06, d.y);
    let moon_halo = (pow(moon_dot, 8.0) * 0.055 + pow(moon_dot, 28.0) * 0.065)
        * moon_night * (1.0 - 0.9 * rain_amount);
    color = color + vec3<f32>(0.66, 0.78, 1.0) * moon_halo;

    // The sun, drawn here instead of the game's square: a round disc a little larger than the real
    // one (so it reads at Minecraft's scale), darker and redder toward its rim as the real sun is,
    // white-gold high up and deep orange-red as the air near the horizon thickens. A tight bright
    // corona hugs it; the wide glow comes from the bloom, which follows this disc. Clouds, drawn
    // after, cover it.
    if (sun_dir.y > -0.1) {
        let along = dot(d, sun_dir);
        let radius = 0.035;
        let apart = acos(clamp(along, -1.0, 1.0));
        let disc = 1.0 - smoothstep(radius * 0.92, radius, apart);
        let rim = clamp(apart / radius, 0.0, 1.0);
        let limb = 1.0 - 0.45 * (1.0 - sqrt(max(1.0 - rim * rim, 0.0)));
        let low = sun_low();
        let disc_colour = mix(vec3<f32>(1.0, 0.97, 0.9), vec3<f32>(1.0, 0.45, 0.12), low * low) * limb;
        let corona = exp(-max(apart - radius, 0.0) * 90.0) * 0.6 + exp(-max(apart - radius, 0.0) * 18.0) * 0.18;
        let corona_colour = mix(vec3<f32>(1.0, 0.92, 0.75), vec3<f32>(1.0, 0.5, 0.18), low);
        // Below the horizon line the disc sinks behind the haze rather than cutting off.
        let horizon = smoothstep(-0.03, 0.02, d.y) * (1.0 - frame.rain * 0.85);
        color = color + corona_colour * corona * (1.0 - disc) * horizon;
        color = mix(color, disc_colour * 1.6, disc * horizon);
    }

    // Stars: only on a clear night, and only above the horizon.
    let star_vis = (1.0 - daylight()) * (1.0 - rain_amount) * smoothstep(0.0, 0.12, d.y);
    if (stars && star_vis > 0.0) {
        color = color + sky_stars(d) * star_vis;
    }

    // Clouds: a flat layer 600 blocks overhead, found by intersecting the view ray with it. The
    // layer follows the camera a little, so it slides past rather than swinging, and drifts with
    // the wind. Only rays that actually head upward see it.
    if (clouds && d.y > 0.02) {
        var plane = d.xz / d.y * 600.0 + frame.camera_position.xz * 0.5
            + frame.time * vec2<f32>(3.0, 1.0);
        // Far out toward the horizon the ray almost grazes the layer and the projection runs away,
        // so pull the distance in; the fade below hides the seam.
        let plane_len = length(plane);
        plane = plane * min(1.0, 9000.0 / max(plane_len, 1.0));
        let p = plane * 0.0022;

        // One domain warp bends the noise into soft, billowing shapes instead of round blobs.
        let q = sky_cloud_warp(p);

        // More cloud with rain: overcast is the same layer, denser and flatter.
        let coverage = clamp(cloud_amount + 0.9 * rain_amount, 0.0, 1.0);
        let threshold = mix(0.94, 0.22, coverage);
        let softness = 0.12;

        let n = sky_fbm(q);
        let density = smoothstep(threshold, threshold + softness, n);
        // Sample the same layer a little way toward the sun: where that is denser too, this spot
        // lies in the cloud's own shadow.
        let sun_h = vec2<f32>(hs.x, hs.z);
        let shadow_density = smoothstep(threshold, threshold + softness, sky_fbm(q + sun_h * 0.38));
        let light = 1.0 - shadow_density * 0.55;

        // Colour: white tops and grey bases by day, warm undersides at sunset, a dim blue-grey at
        // night with the moon silvering the edges, and flat grey in the rain.
        let day_lit = vec3<f32>(0.95, 0.97, 1.00);
        let day_shade = vec3<f32>(0.52, 0.57, 0.67);
        var cloud_col = mix(day_shade, day_lit, light);

        // At sunset the light comes from below: undersides catch gold toward the sun and pink away
        // from it, strongest on the parts already in shadow and low in the view.
        let sun_side = max(dot(hd, hs), 0.0);
        let dusk = mix(vec3<f32>(1.00, 0.46, 0.56), vec3<f32>(1.00, 0.62, 0.28), sun_side);
        let dusk_amount = sunset * (0.25 + 0.60 * shadow_density)
            * (1.0 - smoothstep(0.18, 0.80, d.y));
        cloud_col = mix(cloud_col, dusk, dusk_amount * 0.85);

        // Night: dark blue-grey, faintly lit by the moon on its side of the sky.
        let moon_side = pow(max(dot(d, frame.moon_direction), 0.0), 3.0);
        let night_col = mix(vec3<f32>(0.018, 0.026, 0.048), vec3<f32>(0.070, 0.085, 0.130), light)
            + vec3<f32>(0.10, 0.12, 0.17) * moon_side * light;
        cloud_col = mix(night_col, cloud_col, daylight());

        // Rain flattens the clouds too: darker, greyer and even.
        let rain_grey = vec3<f32>(0.30, 0.32, 0.35) * mix(0.30, 1.0, daylight());
        cloud_col = mix(cloud_col, rain_grey, rain_amount * 0.80);

        // Silver lining: thin edges toward the sun catch a bright warm rim.
        let sun_face = max(dot(d, sun_dir), 0.0);
        let edge = 4.0 * density * (1.0 - density);
        let silver = pow(sun_face, 7.0) * edge * (0.35 + 0.65 * daylight()) * 0.55;
        cloud_col = cloud_col + vec3<f32>(1.0, 0.92, 0.80) * silver;
        // The moon does the same at night, faintly blue.
        let moon_edge = pow(max(dot(d, frame.moon_direction), 0.0), 9.0)
            * edge * (1.0 - daylight()) * 0.30;
        cloud_col = cloud_col + vec3<f32>(0.62, 0.72, 0.95) * moon_edge;

        // Near the horizon, blend the clouds into the haze so the layer's edge has no hard line.
        cloud_col = mix(cloud_col, color, (1.0 - smoothstep(0.05, 0.30, d.y)) * 0.6);
        let fade = smoothstep(0.02, 0.10, d.y);
        let cloud_alpha = min(density * fade, 0.95);
        color = mix(color, cloud_col, cloud_alpha);
    }

    return vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}
