package blockgame

import gl "vendor:OpenGL"

import "core:math/linalg"
import "core:math"
import "core:mem"

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

VIEW_PROJECTION_UNIFORM_BUFFER_BINDING_POINT :: 0
LIGHT_DATA_UNIFORM_BUFFER_BINDING_POINT :: 1

Renderer :: struct {
	view_projection_uniform_buffer: Gl_Buffer,
	light_data_uniform_buffer: Gl_Buffer,
	model_uniform: Uniform(Mat4),
}

@(private="file")
s_renderer: Renderer

renderer_init :: proc() -> (ok := false) {
	gl.ClearColor(0, 0, 0, 1)
	gl.Enable(gl.CULL_FACE)
	gl.CullFace(gl.BACK)
	gl.FrontFace(gl.CCW)
	gl.Enable(gl.DEPTH_TEST)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	create_static_gl_buffer(&s_renderer.view_projection_uniform_buffer, size_of(View_Projection_Uniform_Buffer_Data))
	bind_uniform_buffer(s_renderer.view_projection_uniform_buffer, VIEW_PROJECTION_UNIFORM_BUFFER_BINDING_POINT)
	create_static_gl_buffer(&s_renderer.light_data_uniform_buffer, size_of(Light_Data_Uniform_Buffer_Data))
	bind_uniform_buffer(s_renderer.light_data_uniform_buffer, LIGHT_DATA_UNIFORM_BUFFER_BINDING_POINT)

	renderer_get_uniforms()

	return true
}

renderer_deinit :: proc() {
	destroy_gl_buffer(&s_renderer.view_projection_uniform_buffer)
	destroy_gl_buffer(&s_renderer.light_data_uniform_buffer)
}

renderer_get_uniforms :: proc() {
	shader := get_shader(.Block)
	s_renderer.model_uniform = get_uniform(shader, "model", Mat4)
}

renderer_set_clear_color :: proc(color: Vec4) {
	gl.ClearColor(color.r, color.g, color.b, color.a)
}

renderer_clear :: proc() {
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
}

renderer_begin_frame :: proc(camera: Camera, light: Directional_Light) {
	camera_vectors := camera_vectors(camera)

	view := linalg.matrix4_look_at(eye = camera.position,
				       centre = camera.position + camera_vectors.forward,
				       up = camera_vectors.up)
	projection := linalg.matrix4_perspective(fovy = math.to_radians(f32(45)),
						 aspect = window_aspect_ratio(),
						 near = 0.1,
						 far = 1000)

	view_projection_uniform_buffer_data := View_Projection_Uniform_Buffer_Data { view, projection }
	upload_static_gl_buffer_data(s_renderer.view_projection_uniform_buffer,
				     mem.any_to_bytes(view_projection_uniform_buffer_data))
	light_data_uniform_buffer_data := Light_Data_Uniform_Buffer_Data {
		light_ambient = light.ambient,
		light_color = light.color,
		light_direction = light.direction,
	}
	upload_static_gl_buffer_data(s_renderer.light_data_uniform_buffer,
				     mem.any_to_bytes(light_data_uniform_buffer_data))
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
	use_shader(.Block)
	bind_texture(.Blocks, 0)
	for _, &chunk in world.chunk_map do renderer_render_chunk(chunk)
}

View_Projection_Uniform_Buffer_Data :: struct {
	view: Mat4,
	projection: Mat4,
}

Light_Data_Uniform_Buffer_Data :: struct {
	light_ambient: Vec3,
	_: [4]byte,
	light_color: Vec3,
	_: [4]byte,
	light_direction: Vec3,
}
