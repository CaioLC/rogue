@group(0) @binding(0) var<uniform> uTime: f32;

struct VertexInput {
    @location(0) position: vec4f,
    @location(1) color: vec4f,
}

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec4f,
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    let ratio = 640.0 / 480.0;
    var offset = vec2f(-0.6875, -0.463);
    offset += 0.3 * vec2f(cos(uTime), sin(uTime));

    let out_position = vec4(
        in.position.x + offset.x,
        in.position.y + offset.y,
        in.position.zw
    );

    return VertexOutput(
        out_position,
        in.color,
    );
}

@fragment
fn fs_main(@location(0) color: vec4f) -> @location(0) vec4f {
    return color;
}

