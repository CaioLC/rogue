const pi = 3.14159265359;

struct MyUniforms {
    projectionMatrix: mat4x4<f32>,
    viewMatrix: mat4x4<f32>,
    modelMatrix: mat4x4<f32>,
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

fn makeOrthographicProjection(ratio: f32, scale: f32, near: f32, far: f32) -> mat4x4<f32> {
  return transpose(mat4x4(
    1.0 / scale, 0.0        , 0.0, 0.0,
    0.0        , ratio / scale, 0.0, 0.0,
    0.0        , 0.0        , 1.0 / (far - near), -near / (far - near),
    0.0        , 0.0        , 0.0, 1.0,
  ));
}

fn makePerspectiveProjection(ratio: f32, focalLenght: f32, near: f32, far: f32) -> mat4x4<f32> {
  let denominator = focalLenght * (far - near);
  let p_zz = far / denominator;
  let p_zw = -(far * near) / denominator;
  return transpose(mat4x4(
    focalLenght, 0.0              , 0.0 , 0.0,  
    0.0        , focalLenght*ratio, 0.0 , 0.0,  
    0.0        , 0.0              , p_zz, p_zw,
    0.0        , 0.0              , 1.0, 0.0,
  ));
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.position = uMyUniforms.projectionMatrix * uMyUniforms.viewMatrix * uMyUniforms.modelMatrix * in.position;
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let color = in.color * uMyUniforms.color.rgba;
    return color;
}

