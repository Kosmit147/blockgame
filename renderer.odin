package blockgame

import gl "vendor:OpenGL"

import "core:math/linalg"
import "core:math"
import "core:mem"
import "core:slice"
import "core:log"

// These symbols tell GPU drivers to use the dedicated graphics card.
@(export, rodata)
NvOptimusEnablement: u32 = 1
@(export, rodata)
AmdPowerXpressRequestHighPerformance: u32 = 1

Flat_Vertex :: struct {
	position: Vec3,
}

Line_Vertex :: struct {
	position: Vec3,
	color: Vec4,
}

Standard_Vertex :: struct {
	position: Vec3,
	normal: Vec3,
	uv: Vec2,
}

VIEW_PROJECTION_UNIFORM_BUFFER_BINDING_POINT :: 0
LIGHT_DATA_UNIFORM_BUFFER_BINDING_POINT :: 1

Renderer :: struct {
	framebuffer: Framebuffer,
	color_texture: Texture,
	depth_stencil_renderbuffer: Renderbuffer,
	postprocess_vertex_array: Vertex_Array,

	view_projection_uniform_buffer: Gl_Buffer,
	light_data_uniform_buffer: Gl_Buffer,

	block_shader_model_uniform: Uniform(Mat4),
	flat_shader_model_uniform: Uniform(Mat4),
	flat_shader_color_uniform: Uniform(Vec4),

	flat_cube_mesh: Mesh,

	// Not entirely optimal, as there's no need to use indices with lines.
	line_renderer: Batch_Renderer(Line_Vertex),
}

@(private="file")
s_renderer: Renderer

renderer_init :: proc() -> (ok := false) {
	renderer_set_clear_color(BLACK)
	gl.CullFace(gl.BACK)
	gl.FrontFace(gl.CCW)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	// TODO: Handle framebuffer resize.

	create_framebuffer(&s_renderer.framebuffer)
	defer if !ok do destroy_framebuffer(&s_renderer.framebuffer)
	bind_framebuffer(s_renderer.framebuffer)

	window_framebuffer_size := window_framebuffer_size()

	COLOR_TEXTURE_PARAMS :: Texture_Parameters {
		wrap_s = gl.CLAMP_TO_BORDER,
		wrap_t = gl.CLAMP_TO_BORDER,
		min_filter = gl.NEAREST,
		mag_filter = gl.NEAREST,
		border_color = MAGENTA, // We should never see this magenta color.
	}
	s_renderer.color_texture = create_texture(width = cast(u32)window_framebuffer_size.x,
						  height = cast(u32)window_framebuffer_size.y,
						  internal_format = gl.RGBA8,
						  params = COLOR_TEXTURE_PARAMS)
	defer if !ok do destroy_texture(&s_renderer.color_texture)
	attach_texture(s_renderer.framebuffer, s_renderer.color_texture, gl.COLOR_ATTACHMENT0)

	create_renderbuffer(renderbuffer = &s_renderer.depth_stencil_renderbuffer,
			    width = window_framebuffer_size.x,
			    height = window_framebuffer_size.y,
			    format = gl.DEPTH24_STENCIL8)
	defer if !ok do destroy_renderbuffer(&s_renderer.depth_stencil_renderbuffer)
	attach_renderbuffer(s_renderer.framebuffer, s_renderer.depth_stencil_renderbuffer, gl.DEPTH_STENCIL_ATTACHMENT)

	if !framebuffer_is_complete(s_renderer.framebuffer) {
		log.fatal("Main framebuffer is not complete.")
		return
	}

	create_vertex_array(&s_renderer.postprocess_vertex_array)
	defer if !ok do destroy_vertex_array(&s_renderer.postprocess_vertex_array)

	create_static_gl_buffer(&s_renderer.view_projection_uniform_buffer, size_of(View_Projection_Uniform_Buffer_Data))
	defer if !ok do destroy_gl_buffer(&s_renderer.view_projection_uniform_buffer)
	bind_uniform_buffer(s_renderer.view_projection_uniform_buffer, VIEW_PROJECTION_UNIFORM_BUFFER_BINDING_POINT)

	create_static_gl_buffer(&s_renderer.light_data_uniform_buffer, size_of(Light_Data_Uniform_Buffer_Data))
	defer if !ok do destroy_gl_buffer(&s_renderer.light_data_uniform_buffer)
	bind_uniform_buffer(s_renderer.light_data_uniform_buffer, LIGHT_DATA_UNIFORM_BUFFER_BINDING_POINT)

	renderer_get_uniforms()

	create_mesh(&s_renderer.flat_cube_mesh,
		    vertices = slice.to_bytes(flat_cube_vertices[:]),
		    vertex_stride = size_of(Flat_Cube_Mesh_Vertex),
		    vertex_format = gl_vertex(Flat_Cube_Mesh_Vertex),
		    indices = slice.to_bytes(flat_cube_indices[:]),
		    index_type = gl_index(Flat_Cube_Mesh_Index))
	defer if !ok do destroy_mesh(&s_renderer.flat_cube_mesh)

	batch_renderer_init(&s_renderer.line_renderer)
	defer if !ok do batch_renderer_deinit(&s_renderer.line_renderer)

	ok = true
	return
}

