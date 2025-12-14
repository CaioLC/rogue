const pi = 3.14159265359;

struct Model {
    mat: mat4x4<f32>,
};

struct MyUniforms {
    projectionMatrix: mat4x4<f32>,
    viewMatrix: mat4x4<f32>,
    color: vec4f,
    time: f32,
};

@group(0) @binding(0) var<uniform> uMyUniforms: MyUniforms;
@group(1) @binding(0) var<uniform> uModel: Model;

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
    var out: VertexOutput;
    out.position = uMyUniforms.projectionMatrix * uMyUniforms.viewMatrix * uModel.mat * in.position;
    // out.position = in.position;
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let color = in.color * uMyUniforms.color.rgba;
    return color;
}

