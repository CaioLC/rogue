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
    return VertexOutput(
        in.position,
        in.color
    );
}

@fragment
fn fs_main(@location(0) color: vec4f) -> @location(0) vec4f {
    return color;
}

