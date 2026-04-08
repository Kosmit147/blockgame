package blockgame

import gl "vendor:OpenGL"

import "core:slice"

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

batch_renderer_render :: proc(renderer: ^Batch_Renderer($Vertex),
			      shader: Shader_Id,
			      texture: Maybe(Texture_Id) = nil,
			      primitive_type: u32 = gl.TRIANGLES) {
	if len(renderer.vertices) == 0 do return

	use_shader(shader)
	if texture, texture_present := texture.?; texture_present {
		bind_texture(texture, 0)
	}

	upload_dynamic_gl_buffer_data(&renderer.vertex_buffer, slice.to_bytes(renderer.vertices[:]))
	upload_dynamic_gl_buffer_data(&renderer.index_buffer, slice.to_bytes(renderer.indices[:]))
	bind_vertex_array(renderer.vertex_array)
	gl.DrawElements(primitive_type, cast(i32)len(renderer.indices), gl_index(Batch_Renderer_Index), nil)
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

batch_renderer_submit_line :: proc(renderer: ^Batch_Renderer($Vertex), vertices: ^[2]Vertex) {
	index_offset := cast(Batch_Renderer_Index)len(renderer.vertices)
	append(&renderer.vertices, ..vertices[:])
	append(&renderer.indices,
	       index_offset + 0,
	       index_offset + 1)
}
