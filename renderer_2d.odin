package blockgame

import gl "vendor:OpenGL"

import "easy_font"

import "core:log"
import "core:slice"

SHADER_2D_VERTEX_SOURCE :: #load("2d_shader.vert", cstring)
SHADER_2D_FRAGMENT_SOURCE :: #load("2d_shader.frag", cstring)

Vertex_2D :: struct {
	position: Vec2,
	color: Vec4,
}

VERTEX_2D_FORMAT :: [?]Vertex_Attribute {
	.Float_2,
	.Float_4,
}

@(rodata)
vertex_2d_format := VERTEX_2D_FORMAT

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
	set_vertex_array_format(s_renderer_2d.vertex_array, vertex_2d_format[:])
	create_dynamic_gl_buffer(&s_renderer_2d.vertex_buffer)
	create_dynamic_gl_buffer(&s_renderer_2d.index_buffer)

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
	gl.DrawElements(gl.TRIANGLES, cast(i32)len(s_renderer_2d.indices), gl_index(u32), nil)

	clear(&s_renderer_2d.vertices)
	clear(&s_renderer_2d.indices)
}

// Quads are represented with normalized device coordinates.
Quad :: struct {
	position: Vec2,
	size: Vec2,
	color: Vec4,
}

// Rects are represented with screen coordinates.
Rect :: struct {
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

renderer_2d_submit_rect :: proc(rect: Rect) {
	renderer_2d_submit_quad(Quad {
		position = normalize_screen_position(rect.position),
		size = normalize_screen_size(rect.size),
		color = rect.color,
	})
}

// SLOW IMPLEMENTATION
renderer_2d_submit_text :: proc(text: string, screen_position: Vec2, color := WHITE, scale := f32(1)) {
	quad_buffer: [1000]easy_font.Quad = ---
	quad_count := easy_font.print(screen_position, text, quad_buffer[:], scale)

	for quad in quad_buffer[:quad_count] {
		renderer_2d_submit_quad(Quad {
			position = normalize_screen_position(quad.top_left.position),
			size = normalize_screen_size(quad.bottom_right.position - quad.top_left.position),
			color = color,
		})
	}
}
