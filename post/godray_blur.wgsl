// Smooths the god rays' per-pixel noise: twelve taps on two rings. Taps across the edge between sky
// and terrain count less, so shafts don't smear onto a tree or a hill that stands in front of them.
// Which taps are sky the march left in their alpha (8 added to the exposure), so this pass reads
// no depth; it passes the exposure on in its own alpha, for the composite and next frame's march.
fn sky_flag(a: f32) -> bool {
    return a >= 8.0;
}

fn post(input: PostInput) -> vec4<f32> {
    let texel = 2.0 / frame.resolution;
    let centre = textureSampleLevel(godray_raw, nearest_sampler, input.uv, 0.0);
    let sky_here = sky_flag(centre.a);
    var sum = centre.rgb * 0.2;
    var total = 0.2;
    for (var i = 0; i < 12; i++) {
        let angle = f32(i) * 0.5235988;
        let radius = select(2.0, 4.5, (i & 1) == 1);
        let uv = input.uv + vec2<f32>(cos(angle), sin(angle)) * radius * texel;
        let tap = textureSampleLevel(godray_raw, nearest_sampler, uv, 0.0);
        let weight = select(0.3, 1.0, sky_flag(tap.a) == sky_here) * 0.1;
        sum += tap.rgb * weight;
        total += weight;
    }
    let exposure = centre.a - select(0.0, 8.0, sky_here);
    // The sky flag goes on to the composite with the exposure, so it can keep the rays on their
    // own side of an edge when it enlarges them.
    return vec4<f32>(sum / total, exposure + select(0.0, 8.0, sky_here));
}
