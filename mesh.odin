package blockgame

import "core:slice"

Mesh :: struct {
	vertex_array: Vertex_Array,
	buffer: Gl_Buffer, // Contains both the vertices and indices.
	vertex_count: u32,
	index_type: u32,
	index_data_offset: u32,
}

create_mesh :: proc(mesh: ^Mesh,
		    vertices: []byte,
		    vertex_stride: u32,
		    vertex_format: []Vertex_Attribute,
		    indices: []byte,
		    index_type: u32) {
	vertex_data_offset := 0
	index_data_offset := slice.size(vertices[:])
	buffer_size := slice.size(vertices[:]) + slice.size(indices[:])

	create_static_gl_buffer(&mesh.buffer, buffer_size)
	upload_static_gl_buffer_data(mesh.buffer, slice.to_bytes(vertices[:]), vertex_data_offset)
	upload_static_gl_buffer_data(mesh.buffer, slice.to_bytes(indices[:]), index_data_offset)

	mesh.vertex_count = cast(u32)len(indices)
	mesh.index_type = index_type
	mesh.index_data_offset = cast(u32)index_data_offset

	create_vertex_array(&mesh.vertex_array)
	set_vertex_array_format(mesh.vertex_array, vertex_format)
	bind_vertex_buffer(mesh.vertex_array, mesh.buffer, i32(vertex_stride))
	bind_index_buffer(mesh.vertex_array, mesh.buffer)
}

destroy_mesh :: proc(mesh: ^Mesh) {
	destroy_vertex_array(&mesh.vertex_array)
	destroy_gl_buffer(&mesh.buffer)
}

bind_mesh :: proc(mesh: Mesh) {
	bind_vertex_array(mesh.vertex_array)
}
