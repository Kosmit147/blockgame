package blockgame

import gl "vendor:OpenGL"

import "core:math/linalg"
import "core:math"
import "core:mem"
import "core:slice"

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
	cube_mesh: Mesh,
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

	create_mesh(&s_renderer.cube_mesh,
		    vertices = slice.to_bytes(cube_vertices[:]),
		    vertex_stride = size_of(Cube_Mesh_Vertex),
		    vertex_format = gl_vertex(Cube_Mesh_Vertex),
		    indices = slice.to_bytes(cube_indices[:]),
		    index_type = gl_index(Cube_Mesh_Index))

	return true
}

renderer_deinit :: proc() {
	destroy_mesh(&s_renderer.cube_mesh)
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

// TODO: Do block highlight properly.
renderer_render_block_highlight :: proc(coordinate: Block_World_Coordinate) {
	gl.Disable(gl.DEPTH_TEST)
	defer gl.Enable(gl.DEPTH_TEST)
	gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
	defer gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)

	// TODO: Remove this lighting hack; use a flat color shader.
	light_data_uniform_buffer_data := Light_Data_Uniform_Buffer_Data {
		light_ambient = WHITE.rgb,
		light_color = WHITE.rgb,
		light_direction = WORLD_DOWN,
	}
	upload_static_gl_buffer_data(s_renderer.light_data_uniform_buffer,
				     mem.any_to_bytes(light_data_uniform_buffer_data))

	use_shader(.Block)
	bind_texture(.White, 0)
	model := linalg.matrix4_translate(linalg.array_cast(coordinate, f32))
	set_uniform(s_renderer.model_uniform, model)
	renderer_render_mesh(s_renderer.cube_mesh)
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

Cube_Mesh_Vertex :: Standard_Vertex
Cube_Mesh_Index  :: u8

@(private="file", rodata)
cube_vertices := [24]Cube_Mesh_Vertex{
	// Front wall.
	{ position = { 0, 0, 1 }, normal = {  0,  0,  1 }, uv = { 0, 1 } },
	{ position = { 1, 0, 1 }, normal = {  0,  0,  1 }, uv = { 1, 1 } },
	{ position = { 1, 1, 1 }, normal = {  0,  0,  1 }, uv = { 1, 0 } },
	{ position = { 0, 1, 1 }, normal = {  0,  0,  1 }, uv = { 0, 0 } },

	// Back wall.
	{ position = { 0, 0, 0 }, normal = {  0,  0, -1 }, uv = { 0, 1 } },
	{ position = { 0, 1, 0 }, normal = {  0,  0, -1 }, uv = { 0, 0 } },
	{ position = { 1, 1, 0 }, normal = {  0,  0, -1 }, uv = { 1, 0 } },
	{ position = { 1, 0, 0 }, normal = {  0,  0, -1 }, uv = { 1, 1 } },

	// Left wall.
	{ position = { 0, 1, 1 }, normal = { -1,  0,  0 }, uv = { 1, 0 } },
	{ position = { 0, 1, 0 }, normal = { -1,  0,  0 }, uv = { 0, 0 } },
	{ position = { 0, 0, 0 }, normal = { -1,  0,  0 }, uv = { 0, 1 } },
	{ position = { 0, 0, 1 }, normal = { -1,  0,  0 }, uv = { 1, 1 } },

	// Right wall.
	{ position = { 1, 1, 1 }, normal = {  1,  0,  0 }, uv = { 0, 0 } },
	{ position = { 1, 0, 1 }, normal = {  1,  0,  0 }, uv = { 0, 1 } },
	{ position = { 1, 0, 0 }, normal = {  1,  0,  0 }, uv = { 1, 1 } },
	{ position = { 1, 1, 0 }, normal = {  1,  0,  0 }, uv = { 1, 0 } },

	// Bottom wall.
	{ position = { 0, 0, 0 }, normal = {  0, -1,  0 }, uv = { 0, 0 } },
	{ position = { 1, 0, 0 }, normal = {  0, -1,  0 }, uv = { 1, 0 } },
	{ position = { 1, 0, 1 }, normal = {  0, -1,  0 }, uv = { 1, 1 } },
	{ position = { 0, 0, 1 }, normal = {  0, -1,  0 }, uv = { 0, 1 } },

	// Top wall.
	{ position = { 0, 1, 0 }, normal = {  0,  1,  0 }, uv = { 0, 0 } },
	{ position = { 0, 1, 1 }, normal = {  0,  1,  0 }, uv = { 0, 1 } },
	{ position = { 1, 1, 1 }, normal = {  0,  1,  0 }, uv = { 1, 1 } },
	{ position = { 1, 1, 0 }, normal = {  0,  1,  0 }, uv = { 1, 0 } },
}

@(private="file", rodata)
cube_indices := [36]Cube_Mesh_Index{
	// Front wall.
	0, 1, 2, 0, 2, 3,

	// Back wall.
	4, 5, 6, 4, 6, 7,

	// Left wall.
	8, 9, 10, 8, 10, 11,

	// Right wall.
	12, 13, 14, 12, 14, 15,

	// Bottom wall.
	16, 17, 18, 16, 18, 19,

	// Top wall.
	20, 21, 22, 20, 22, 23,
}
