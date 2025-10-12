struct MyUniforms {
    color: vec4f,
    time: f32,
};
@group(0) @binding(0) var<uniform> uMyUniforms: MyUniforms;

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
    let ratio = 1882.0 / 2260.0;
    let angle = uMyUniforms.time;
    let alpha = cos(angle);
    let beta = sin(angle);

    var out_position = vec4(
        in.position.x,
        alpha * in.position.y + beta * in.position.z,
        // alpha * in.position.z - beta * in.position.y,
        0.0,
        in.position.w,
    );
    out_position.y *= ratio;

    return VertexOutput(
        out_position,
        in.color,
    );
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let color = in.color * uMyUniforms.color.rgba;
    return color;
}

