package blockgame

import gl "vendor:OpenGL"

import "core:math/linalg"
import "core:math"

// These symbols tell GPU drivers to use the dedicated graphics card.
@(export, rodata)
NvOptimusEnablement: u32 = 1
@(export, rodata)
AmdPowerXpressRequestHighPerformance: u32 = 1

Standard_Vertex :: struct {
	position: Vec3,
	normal: Vec3,
	uv: Vec2,
}

Renderer :: struct {
	model_uniform: Uniform(Mat4),
	view_uniform: Uniform(Mat4),
	projection_uniform: Uniform(Mat4),
}

@(private="file")
s_renderer: Renderer

renderer_init :: proc() -> (ok := false) {
	gl.ClearColor(0, 0, 0, 1)
	gl.Enable(gl.CULL_FACE)
	gl.CullFace(gl.BACK)
	gl.FrontFace(gl.CCW)
	gl.Enable(gl.DEPTH_TEST)

	renderer_get_uniforms()

	return true
}

renderer_deinit :: proc() {}

renderer_get_uniforms :: proc() {
	shader := get_shader(.Base)
	s_renderer.model_uniform = get_uniform(shader, "model", Mat4)
	s_renderer.view_uniform = get_uniform(shader, "view", Mat4)
	s_renderer.projection_uniform = get_uniform(shader, "projection", Mat4)
}

renderer_clear :: proc() {
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
}

renderer_begin_frame :: proc(camera: Camera) {
	camera_vectors := camera_vectors(camera)

	view := linalg.matrix4_look_at(eye = camera.position,
				       centre = camera.position + camera_vectors.forward,
				       up = camera_vectors.up)

	projection := linalg.matrix4_perspective(fovy = math.to_radians(f32(45)),
						 aspect = window_aspect_ratio(),
						 near = 0.1,
						 far = 100)

	use_shader(get_shader(.Base))
	set_uniform(s_renderer.view_uniform, view)
	set_uniform(s_renderer.projection_uniform, projection)
}

renderer_render_mesh :: proc(mesh: Mesh) {
	bind_mesh(mesh)
	gl.DrawElements(gl.TRIANGLES,
			i32(mesh.vertex_count),
			mesh.index_type,
			cast(rawptr)uintptr(mesh.index_data_offset))
}

renderer_render_chunk :: proc(chunk: Chunk) {
	model := linalg.matrix4_translate(Vec3{ f32(chunk.coordinate.x * CHUNK_SIZE.x),
						0,
						f32(chunk.coordinate.z * CHUNK_SIZE.z) })

	set_uniform(s_renderer.model_uniform, model)
	renderer_render_mesh(chunk.mesh)
}

renderer_render_world :: proc(world: World) {
	use_shader(get_shader(.Base))
	bind_texture(get_texture(.Stone), 0)
	for chunk in world.chunks do renderer_render_chunk(chunk)
}
