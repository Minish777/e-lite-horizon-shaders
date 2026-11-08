// Spreads the bright parts into a wide, soft halo at quarter size: a centre tap and two rings (rgb).
// In alpha, the brightness of the much wider sun glow: the bright sky (the prefilter's alpha) averaged over a spiral
// reaching about 160 pixels out, falling off smoothly, with a per-pixel start so it has no visible
// rings. Worked out here, at a sixteenth of the pixels, instead of in the composite; the composite
// tints it, since it is the sun's (or the moon's) own colour that glows that wide.
fn sun_glow(uv: vec2<f32>, noise: f32) -> f32 {
    let texel = 4.0 / frame.resolution;
    var sum = 0.0;
    var total = 0.0;
    for (var i = 0; i < 24; i++) {
        let t = (f32(i) + noise) / 24.0;
        let radius = mix(1.0, 40.0, t * t);
        let angle = f32(i) * 2.3999632 + noise * 6.2831853;
        let weight = exp(-radius / 14.0);
        sum += textureSampleLevel(bloom_half, linear_sampler, uv + vec2<f32>(cos(angle), sin(angle)) * radius * texel, 0.0).a * weight;
        total += weight;
    }
    return sum / total;
}

fn post(input: PostInput) -> vec4<f32> {
    let texel = 2.0 / frame.resolution;
    var sum = textureSampleLevel(bloom_half, linear_sampler, input.uv, 0.0).rgb * 0.2;
    for (var i = 0; i < 8; i++) {
        let angle = f32(i) * 0.7853982;
        let radius = select(1.5, 3.5, (i & 1) == 1);
        let offset = vec2<f32>(cos(angle), sin(angle)) * radius * texel;
        sum += textureSampleLevel(bloom_half, linear_sampler, input.uv + offset, 0.0).rgb * 0.1;
    }
    return vec4<f32>(sum, sun_glow(input.uv, ign(input.pixel)));
}
