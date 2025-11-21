const zmath = @import("zmath");

pub const PerspectiveCamera = struct {
    focal_len: f32,

    fn make_projection(self: PerspectiveCamera, ratio: f32, near: f32, far: f32) zmath.Mat {
        const denominator = self.focal_len * (far - near);
        const p_zz = far / denominator;
        const p_zw = -(far * near) / denominator;
        return zmath.matFromArr(.{
            self.focal_len, 0.0,                    0.0,  0.0,
            0.0,            self.focal_len * ratio, 0.0,  0.0,
            0.0,            0.0,                    p_zz, p_zw,
            0.0,            0.0,                    1.0,  0.0,
        });
    }
};

pub const OrtogonalCamera = struct {
    scale: f32,

    fn make_projection(self: OrtogonalCamera, ratio: f32, near: f32, far: f32) zmath.Mat {
        return zmath.matFromArr(.{
            1.0 / self.scale, 0.0,                0.0,                0.0,
            0.0,              ratio / self.scale, 0.0,                0.0,
            0.0,              0.0,                1.0 / (far - near), -near / (far - near),
            0.0,              0.0,                0.0,                1.0,
        });
    }
};

pub const CameraTypes = enum { perspective, ortogonal };
pub const CameraType = union(CameraTypes) {
    perspective: PerspectiveCamera,
    ortogonal: OrtogonalCamera,
};

pub const Camera = struct {
    camera_type: CameraType,
    near: f32,
    far: f32,
    window_ratio: f32,
    world_view: zmath.Mat,
    camera_view: zmath.Mat,
    clip_view: zmath.Mat,

    pub fn init(camera_type: CameraType, window_ratio: f32, near: f32, far: f32) Camera {
        const world_view = zmath.identity();
        const camera_view = cam_view: {
            var cview: zmath.Mat = undefined;
            switch (camera_type) {
                .perspective => {
                    cview = camera_type.perspective.make_projection(window_ratio, near, far);
                },
                .ortogonal => {
                    cview = camera_type.ortogonal.make_projection(window_ratio, near, far);
                },
            }
            break :cam_view cview;
        };
        const clip_view = zmath.identity();
        return Camera{
            .camera_type = camera_type,
            .near = near,
            .far = far,
            .window_ratio = window_ratio,
            .world_view = world_view,
            .camera_view = camera_view,
            .clip_view = clip_view,
        };
    }

    pub fn update(self: *Camera, window_ratio: f32) void {
        self.window_ratio = window_ratio;
    }
};
