// Rain and snow streaks, lit and fogged by hand. Horizon applies neither light nor fog here, so a
// streak takes the day's sky colour through its sky light, warm block light near torches, and melts
// into the fog toward `frame.fog_end`. Alpha stays low so the world reads through the weather.

override rain_opacity: f32 = 1.0;

// A fixed hash for the lightning flicker: one value per eighth of a second, so every streak flashes
// together instead of each pixel picking its own moment.
fn weather_hash(n: f32) -> f32 {
    return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

fn weather(input: WeatherInput) -> vec4<f32> {
    let dist = length(input.position);

    // Sky light: the day's sky colour, a dim blue-grey at night, so rain does not glow after dark.
    let day = daylight();
    let sky_tint = mix(vec3<f32>(0.15, 0.17, 0.22), frame.sky_color, day);
    let sky_light = sky_tint * pow(input.light.y, 1.5);

    // Block light: warm, and curved so it pools under torches rather than washing out everything.
    let block_light = pow(input.light.x, 2.4) * vec3<f32>(1.0, 0.62, 0.3);

    // A little ambient keeps streaks from vanishing in shade and gives snow its soft lift.
    let ambient = vec3<f32>(0.05, 0.06, 0.08);
    let light = sky_light * 1.15 + block_light * 1.1 + ambient;

    // A raindrop is clear water: what shows is the sky it catches, so a streak is pale and a little
    // brighter than the sky light around it, never a solid grey. Snow is white and matte.
    let tint = select(vec3<f32>(0.82, 0.88, 1.0), vec3<f32>(1.0, 1.0, 1.02), input.snow);
    let sheen = select(1.35, 1.0, input.snow);
    var rgb = light * sheen * mix(vec3<f32>(luminance(input.color.rgb)), input.color.rgb, 0.3) * tint;

    // Lightning: rare, and only while it thunders hard. The pulse fades across its eighth of a
    // second, so it reads as a flicker instead of a hard step.
    let tick = floor(frame.time * 8.0);
    let strike = smoothstep(0.95, 1.0, weather_hash(tick));
    let decay = 1.0 - fract(frame.time * 8.0);
    let storm = select(0.0, 1.0, frame.thunder > 0.5);
    let flash = strike * decay * storm * frame.thunder * 0.6;
    rgb += vec3<f32>(0.85, 0.90, 1.0) * flash;

    // Far streaks take the fog colour, so they do not draw a hard edge in the distance.
    let far = clamp(dist / max(frame.fog_end, 1.0), 0.0, 1.0);
    let fog = smoothstep(0.55, 1.0, far);
    rgb = mix(rgb, frame.fog_color, fog);

    // Streaks right at the eye become huge and blurry: fade them in over the first block and a half.
    // Drops right in front of the eye are a blur too fast to see: fade them over the first few blocks.
    let near_fade = smoothstep(0.5, 3.0, dist);

    // Each streak is faint; it is the many of them, layered into the distance, that read as rain.
    let alpha_scale = select(0.3, 0.8, input.snow) * mix(0.8, 1.15, smoothstep(4.0, 24.0, dist));
    let alpha = clamp(input.color.a * alpha_scale * rain_opacity * near_fade, 0.0, 1.0);

    return vec4<f32>(min(rgb, vec3<f32>(1.0)), alpha);
}
