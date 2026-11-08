// God rays: march each pixel's view ray through the shadow map and add up the sunlight the air
// scatters toward the camera. Only rays that cross both light and shadow show: the shafts between
// leaves, past tree trunks and through gaps in terrain; air that is wholly lit or wholly shaded
// adds nothing. Samples crowd near the camera, where the shafts under a canopy are. Written at
// half size.
//
// One frame's march at half size is grainy: 32 jittered steps per pixel. So the jitter walks on a
// different offset every frame (the golden ratio), and this frame's rays are mixed with last
// frame's final blurred rays (`godray`), reprojected into this frame with the camera's motion.
// A dozen frames average out most of the grain, and the blur pass after this one smooths the rest.
// The history is clamped around this frame's value, so a shaft that opens or closes catches up
// over a handful of frames instead of trailing behind; a fast camera trusts the history less.
override godray_amount: f32 = 3.0;
override sun_shafts: f32 = 1.0;

// Auto-exposure: how bright the picture is on average, from 16 points spread over it (their
// logarithm, so one bright window doesn't decide), turned into a gain that brings it toward a
// comfortable middle: dark caves are lifted, glaring snow eased a little. It moves smoothly, by
// last frame's value read back from `godray` (every pixel holds the same one), over a second or so.
fn eye_exposure() -> f32 {
    var sum = 0.0;
    for (var i = 0; i < 16; i++) {
        let uv = (vec2<f32>(f32(i % 4), f32(i / 4)) + 0.5) / 4.0;
        let c = textureSampleLevel(previous, linear_sampler, uv * 0.8 + 0.1, 0.0).rgb;
        sum += log2(max(luminance(c), 0.002));
    }
    let average = exp2(sum / 16.0);
    let goal = clamp(0.32 / average, 0.8, 1.7);
    let last = textureSampleLevel(godray, nearest_sampler, vec2<f32>(0.5), 0.0).a;
    let last_exposure = last - select(0.0, 8.0, last >= 8.0);
    let known = last_exposure > 0.1 && frame.delta_time > 0.0;
    // Opening up in the dark is slower than squinting in the light, as eyes do.
    let rate = select(0.6, 1.8, goal < last_exposure);
    let blend = 1.0 - exp(-frame.delta_time * rate);
    return select(goal, mix(last_exposure, goal, blend), known);
}

