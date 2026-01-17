package blockgame

import gl "vendor:OpenGL"

import "core:log"
import "core:slice"
import "core:math/linalg"
import "core:math"

// These symbols tell GPU drivers to use the dedicated graphics card.
@(export, rodata)
NvOptimusEnablement: u32 = 1
@(export, rodata)
AmdPowerXpressRequestHighPerformance: u32 = 1

SHADER_VERTEX_SOURCE :: #load("shader_vertex.glsl", cstring)
SHADER_FRAGMENT_SOURCE :: #load("shader_fragment.glsl", cstring)

COBBLE_TEXTURE_FILE_DATA :: #load("cobble.png")

Vertex :: struct {
	position: Vec3,
	normal: Vec3,
	uv: Vec2,
}

VERTEX_FORMAT :: [?]Vertex_Attribute{
	.Float_3,
	.Float_3,
	.Float_2,
}

@(private="file", rodata)
vertices := [24]Vertex{
	// Front wall.
	{ position = { -0.5, -0.5,  0.5 }, normal = {  0,  0,  1 }, uv = { 0, 0 } },
	{ position = {  0.5, -0.5,  0.5 }, normal = {  0,  0,  1 }, uv = { 1, 0 } },
	{ position = {  0.5,  0.5,  0.5 }, normal = {  0,  0,  1 }, uv = { 1, 1 } },
	{ position = { -0.5,  0.5,  0.5 }, normal = {  0,  0,  1 }, uv = { 0, 1 } },

	// Back wall.
	{ position = { -0.5, -0.5, -0.5 }, normal = {  0,  0, -1 }, uv = { 0, 0 } },
	{ position = { -0.5,  0.5, -0.5 }, normal = {  0,  0, -1 }, uv = { 0, 1 } },
	{ position = {  0.5,  0.5, -0.5 }, normal = {  0,  0, -1 }, uv = { 1, 1 } },
	{ position = {  0.5, -0.5, -0.5 }, normal = {  0,  0, -1 }, uv = { 1, 0 } },

	// Left wall.
	{ position = { -0.5,  0.5,  0.5 }, normal = { -1,  0,  0 }, uv = { 1, 0 } },
	{ position = { -0.5,  0.5, -0.5 }, normal = { -1,  0,  0 }, uv = { 1, 1 } },
	{ position = { -0.5, -0.5, -0.5 }, normal = { -1,  0,  0 }, uv = { 0, 1 } },
	{ position = { -0.5, -0.5,  0.5 }, normal = { -1,  0,  0 }, uv = { 0, 0 } },

	// Right wall.
	{ position = {  0.5,  0.5,  0.5 }, normal = {  1,  0,  0 }, uv = { 1, 0 } },
	{ position = {  0.5, -0.5,  0.5 }, normal = {  1,  0,  0 }, uv = { 0, 0 } },
	{ position = {  0.5, -0.5, -0.5 }, normal = {  1,  0,  0 }, uv = { 0, 1 } },
	{ position = {  0.5,  0.5, -0.5 }, normal = {  1,  0,  0 }, uv = { 1, 1 } },

	// Bottom wall.
	{ position = { -0.5, -0.5, -0.5 }, normal = {  0, -1,  0 }, uv = { 0, 1 } },
	{ position = {  0.5, -0.5, -0.5 }, normal = {  0, -1,  0 }, uv = { 1, 1 } },
	{ position = {  0.5, -0.5,  0.5 }, normal = {  0, -1,  0 }, uv = { 1, 0 } },
	{ position = { -0.5, -0.5,  0.5 }, normal = {  0, -1,  0 }, uv = { 0, 0 } },

	// Top wall.
	{ position = { -0.5,  0.5, -0.5 }, normal = {  0,  1,  0 }, uv = { 0, 1 } },
	{ position = { -0.5,  0.5,  0.5 }, normal = {  0,  1,  0 }, uv = { 0, 0 } },
	{ position = {  0.5,  0.5,  0.5 }, normal = {  0,  1,  0 }, uv = { 1, 0 } },
	{ position = {  0.5,  0.5, -0.5 }, normal = {  0,  1,  0 }, uv = { 1, 1 } },
}

