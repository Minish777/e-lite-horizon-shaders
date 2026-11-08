// Leaves sway gently in the wind. Corners are camera-relative, so the phase uses the world position,
// otherwise the sway would shimmer as the camera moves. The shadow map uses the same positions.
override waving: bool = true;
override wind_force: f32 = 1.0;

fn vertex(input: VertexInput) -> vec3<f32> {
    var p = input.position;
    // E-LITE WAVING + WIND_FORCE: leaves sway most, plants less (material 2).
    if waving && (input.material == 1u || input.material == 2u) {
        let world = p + frame.camera_position;
        let amp = select(0.012, 0.03, input.material == 1u) * wind_force;
        let gust = 1.0 + frame.rain * 0.8 + frame.thunder * 0.6;
        let phase = frame.time * 1.4 + world.x * 0.8 + world.z * 0.6 + world.y * 0.3;
        p.x += sin(phase) * amp * gust;
        p.z += cos(phase * 0.9 + 1.7) * amp * gust;
        p.y += sin(phase * 1.3) * amp * 0.4 * gust;
    }
    return p;
}