fn post(input: PostInput) -> vec4<f32> {
    // Which body lights the air. The shadow map follows `light_direction`, which turns to the moon
    // while the sun may still be on screen at dusk, so the volume and the screen shafts each follow
    // their own: the volume whichever body casts the shadows, the shafts the sun until it has set,
    // then the moon. Moonlight is faint and blue-white.
    // Rain comes with a sky full of cloud: no sun or moon to cast shafts, so they fade out as it
    // sets in (smoothly, as the rain itself does) and return as it clears.
    let overcast = smoothstep(0.1, 0.6, frame.rain);
    let dry = (1.0 - frame.in_water) * (1.0 - overcast);
    let sun_up = smoothstep(-0.08, 0.02, frame.sun_direction.y);
    let moon_up = smoothstep(0.0, 0.15, frame.moon_direction.y) * (1.0 - sun_up) * (1.0 - frame.rain);
    let moon_colour = vec3<f32>(0.55, 0.68, 1.0) * 0.22;
    let shadow_by_sun = dot(frame.light_direction, frame.sun_direction) > 0.0;
    let volume_light = select(moon_up, daylight(), shadow_by_sun) * dry;
    let shaft_body = select(frame.moon_direction, frame.sun_direction, sun_up > 0.0);
    let shaft_light = select(moon_up, sun_up, sun_up > 0.0) * dry;
    // The alpha carries two things to the passes after: the eye's exposure (below), and 8 more
    // where this pixel is sky, so the blur can tell sky from land without reading the depth again.
    let encoded = eye_exposure() + select(0.0, 8.0, input.depth <= 0.0);
    if godray_amount <= 0.0 || frame.has_shadow == 0u || max(volume_light, shaft_light) <= 0.0 {
        return vec4<f32>(0.0, 0.0, 0.0, encoded);
    }

    // The pixel's ray from two points on it: one right at the eye, one far along it (the world's
    // point, or a distant one over the sky). The eye is not at the origin of camera-relative space:
    // the view bob moves it a little to each side as you walk, and a direction taken from the
    // origin would swing with that.
    let sky_pixel = input.depth <= 0.0;
    let eye = view_position(input.uv, 0.9);
    let far_point = view_position(input.uv, select(0.001, input.depth, sky_pixel == false));
    let dir = normalize(far_point - eye);
    let reach = select(length(far_point - eye), 1.0e4, sky_pixel);
    // Over the sky only nearby shadows count, so a ray along the horizon doesn't add up every
    // hill and forest to the edge of the map into a bright band.
    let span = min(reach, frame.shadow_distance * select(0.7, 0.4, sky_pixel));
    // The jitter steps by the golden ratio each frame, so successive frames put their samples in
    // different places along the ray and the average has no fixed pattern to see.
    let jitter = fract(ign(input.pixel) + f32(frame.frame_index % 64u) * 0.61803398);
    let bias = 0.3 / shadow_range();

    var lit = 0.0;
    var total = 0.0;
    var crossings = 0.0;
    var last = -1.0;
    for (var i = 0; i < 24; i++) {
        let u = (f32(i) + jitter) / 24.0;
        let along = eye + dir * (span * u * u);
        let weight = 2.0 * u * span / 24.0;
        let p = shadow_position(along);
        let visible = textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy, p.z - bias);
        // The haze thins out with height above the sea.
        let height = along.y + frame.camera_position.y;
        let haze = exp(-max(height - 62.0, 0.0) * 0.015) * weight;
        lit += visible * haze;
        total += haze;
        crossings += select(abs(visible - last), 0.0, last < 0.0);
        last = visible;
    }

    // A shaft is lit air with shadow beside it: the share of the ray's air that is lit counts as far
    // as the ray also passes from light into shade and back. Under a canopy the few beams the ray
    // crosses show at full strength; air lit all the way (an open field) adds nothing, which the
    // atmosphere pass's haze covers. It is a share, 0..1, not a sum along the ray, so a long view
    // across open ground toward the sun doesn't pile up into a white wall.
    let share = lit / max(total, 0.001);
    let contrast = clamp(crossings * 0.5, 0.0, 1.0);
    let signal = sqrt(share) * contrast;

    // Brighter toward the sun, but never more than about three times what they are side-on. Over
    // bare sky the lobe is broad: the sky is drawn without the view bob the world has, and a tight
    // lobe there would slide off the sun as you walk.
    let cos_angle = dot(dir, normalize(frame.light_direction));
    let lobe = pow(max(cos_angle, 0.0), select(4.0, 1.5, sky_pixel));
    let phase = 0.35 + 0.65 * lobe;

    // Thicker air near sunrise and sunset and in rain; at noon thin but still there.
    let strength = 0.07 * (1.0 + sun_low() * 1.2) * godray_amount * profile_scale();
    let sun_colour = mix(vec3<f32>(1.0, 0.92, 0.78), vec3<f32>(1.0, 0.55, 0.25), sun_low());
    let volume_colour = select(moon_colour, sun_colour, shadow_by_sun);
    let shaft_colour = select(moon_colour, sun_colour, sun_up > 0.0);
    // Over the sky they count half as much, so the glow of the air doesn't turn into a haze.
    let shafts_volume = volume_colour * phase * signal * strength * volume_light * select(1.0, 0.5, sky_pixel);

    // Sun shafts: the rays that fan out from a low sun through the trees in front of it (light
    // scattering in screen space). From this pixel, 48 steps walk toward the sun on the screen and
    // add up the light of what they cross: open sky, as bright as it is drawn and brighter the nearer
    // the sun it lies, each step counting a little less than the one before. Where the sun shows
    // through a gap in the leaves, that bright patch throws a streak back along the walk; trunks and
    // branches in front of it leave dark wedges. Done on the screen, so the shafts line up exactly
    // with the silhouettes and with the sun as drawn.
    var shafts_screen = vec3<f32>(0.0);
    let sun_view = frame.view * vec4<f32>(normalize(shaft_body), 0.0);
    let sun_clip = frame.projection * sun_view;
    if sun_shafts > 0.0 && sun_clip.w > 0.0 {
        let sun_uv = vec2<f32>(sun_clip.x / sun_clip.w * 0.5 + 0.5, 0.5 - sun_clip.y / sun_clip.w * 0.5);
        let aspect = vec2<f32>(frame.resolution.x / frame.resolution.y, 1.0);
        // Fades as the sun leaves the screen, so the fan doesn't snap off at the edge.
        let off = max(max(-sun_uv.x, sun_uv.x - 1.0), max(-sun_uv.y, sun_uv.y - 1.0));
        // Only while the sun itself is (nearly) on the screen: off it, the walk toward it would run
        // out of the picture before reaching anything bright.
        let on_screen = 1.0 - smoothstep(-0.05, 0.1, off);
        let to_sun = sun_uv - input.uv;
        let reach = length(to_sun * aspect);
        if on_screen > 0.0 {
            // The walk covers at most a screen's height, in 48 steps.
            let walk = to_sun * min(1.0, 1.0 / max(reach, 0.001));
            var sum = 0.0;
            var decay = 1.0;
            for (var i = 0; i < 48; i++) {
                let uv = input.uv + walk * ((f32(i) + jitter) / 48.0);
                // Past the picture's edge there is nothing to read: the edge's own pixels, read over
                // and over, would smear ghost copies of whatever is there across the screen.
                if any(uv < vec2<f32>(0.0)) || any(uv > vec2<f32>(1.0)) {
                    break;
                }
                let sky = depth_at(uv) <= 0.0;
                let bright = luminance(textureSampleLevel(scene_color, linear_sampler, uv, 0.0).rgb);
                let near_sun = exp(-length((uv - sun_uv) * aspect) * 5.0);
                sum += select(0.0, near_sun * (0.3 + bright), sky) * decay;
                decay *= 0.975;
            }
            // Low sun: long golden shafts. High sun: shorter, paler ones.
            let shaft_strength = 0.09 * mix(0.45, 1.0, sun_low());
            let falloff = 1.0 - smoothstep(0.5, 1.5, reach);
            // Over open sky somewhat less, so the sky around the sun glows without washing out.
            shafts_screen = shaft_colour * sum * falloff * on_screen * shaft_strength * sun_shafts * shaft_light
                * select(1.0, 0.6, sky_pixel);
        }
    }    let shafts = shafts_volume + shafts_screen;
    // Where what this pixel shows was last frame: terrain at its own depth, the sky as if a
    // thousand blocks out (a direction reprojects well from anywhere).
    let here = select(eye + dir * 1000.0, view_position(input.uv, input.depth), sky_pixel == false);
    let last_clip = frame.previous_view_projection * vec4<f32>(here + frame.camera_motion, 1.0);
    // A point behind last frame's eye reprojects to nonsense; the guard keeps it finite and out.
    let w = select(1.0, last_clip.w, last_clip.w > 0.0);
    let prev_uv = vec2<f32>(last_clip.x / w * 0.5 + 0.5, 0.5 - last_clip.y / w * 0.5);
    let inside = all(prev_uv >= vec2<f32>(0.0)) && all(prev_uv <= vec2<f32>(1.0));
    let valid = last_clip.w > 0.0 && inside && frame.delta_time > 0.0;

    // Last frame's rays, already smoothed by the blur pass that follows this one. Clamping them
    // near this frame's value keeps an occluder that just moved from trailing: a shaft that went
    // dark keeps at most a little over half its brightness as this frame's, so it fades within a few frames.
    let history_ray = textureSampleLevel(godray, linear_sampler, prev_uv, 0.0).rgb;
    let lower = shafts * 0.6 - vec3<f32>(0.01);
    let upper = shafts * 1.5 + vec3<f32>(0.01);
    let kept = clamp(history_ray, lower, upper);
    // A running player, a teleport or a cutscene lines last frame's rays up less well.
    let speed = length(frame.camera_motion) / max(frame.delta_time, 1.0e-4);
    let weight = mix(0.7, 0.35, smoothstep(4.0, 20.0, speed)) * select(0.0, 1.0, valid);
    let rays = mix(shafts, kept, weight);
    return vec4<f32>(min(rays, vec3<f32>(1.0)), encoded);
}
