package blockgame

import gl "vendor:OpenGL"

import "easy_font"

import "core:slice"

Vertex_2D :: struct {
	position: Vec2,
	color: Vec4,
}

Renderer_2D :: struct {
	vertex_array: Vertex_Array,
	vertex_buffer: Gl_Buffer,
	index_buffer: Gl_Buffer,

	vertices: [dynamic]Vertex_2D,
	indices: [dynamic]u32,
}

@(private="file")
s_renderer_2d: Renderer_2D

renderer_2d_init :: proc() -> bool {
	create_vertex_array(&s_renderer_2d.vertex_array)
	set_vertex_array_format(s_renderer_2d.vertex_array, gl_vertex(Vertex_2D))
	create_dynamic_gl_buffer(&s_renderer_2d.vertex_buffer)
	create_dynamic_gl_buffer(&s_renderer_2d.index_buffer)

	bind_vertex_buffer(s_renderer_2d.vertex_array, s_renderer_2d.vertex_buffer, size_of(Vertex_2D))
	bind_index_buffer(s_renderer_2d.vertex_array, s_renderer_2d.index_buffer)

	return true
}

renderer_2d_deinit :: proc() {
	delete(s_renderer_2d.indices)
	delete(s_renderer_2d.vertices)

	destroy_gl_buffer(&s_renderer_2d.index_buffer)
	destroy_gl_buffer(&s_renderer_2d.vertex_buffer)
	destroy_vertex_array(&s_renderer_2d.vertex_array)
}

renderer_2d_render :: proc() {
	gl.Disable(gl.DEPTH_TEST)
	defer gl.Enable(gl.DEPTH_TEST)

	upload_dynamic_gl_buffer_data(&s_renderer_2d.vertex_buffer, slice.to_bytes(s_renderer_2d.vertices[:]))
	upload_dynamic_gl_buffer_data(&s_renderer_2d.index_buffer, slice.to_bytes(s_renderer_2d.indices[:]))

	use_shader(get_shader(.D2))
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