@(private="file", rodata)
indices := [36]u16{
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

Renderer :: struct {
	shader: Shader,
	model_uniform: Uniform(Mat4),
	view_uniform: Uniform(Mat4),
	projection_uniform: Uniform(Mat4),

	texture: Texture,

	vertex_array: Vertex_Array,
	vertex_buffer: Gl_Buffer,
	index_buffer: Gl_Buffer,
}

@(private="file")
s_renderer: Renderer

renderer_init :: proc() -> (ok := false) {
	gl.Enable(gl.CULL_FACE)
	gl.CullFace(gl.BACK)
	gl.FrontFace(gl.CCW)
	gl.Enable(gl.DEPTH_TEST)

	s_renderer.shader, ok = create_shader(SHADER_VERTEX_SOURCE, SHADER_FRAGMENT_SOURCE) 
	if !ok {
		log.fatal("Failed to compile the base shader.")
		return
	}
	defer if !ok do destroy_shader(s_renderer.shader)

	s_renderer.model_uniform = get_uniform(s_renderer.shader, "model", Mat4)
	s_renderer.view_uniform = get_uniform(s_renderer.shader, "view", Mat4)
	s_renderer.projection_uniform = get_uniform(s_renderer.shader, "projection", Mat4)

	s_renderer.texture, ok = create_texture_from_png_in_memory(COBBLE_TEXTURE_FILE_DATA)
	if !ok {
		log.fatal("Failed to load the texture.")
		return
	}
	defer if !ok do destroy_texture(&s_renderer.texture)
	bind_texture(s_renderer.texture, 0)

	// From this point onwards we cannot fail, so we don't have to set up any more cleanup.
	create_vertex_array(&s_renderer.vertex_array)
	set_vertex_array_format(s_renderer.vertex_array, VERTEX_FORMAT)
	create_static_gl_buffer_with_data(&s_renderer.vertex_buffer, slice.to_bytes(vertices[:]))
	create_static_gl_buffer_with_data(&s_renderer.index_buffer, slice.to_bytes(indices[:]))

	bind_vertex_array(s_renderer.vertex_array)
	bind_vertex_buffer(s_renderer.vertex_array, s_renderer.vertex_buffer, size_of(Vertex))
	bind_index_buffer(s_renderer.vertex_array, s_renderer.index_buffer)

	ok = true
	return
}

renderer_deinit :: proc() {
	destroy_gl_buffer(&s_renderer.index_buffer)
	destroy_gl_buffer(&s_renderer.vertex_buffer)
	destroy_vertex_array(&s_renderer.vertex_array)
	destroy_texture(&s_renderer.texture)
	destroy_shader(s_renderer.shader)
}

renderer_render :: proc(camera: Camera, cube_position: Vec3) {
	gl.ClearColor(0, 0, 0, 1)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

	camera_vectors := camera_vectors(camera)

	model := linalg.matrix4_translate(cube_position)

	view := linalg.matrix4_look_at(eye = camera.position,
				       centre = camera.position + camera_vectors.forward,
				       up = camera_vectors.up)

	projection := linalg.matrix4_perspective(fovy = math.to_radians(f32(45)),
						 aspect = window_aspect_ratio(),
						 near = 0.1,
						 far = 100)

	use_shader(s_renderer.shader)
	set_uniform(s_renderer.model_uniform, model)
	set_uniform(s_renderer.view_uniform, view)
	set_uniform(s_renderer.projection_uniform, projection)

	bind_vertex_array(s_renderer.vertex_array)
	gl.DrawElements(gl.TRIANGLES, len(indices), gl.UNSIGNED_SHORT, nil)
}

SHADER_2D_VERTEX_SOURCE :: #load("shader_2d_vertex.glsl", cstring)
SHADER_2D_FRAGMENT_SOURCE :: #load("shader_2d_fragment.glsl", cstring)

Vertex_2D :: struct {
	position: Vec2,
	color: Vec4,
}

VERTEX_2D_FORMAT :: [?]Vertex_Attribute{
	.Float_2,
	.Float_4,
}

Renderer_2D :: struct {
	shader: Shader,

	vertex_array: Vertex_Array,
	vertex_buffer: Gl_Buffer,
	index_buffer: Gl_Buffer,

	vertices: [dynamic]Vertex_2D,
	indices: [dynamic]u32,
}

@(private="file")
s_renderer_2d: Renderer_2D

renderer_2d_init :: proc() -> (ok := false) {
	s_renderer_2d.shader, ok = create_shader(SHADER_2D_VERTEX_SOURCE, SHADER_2D_FRAGMENT_SOURCE) 
	if !ok {
		log.fatal("Failed to compile the 2D shader.")
		return
	}
	defer if !ok do destroy_shader(s_renderer_2d.shader)

	// From this point onwards we cannot fail, so we don't have to set up any more cleanup.
	create_vertex_array(&s_renderer_2d.vertex_array)
	set_vertex_array_format(s_renderer_2d.vertex_array, VERTEX_2D_FORMAT)
	create_dynamic_gl_buffer(&s_renderer_2d.vertex_buffer)
	create_dynamic_gl_buffer(&s_renderer_2d.index_buffer)

	bind_vertex_array(s_renderer_2d.vertex_array)
	bind_vertex_buffer(s_renderer_2d.vertex_array, s_renderer_2d.vertex_buffer, size_of(Vertex_2D))
	bind_index_buffer(s_renderer_2d.vertex_array, s_renderer_2d.index_buffer)

	ok = true
	return
}

renderer_2d_deinit :: proc() {
	delete(s_renderer_2d.indices)
	delete(s_renderer_2d.vertices)

	destroy_gl_buffer(&s_renderer_2d.index_buffer)
	destroy_gl_buffer(&s_renderer_2d.vertex_buffer)
	destroy_vertex_array(&s_renderer_2d.vertex_array)
	destroy_shader(s_renderer_2d.shader)
}

renderer_2d_render :: proc() {
	gl.Disable(gl.DEPTH_TEST)
	defer gl.Enable(gl.DEPTH_TEST)

	upload_dynamic_gl_buffer_data(&s_renderer_2d.vertex_buffer, slice.to_bytes(s_renderer_2d.vertices[:]))
	upload_dynamic_gl_buffer_data(&s_renderer_2d.index_buffer, slice.to_bytes(s_renderer_2d.indices[:]))

	use_shader(s_renderer_2d.shader)
	bind_vertex_array(s_renderer_2d.vertex_array)
	gl.DrawElements(gl.TRIANGLES, cast(i32)len(s_renderer_2d.indices), gl.UNSIGNED_INT, nil)

	clear(&s_renderer_2d.vertices)
	clear(&s_renderer_2d.indices)
}

Quad :: struct {
	position: Vec2,
	size: Vec2,
	color: Vec4,
}

renderer_2d_submit_quad :: proc(quad: Quad) {
	index_offset := cast(u32)len(s_renderer_2d.vertices)

	v1 := Vertex_2D{ position = quad.position, color = quad.color }
	v2 := Vertex_2D{ position = quad.position + { quad.size.x, 0 }, color = quad.color }
	v3 := Vertex_2D{ position = quad.position + { quad.size.x, -quad.size.y }, color = quad.color }
	v4 := Vertex_2D{ position = quad.position + { 0, -quad.size.y }, color = quad.color }
	append(&s_renderer_2d.vertices, v1, v2, v3, v4)

	append(&s_renderer_2d.indices,
	       index_offset + 0,
	       index_offset + 3,
	       index_offset + 2,
	       index_offset + 0,
	       index_offset + 2,
	       index_offset + 1)
}
