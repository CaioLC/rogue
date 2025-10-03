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
    let ratio = 640.0 / 480.0;
    let time = uMyUniforms.time;
    var offset = vec2f(-0.6875, -0.463);
    offset += 0.3 * vec2f(cos(time), sin(time));

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
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let color = in.color * uMyUniforms.color.rgba;
    return color;
}

