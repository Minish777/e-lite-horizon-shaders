// Final pass: adds the god rays, bloom, sun glow and a faint anamorphic streak, tints the picture
// underwater, rolls highlights off with a film-like shoulder, then grades it: a gentle S-curve,
// warm highlights over cool shadows, and a little extra colour where it is dull. Dark places are
// lifted a touch so caves stay readable, and with the HUD hidden (F1) the frame can take
// cinematic bars.
override bloom_amount: f32 = 0.5;
override glow_amount: f32 = 1.0;
override saturation: f32 = 1.1;
override vignette: bool = true;
override color_scheme: u32 = 1u;
override grade_strength: f32 = 1.0;
override lens_streak: f32 = 0.3;
override chromatic_aberration: f32 = 0.3;
override film_grain: f32 = 0.15;
override letterbox: bool = true;
override cave_exposure: f32 = 0.5;
override debug_view: u32 = 0u;
override exposure: f32 = 1.0;
override brightness: f32 = 1.1;
override contrast: f32 = 1.0;
override gamma: f32 = 1.0;
override vibrance: f32 = 1.0;
override tonemapping: u32 = 0u;
override sharp_force: f32 = 0.25;
override dof_strength: f32 = 0.0;

// A thin horizontal flare through the brightest things, like an anamorphic lens: the quarter-size
// bloom read along a line, only its brightest part, tinted a little blue.
fn streak(uv: vec2<f32>) -> vec3<f32> {
    let step = vec2<f32>(6.0 / frame.resolution.x, 0.0);
    var sum = vec3<f32>(0.0);
    for (var i = 1; i <= 6; i++) {
        let w = exp(-f32(i) * 0.35);
        let a = textureSampleLevel(bloom_quarter, linear_sampler, uv + step * f32(i * i), 0.0).rgb;
        let b = textureSampleLevel(bloom_quarter, linear_sampler, uv - step * f32(i * i), 0.0).rgb;
        sum += (max(a - vec3<f32>(0.5), vec3<f32>(0.0)) + max(b - vec3<f32>(0.5), vec3<f32>(0.0))) * w;
    }
    return sum * vec3<f32>(0.7, 0.85, 1.2) * 0.35;
}

// Leaves everything below 0.75 alone and bends what lies above toward 1, keeping the hue: the
// brightest channel sets how much the whole colour is pulled in.
fn shoulder(c: vec3<f32>) -> vec3<f32> {
    let peak = max(c.r, max(c.g, c.b));
    if peak <= 0.75 {
        return c;
    }
    let rolled = 0.75 + 0.25 * (1.0 - exp(-(peak - 0.75) / 0.25));
    let scaled = c * (rolled / peak);
    // Very bright light bleaches toward white, as film does.
    return mix(scaled, vec3<f32>(rolled), smoothstep(1.2, 3.0, peak) * 0.6);
}