renderer_deinit :: proc() {
	batch_renderer_deinit(&s_renderer.line_renderer)

	destroy_mesh(&s_renderer.flat_cube_mesh)
	destroy_gl_buffer(&s_renderer.view_projection_uniform_buffer)
	destroy_gl_buffer(&s_renderer.light_data_uniform_buffer)

	destroy_vertex_array(&s_renderer.postprocess_vertex_array)
	destroy_renderbuffer(&s_renderer.depth_stencil_renderbuffer)
	destroy_texture(&s_renderer.color_texture)
	destroy_framebuffer(&s_renderer.framebuffer)
}

renderer_get_uniforms :: proc() {
	block_shader := get_shader(.Block)
	s_renderer.block_shader_model_uniform = get_uniform(block_shader, "model", Mat4)
	flat_shader := get_shader(.Flat)
	s_renderer.flat_shader_model_uniform = get_uniform(flat_shader, "model", Mat4)
	s_renderer.flat_shader_color_uniform = get_uniform(flat_shader, "color", Vec4)
}

renderer_set_clear_color :: proc(color: Vec4) {
	gl.ClearColor(color.r, color.g, color.b, color.a)
}

renderer_set_line_width :: proc(width: f32) {
	gl.LineWidth(width)
}

renderer_clear :: proc() {
	bind_framebuffer(s_renderer.framebuffer)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)
	bind_default_framebuffer()
	gl.Clear(gl.COLOR_BUFFER_BIT)
}

renderer_begin_2d_frame :: proc() {
	renderer_clear()
	bind_framebuffer(s_renderer.framebuffer)
}

renderer_begin_3d_frame :: proc(camera: Camera, light: Directional_Light) {
	renderer_clear()
	bind_framebuffer(s_renderer.framebuffer)

	gl.Enable(gl.CULL_FACE)
	gl.Enable(gl.DEPTH_TEST)
	gl.Enable(gl.BLEND)

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

renderer_end_frame :: proc() {
	gl.Disable(gl.CULL_FACE)
	gl.Enable(gl.DEPTH_TEST)
	gl.Enable(gl.BLEND)
	batch_renderer_render(&s_renderer.line_renderer, .Lines, primitive_type = gl.LINES)

	gl.Disable(gl.CULL_FACE)
	gl.Disable(gl.DEPTH_TEST)
	gl.Enable(gl.BLEND)
	bind_framebuffer(s_renderer.framebuffer)
	renderer_2d_render()

	gl.Disable(gl.BLEND)
	bind_default_framebuffer()
	use_shader(.Postprocess)
	bind_texture_object(s_renderer.color_texture, 0)
	bind_vertex_array(s_renderer.postprocess_vertex_array)
	gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)
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
	set_uniform(s_renderer.block_shader_model_uniform, model)
	renderer_render_mesh(chunk.mesh)
}

renderer_render_world :: proc(world: World) {
	use_shader(.Block)
	bind_texture(.Blocks, 0)
	for _, &chunk in world.chunk_map do renderer_render_chunk(chunk)
}

renderer_render_block_highlight :: proc(coordinate: Block_World_Coordinate) {
	HIGHLIGHT_COLOR :: WHITE

	gl.Disable(gl.DEPTH_TEST)
	defer gl.Enable(gl.DEPTH_TEST)
	gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE)
	defer gl.PolygonMode(gl.FRONT_AND_BACK, gl.FILL)

	use_shader(.Flat)
	model := linalg.matrix4_translate(linalg.array_cast(coordinate, f32))
	set_uniform(s_renderer.flat_shader_model_uniform, model)
	set_uniform(s_renderer.flat_shader_color_uniform, HIGHLIGHT_COLOR)
	renderer_render_mesh(s_renderer.flat_cube_mesh)
}

renderer_render_line :: proc(vertices: ^[2]Line_Vertex) {
	batch_renderer_submit_line(&s_renderer.line_renderer, vertices)
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

Flat_Cube_Mesh_Vertex :: Flat_Vertex
Flat_Cube_Mesh_Index  :: u8

@(private="file", rodata)
flat_cube_vertices := [24]Flat_Cube_Mesh_Vertex{
	// Front wall.
	{ position = { 0, 0, 1 } },
	{ position = { 1, 0, 1 } },
	{ position = { 1, 1, 1 } },
	{ position = { 0, 1, 1 } },

	// Back wall.
	{ position = { 0, 0, 0 } },
	{ position = { 0, 1, 0 } },
	{ position = { 1, 1, 0 } },
	{ position = { 1, 0, 0 } },

	// Left wall.
	{ position = { 0, 1, 1 } },
	{ position = { 0, 1, 0 } },
	{ position = { 0, 0, 0 } },
	{ position = { 0, 0, 1 } },

	// Right wall.
	{ position = { 1, 1, 1 } },
	{ position = { 1, 0, 1 } },
	{ position = { 1, 0, 0 } },
	{ position = { 1, 1, 0 } },

	// Bottom wall.
	{ position = { 0, 0, 0 } },
	{ position = { 1, 0, 0 } },
	{ position = { 1, 0, 1 } },
	{ position = { 0, 0, 1 } },

	// Top wall.
	{ position = { 0, 1, 0 } },
	{ position = { 0, 1, 1 } },
	{ position = { 1, 1, 1 } },
	{ position = { 1, 1, 0 } },
}

@(private="file", rodata)
flat_cube_indices := [36]Flat_Cube_Mesh_Index{
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
