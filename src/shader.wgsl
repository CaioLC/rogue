@vertex
fn vs_main(@location(0) in_vertex_position: vec4f) -> @builtin(position) vec4f {
    return in_vertex_position;
}

@fragment
fn fs_main() -> @location(0) vec4f {
    return vec4f(0.0, 0.4, 1.0, 1.0);
}

