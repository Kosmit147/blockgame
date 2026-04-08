package blockgame

import "vendor/easy_font"

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
	// Creating a separate batch renderer for every texture is a bit wasteful, as the only thing that changes per
	// texture is the set of vertices and indices.
	textured_quad_renderers: [Texture_Id]Batch_Renderer(Textured_Quad_Vertex),
}

@(private="file")
s_renderer_2d: Renderer_2D

renderer_2d_init :: proc() -> (ok := false) {
	batch_renderer_init(&s_renderer_2d.quad_renderer)
	for &renderer in s_renderer_2d.textured_quad_renderers do batch_renderer_init(&renderer)
	ok = true
	return
}

renderer_2d_deinit :: proc() {
	batch_renderer_deinit(&s_renderer_2d.quad_renderer)
	for &renderer in s_renderer_2d.textured_quad_renderers do batch_renderer_deinit(&renderer)
}

renderer_2d_render :: proc() {
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

@(require_results)
renderer_2d_text_width :: proc(text: string, scale := f32(1)) -> f32 {
	return cast(f32)easy_font.width(text) * scale
}

@(require_results)
renderer_2d_text_height :: proc(text: string, scale := f32(1)) -> f32 {
	return cast(f32)easy_font.height(text) * scale
}

@(require_results)
renderer_2d_text_size :: proc(text: string, scale := f32(1)) -> Vec2 {
	return Vec2{ renderer_2d_text_width(text, scale), renderer_2d_text_height(text, scale) }
}
