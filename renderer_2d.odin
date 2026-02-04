package blockgame

import gl "vendor:OpenGL"

import "easy_font"

import "core:slice"

Quad_Vertex :: struct {
	position: Vec2,
	color: Vec4,
}

Textured_Quad_Vertex :: struct {
	position: Vec2,
	uv: Vec2,
	tint: Vec4,
}

Renderer_2D :: struct {
	quad_renderer: Batch_Renderer(Quad_Vertex),
	// Creating separate batch renderer for every texture is a bit wasteful, as the only thing that changes per
	// texture is the set of vertices and indices.
	textured_quad_renderers: [Texture_Id]Batch_Renderer(Textured_Quad_Vertex),
}

@(private="file")
s_renderer_2d: Renderer_2D

renderer_2d_init :: proc() -> bool {
	batch_renderer_init(&s_renderer_2d.quad_renderer)
	for &renderer in s_renderer_2d.textured_quad_renderers do batch_renderer_init(&renderer)
	return true
}

renderer_2d_deinit :: proc() {
	batch_renderer_deinit(&s_renderer_2d.quad_renderer)
	for &renderer in s_renderer_2d.textured_quad_renderers do batch_renderer_deinit(&renderer)
}

renderer_2d_render :: proc() {
	gl.Disable(gl.DEPTH_TEST)
	defer gl.Enable(gl.DEPTH_TEST)

	batch_renderer_render(&s_renderer_2d.quad_renderer, .Quad, nil)
	for &renderer, texture in s_renderer_2d.textured_quad_renderers {
		batch_renderer_render(&renderer, .Textured_Quad, texture)
	}
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
	vertices := [4]Quad_Vertex {
		{ position = quad.position,                                 color = quad.color },
		{ position = quad.position + { quad.size.x, 0 },            color = quad.color },
		{ position = quad.position + { quad.size.x, -quad.size.y }, color = quad.color },
		{ position = quad.position + { 0, -quad.size.y },           color = quad.color },
	}
	batch_renderer_submit_quad(&s_renderer_2d.quad_renderer, &vertices)
}

renderer_2d_submit_textured_quad :: proc(quad: Quad, texture: Texture_Id) {
	vertices := [4]Textured_Quad_Vertex {
		{ position = quad.position,                                 uv = Vec2{ 0, 0 }, tint = quad.color },
		{ position = quad.position + { quad.size.x, 0 },            uv = Vec2{ 1, 0 }, tint = quad.color },
		{ position = quad.position + { quad.size.x, -quad.size.y }, uv = Vec2{ 1, 1 }, tint = quad.color },
		{ position = quad.position + { 0, -quad.size.y },           uv = Vec2{ 0, 1 }, tint = quad.color },
	}
	batch_renderer_submit_quad(&s_renderer_2d.textured_quad_renderers[texture], &vertices)
}

renderer_2d_submit_rect :: proc(rect: Rect) {
	renderer_2d_submit_quad(Quad {
		position = normalize_screen_position(rect.position),
		size = normalize_screen_size(rect.size),
		color = rect.color,
	})
}

renderer_2d_submit_textured_rect :: proc(rect: Rect, texture: Texture_Id) {
	renderer_2d_submit_textured_quad(Quad {
		position = normalize_screen_position(rect.position),
		size = normalize_screen_size(rect.size),
		color = rect.color,
	}, texture)
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

Batch_Renderer_Index :: u32

Batch_Renderer :: struct($Vertex: typeid) {
	vertex_array: Vertex_Array,
	vertex_buffer: Gl_Buffer,
	index_buffer: Gl_Buffer,
	vertices: [dynamic]Vertex,
	indices: [dynamic]Batch_Renderer_Index,
}

batch_renderer_init :: proc(renderer: ^Batch_Renderer($Vertex)) {
	create_vertex_array(&renderer.vertex_array)
	set_vertex_array_format(renderer.vertex_array, gl_vertex(Vertex))
	create_dynamic_gl_buffer(&renderer.vertex_buffer)
	create_dynamic_gl_buffer(&renderer.index_buffer)
	bind_vertex_buffer(renderer.vertex_array, renderer.vertex_buffer, size_of(Vertex))
	bind_index_buffer(renderer.vertex_array, renderer.index_buffer)
}

batch_renderer_deinit :: proc(renderer: ^Batch_Renderer($Vertex)) {
	delete(renderer.indices)
	delete(renderer.vertices)
	destroy_gl_buffer(&renderer.index_buffer)
	destroy_gl_buffer(&renderer.vertex_buffer)
	destroy_vertex_array(&renderer.vertex_array)
}

batch_renderer_render :: proc(renderer: ^Batch_Renderer($Vertex), shader: Shader_Id, texture: Maybe(Texture_Id) = nil) {
	if len(renderer.vertices) == 0 do return

	use_shader(shader)
	if texture, texture_present := texture.?; texture_present {
		bind_texture(texture, 0)
	}

	upload_dynamic_gl_buffer_data(&renderer.vertex_buffer, slice.to_bytes(renderer.vertices[:]))
	upload_dynamic_gl_buffer_data(&renderer.index_buffer, slice.to_bytes(renderer.indices[:]))
	bind_vertex_array(renderer.vertex_array)
	gl.DrawElements(gl.TRIANGLES, cast(i32)len(renderer.indices), gl_index(Batch_Renderer_Index), nil)
	clear(&renderer.vertices)
	clear(&renderer.indices)
}

batch_renderer_submit_quad :: proc(renderer: ^Batch_Renderer($Vertex), vertices: ^[4]Vertex) {
	index_offset := cast(Batch_Renderer_Index)len(renderer.vertices)
	append(&renderer.vertices, ..vertices[:])
	append(&renderer.indices,
	       index_offset + 0,
	       index_offset + 3,
	       index_offset + 2,
	       index_offset + 0,
	       index_offset + 2,
	       index_offset + 1)
}
