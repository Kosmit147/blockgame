package blockgame

import "core:math"
import "core:math/linalg"

Camera :: struct {
	position: Vec3,
	yaw: f32,
	pitch: f32,
}

Camera_Vectors :: struct {
	forward: Vec3,
	right: Vec3,
	up: Vec3,
}

camera_vectors :: proc(camera: Camera) -> Camera_Vectors {
	forward: Vec3
	forward.x = math.cos(camera.yaw) * math.cos(camera.pitch)
	forward.y = math.sin(camera.pitch)
	forward.z = math.sin(camera.yaw) * math.cos(camera.pitch)
	forward = linalg.normalize(forward)

	right := linalg.normalize(linalg.cross(forward, WORLD_UP))
	up := linalg.normalize(linalg.cross(right, forward))

	return Camera_Vectors {
		forward = forward,
		right = right,
		up = up,
	}
}
