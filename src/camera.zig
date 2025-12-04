const zmath = @import("zmath");

pub const PerspectiveCamera = struct {
    f_length: f32,

    pub fn init(focal_length: f32) PerspectiveCamera {
        return .{ .f_length = focal_length };
    }

    pub fn update(self: *PerspectiveCamera, focal_length: f32) void {
        self.f_length = focal_length;
    }

    fn make_projection(self: PerspectiveCamera, ratio: f32, near: f32, far: f32) zmath.Mat {
        return zmath.matFromArr(.{
            self.f_length / ratio, 0.0,           0.0,                        0.0,
            0.0,                   self.f_length, 0.0,                        0.0,
            0.0,                   0.0,           far / (far - near),         1.0,
            0.0,                   0.0,           -far * near / (far - near), 0.0,
        });
    }
};

pub const OrtogonalCamera = struct {
    scale: f32,

    pub fn init(scale: f32) OrtogonalCamera {
        return .{ .scale = scale };
    }

    pub fn update(self: *PerspectiveCamera, scale: f32) void {
        self.scale = scale;
    }

    fn make_projection(self: OrtogonalCamera, ratio: f32, near: f32, far: f32) zmath.Mat {
        return zmath.matFromArr(.{
            1.0 / self.scale, 0.0,                0.0,                  0.0,
            0.0,              ratio / self.scale, 0.0,                  0.0,
            0.0,              0.0,                1.0 / (far - near),   0.0,
            0.0,              0.0,                -near / (far - near), 1.0,
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
    model_matrix: zmath.Mat,
    view_matrix: zmath.Mat,
    projection_matrix: zmath.Mat,

    pub fn init(camera_type: CameraType, window_ratio: f32, near: f32, far: f32) Camera {
        var safe_near = near;
        const world_view = zmath.identity();
        const camera_view = zmath.identity();
        const projection_view = proj: {
            var pview: zmath.Mat = undefined;
            switch (camera_type) {
                .perspective => {
                    if (near == 0.0) {
                        safe_near += 0.01; // projection matrix cannot have near == zero
                    }
                    pview = camera_type.perspective.make_projection(window_ratio, near, far);
                },
                .ortogonal => {
                    pview = camera_type.ortogonal.make_projection(window_ratio, near, far);
                },
            }
            break :proj pview;
        };
        return Camera{
            .camera_type = camera_type,
            .near = safe_near,
            .far = far,
            .window_ratio = window_ratio,
            .model_matrix = world_view,
            .view_matrix = camera_view,
            .projection_matrix = projection_view,
        };
    }

    pub fn resize(self: *Camera, window_ratio: f32) void {
        self.window_ratio = window_ratio;
        const projection_view = proj: {
            var pview: zmath.Mat = undefined;
            switch (self.camera_type) {
                .perspective => {
                    pview = self.camera_type.perspective.make_projection(window_ratio, self.near, self.far);
                },
                .ortogonal => {
                    pview = self.camera_type.ortogonal.make_projection(window_ratio, self.near, self.far);
                },
            }
            break :proj pview;
        };
        self.projection_matrix = projection_view;
    }
};