// E-LITE TONEMAPPING: 0 ACES, 1 Reinhard, 2 Lottes, 3 None (plain shoulder).
fn tonemap_apply(c: vec3<f32>) -> vec3<f32> {
    if tonemapping == 3u { return shoulder(c); }
    if tonemapping == 1u {
        return c / (1.0 + c);
    }
    if tonemapping == 2u {
        let a = 1.6; let d = 0.977; let hdr_max = 8.0; let mid_in = 0.18; let mid_out = 0.267;
        let b = -pow(mid_in, a) * pow(hdr_max, a - d) * mid_out;
        let cc = pow(mid_out, d * (a - d)) * pow(hdr_max, a * (a - d)) / pow(mid_in, a);
        let dd = pow(mid_out, d) * pow(hdr_max, a - d) - b;
        return clamp(pow(cc, 1.0 / a) * pow(c, d / a) / (pow(c, d) + dd), vec3<f32>(0.0), vec3<f32>(1.0));
    }
    let x = max(c, vec3<f32>(0.0));
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Tints the shadows toward `low` and the highlights toward `high` without changing brightness.
fn split_tone(c: vec3<f32>, low: vec3<f32>, high: vec3<f32>, amount: f32) -> vec3<f32> {
    let l = luminance(c);
    let tint = mix(low / luminance(low), high / luminance(high), smoothstep(0.05, 0.7, l));
    return mix(c, c * tint, amount);
}

// An S-curve around a pivot: `amount` 0 leaves the picture alone, 1 is a strong film contrast.
fn contrast_curve(c: vec3<f32>, amount: f32) -> vec3<f32> {
    let s = c * c * (3.0 - 2.0 * c);
    return mix(c, s, amount);
}

// E-LITE COLOR_SCHEME / STYLE: 0 Vanilla (close to the game), 1 Realistic+ (teal shadows,
// amber light, deep contrast - E-LITE default), 2 LITE Legacy (cool, muted, dark),
// 3 Warm film (lifted warm blacks, golden highlights), 4 Vivid (rich colour and punch).
fn grade(c_in: vec3<f32>) -> vec3<f32> {
    let c = c_in;
    var g = c;
    if color_scheme == 1u {
        g = split_tone(c, vec3<f32>(0.62, 0.92, 1.0), vec3<f32>(1.0, 0.86, 0.66), 0.55);
        g = contrast_curve(g, 0.45);
        g = max(g - vec3<f32>(0.012), vec3<f32>(0.0)) * 1.04;
        // Warm hues (skin, wood, sunsets) richer; greens pulled slightly toward teal.
        let warmth = clamp((g.r - g.b) * 2.0, 0.0, 1.0);
        g = mix(g, grade_saturation(g, 1.25), warmth);
        g.g = mix(g.g, g.g * 0.96 + g.b * 0.04, clamp((g.g - g.r) * 4.0, 0.0, 1.0));
    } else if color_scheme == 2u {
        g = split_tone(c, vec3<f32>(0.85, 0.78, 0.95), vec3<f32>(1.0, 0.85, 0.6), 0.5);
        g = contrast_curve(g, 0.2);
        let green = clamp((g.g - max(g.r, g.b)) * 5.0, 0.0, 1.0);
        g = mix(g, grade_saturation(g, 0.7) * vec3<f32>(1.04, 1.0, 0.92), green * 0.6);
        // Faded blacks and a softly rolled top, like print film.
        g = vec3<f32>(0.05, 0.035, 0.03) + g * vec3<f32>(0.93, 0.92, 0.88);
    } else if color_scheme == 3u {
        g = grade_saturation(c, 0.7);
        g = split_tone(g, vec3<f32>(0.6, 0.8, 1.0), vec3<f32>(0.95, 0.95, 1.0), 0.5);
        g = contrast_curve(g * 0.92, 0.55);
    } else if color_scheme == 4u {
        g = grade_saturation(c, 1.35);
        g = contrast_curve(g, 0.35);
        g = split_tone(g, vec3<f32>(0.8, 0.9, 1.0), vec3<f32>(1.0, 0.95, 0.85), 0.25);
    } else {
        g = split_tone(c, vec3<f32>(0.9, 0.97, 1.05), vec3<f32>(1.05, 1.0, 0.94), 0.5);
        g = contrast_curve(g, 0.15);
    }
    return mix(c, clamp(g, vec3<f32>(0.0), vec3<f32>(1.0)), grade_strength);
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

// The god rays are worked out at half size. Stretched with plain filtering, a shaft over the sky
// bleeds a pale fringe onto the hill or the mob in front of it. So the four half-size texels
// around this pixel each count only if they are on the same side (sky or land) as this pixel,
// which the ray passes marked in their alpha.
fn upsample_rays(uv: vec2<f32>) -> vec3<f32> {
    let size = vec2<f32>(textureDimensions(godray));
    let st = uv * size - 0.5;
    let base = floor(st);
    let f = st - base;
    let sky_here = depth_at(uv) <= 0.0;
    var sum = vec3<f32>(0.0);
    var total = 0.0;
    for (var i = 0; i < 4; i++) {
        let o = vec2<f32>(f32(i & 1), f32(i >> 1u));
        let tap = textureSampleLevel(godray, nearest_sampler, (base + o + 0.5) / size, 0.0);
        let bilinear = mix(1.0 - f.x, f.x, o.x) * mix(1.0 - f.y, f.y, o.y);
        let same = select(0.05, 1.0, (tap.a >= 8.0) == sky_here);
        sum += tap.rgb * bilinear * same;
        total += bilinear * same;
    }
    return sum / max(total, 0.0001);
}

fn post(input: PostInput) -> vec4<f32> {
    // The Shadows debug view shows the material stage's output as it is, without anything added;
    // No post effects (3) shows the same with the material's full lighting.
    if debug_view >= 2u {
        return vec4<f32>(clamp(input.color.rgb, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
    }
    let rays = upsample_rays(input.uv);
    if debug_view == 1u {
        return vec4<f32>(clamp(rays * 3.0, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0);
    }

    // Lens fringing: red and blue drift apart toward the corners only, so the centre stays crisp.
    var c = input.color.rgb;
    if chromatic_aberration > 0.0 {
        let from_centre = input.uv - 0.5;
        let shift = from_centre * dot(from_centre, from_centre) * 0.012 * chromatic_aberration;
        c.r = textureSampleLevel(previous, linear_sampler, input.uv - shift, 0.0).r;
        c.b = textureSampleLevel(previous, linear_sampler, input.uv + shift, 0.0).b;
    }

    // Rays are added as light, but ease off over what is already bright, so a sunlit field behind
    // them glows instead of clipping to white.
    c += rays * (vec3<f32>(1.0) - min(c, vec3<f32>(1.0)) * 0.55) * profile_scale();
    let bloom = textureSampleLevel(bloom_quarter, linear_sampler, input.uv, 0.0);
    c += bloom.rgb * bloom_amount * profile_scale();
    // E-LITE DOF: depth-based blur, far and near parts soften (0 = off).
    if dof_strength > 0.0 {
        let d0 = depth_at(input.uv);
        if d0 > 0.0 {
            let radius = dof_strength * 0.012;
            var blur = vec3<f32>(0.0);
            var wsum = 0.0;
            for (var i = 0; i < 8; i++) {
                let a = f32(i) * 0.7853982;
                let uv2 = input.uv + vec2<f32>(cos(a), sin(a)) * radius;
                let d2 = depth_at(uv2);
                let w = clamp(abs(d2 - d0) * 2.0, 0.0, 1.0);
                blur += textureSampleLevel(previous, linear_sampler, uv2, 0.0).rgb * w;
                wsum += w;
            }
            if wsum > 0.01 {
                c = mix(c, blur / wsum, clamp(wsum / 8.0, 0.0, 1.0) * 0.7);
            }
        }
    }
    // E-LITE SHARP_FORCE: gentle unsharp mask.
    if sharp_force > 0.0 {
        let px = 1.0 / frame.resolution;
        let blur = (textureSampleLevel(previous, linear_sampler, input.uv + vec2<f32>(px.x, 0.0), 0.0).rgb
            + textureSampleLevel(previous, linear_sampler, input.uv - vec2<f32>(px.x, 0.0), 0.0).rgb
            + textureSampleLevel(previous, linear_sampler, input.uv + vec2<f32>(0.0, px.y), 0.0).rgb
            + textureSampleLevel(previous, linear_sampler, input.uv - vec2<f32>(0.0, px.y), 0.0).rgb) * 0.25;
        c += (c - blur) * sharp_force * 0.5;
    }
    let glow_tint = mix(vec3<f32>(1.0, 0.95, 0.85), vec3<f32>(1.0, 0.6, 0.3), sun_low());
    c += bloom.a * glow_tint * glow_amount * (1.0 - frame.in_water);
    if lens_streak > 0.0 {
        c += streak(input.uv) * lens_streak * (1.0 - frame.in_water);
    }

    // Underwater: the atmosphere pass already swapped the game's blue fog for clearer water; only
    // a slight loss of colour is left to add here.
    c = mix(c, grade_saturation(c, 0.85), frame.in_water * 0.5);

    // The eye adapts: the god-ray pass measured the picture's average brightness and eased a gain
    // toward it (in the alpha of `godray`), lifting dark caves and calming glare. "Eye adaptation"
    // sets how much of it applies.
    let packed = textureSampleLevel(godray, nearest_sampler, vec2<f32>(0.5), 0.0).a;
    let exposure = packed - select(0.0, 8.0, packed >= 8.0);
    c *= mix(1.0, clamp(exposure, 0.8, 1.7), cave_exposure);

    // E-LITE camera: tonemap, exposure, brightness, contrast, gamma, vibrance.
    c = tonemap_apply(max(c, vec3<f32>(0.0)));
    c = clamp(c, vec3<f32>(0.0), vec3<f32>(1.0));
    c *= exposure * brightness;
    c = clamp((c - 0.5) * contrast + 0.5, vec3<f32>(0.0), vec3<f32>(1.0));
    c = pow(c, vec3<f32>(1.0 / max(gamma, 0.01)));
    let vib_chroma = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
    c = mix(vec3<f32>(luminance(c)), c, 1.0 + (vibrance - 1.0) * (1.0 - clamp(vib_chroma, 0.0, 1.0)));

    c = grade(c);
    let chroma = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
    c = mix(vec3<f32>(luminance(c)), c, 1.0 + 0.2 * (1.0 - chroma));
    c = grade_saturation(c, saturation);

    if vignette {
        let p = (input.uv - 0.5) * vec2<f32>(frame.resolution.x / frame.resolution.y, 1.0);
        c *= 1.0 - 0.18 * smoothstep(0.45, 1.2, length(p));
    }

    // Grain that changes each frame and sits mostly in the mid-tones, where film shows it.
    if film_grain > 0.0 {
        let n = hash(input.pixel + vec2<f32>(f32(frame.frame_index % 1024u) * 7.13, 0.0)) - 0.5;
        let l = luminance(c);
        c += vec3<f32>(n * 0.06 * film_grain * (1.0 - abs(l * 2.0 - 1.0)));
    }

    // Bars for a 2.39:1 frame, only while F1 hides the HUD, so play is never cropped.
    if letterbox && frame.hide_gui == 1u {
        let aspect = frame.resolution.x / frame.resolution.y;
        let bar = max(0.5 - 0.5 * aspect / 2.39, 0.0);
        if input.uv.y < bar || input.uv.y > 1.0 - bar {
            c = vec3<f32>(0.0);
        }
    }
    return vec4<f32>(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}
