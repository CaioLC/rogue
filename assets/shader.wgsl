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
    let ratio = 1200.0 / 800.0;
    var offset = vec2f(0.0);

    // Scale the object
    let S = mat4x4(
      0.3, 0.0, 0.0, 0.0,
      0.0, 0.3, 0.0, 0.0,
      0.0, 0.0, 0.3, 0.0,
      0.0, 0.0, 0.0, 1.0,
    );

    // Translate the object
    let T = transpose(mat4x4(
      1.0, 0.0, 0.0, 0.5,
      0.0, 1.0, 0.0, 0.0,
      0.0, 0.0, 1.0, 0.0,
      0.0, 0.0, 0.0, 1.0,
    ));

    // Rotate in the XY plane
    let angle1 = uMyUniforms.time;
    let c1 = cos(angle1);
    let s1 = sin(angle1);
    let R1 = transpose(mat4x4(
       c1,  s1, 0.0, 0.0,
      -s1,  c1, 0.0, 0.0,
      0.0, 0.0, 1.0, 0.0,
      0.0, 0.0, 0.0, 1.0,
    ));

    // Tilt the view point in the YZ plane
    // by three 8th of turn (1 turn = 2pi)
    let angle2 = 3.0 * pi / 4.0;
    let c2 = cos(angle2);
    let s2 = sin(angle2);
    let R2 = transpose(mat4x4(
      1.0, 0.0, 0.0, 0.0,
      0.0,  c2,  s2, 0.0,
      0.0, -s2,  c2, 0.0,
      0.0, 0.0, 0.0, 1.0,
    ));

    var position = R2 * R1 * T * S * in.position;

    // Move the view point
    let focalPoint = vec4f(0.0, 0.0, -2.0, 0.0);
    position = position - focalPoint;

    let focalLenght = 1.5;
   
    // Projection
    // let P = makeOrthographicProjection(ratio, 1.0, 0.0, 100.0);
// fn makePerspectiveProjection(ratio: f32, focalLenght: f32, near: f32, far: f32) -> mat4x4<f32> {
    let P = makePerspectiveProjection(ratio, focalLenght, 0.01, 100.0);

    out.position = P * position;
    out.position.w = position.z / focalLenght;
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let color = in.color * uMyUniforms.color.rgba;
    return color;
}

