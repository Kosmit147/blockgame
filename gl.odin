package blockgame

import gl "vendor:OpenGL"
import ase "vendor/odin-aseprite"
import ase_utils "vendor/odin-aseprite/utils"

import "base:intrinsics"
import "base:runtime"

import "core:log"
import "core:bytes"
import "core:strings"
import "core:slice"
import "core:image"
import "core:image/png"
import "core:reflect"
import "core:os"
import "core:path/filepath"

gl_index :: proc($I: typeid) -> u32 {
	when I == u8 {
		return gl.UNSIGNED_BYTE
	} else when I == u16 {
		return gl.UNSIGNED_SHORT
	} else when I == u32 {
		return gl.UNSIGNED_INT
	} else {
		#panic("T cannot be used for indexing in OpenGL.")
	}
}

@(private="file")
gl_vertex_attribute :: proc(type_info: ^runtime.Type_Info) -> Vertex_Attribute {
	type_info := runtime.type_info_base(type_info)

	ASSERT_MESSAGE :: "only arrays of 32-bit floats are supported"
	array_type_info, is_array := type_info.variant.(runtime.Type_Info_Array)
	assert(is_array, ASSERT_MESSAGE)
	elem_type_info := runtime.type_info_base(array_type_info.elem)
	assert(elem_type_info.size == size_of(f32), ASSERT_MESSAGE)
	_, is_float := elem_type_info.variant.(runtime.Type_Info_Float)
	assert(is_float, ASSERT_MESSAGE)

	switch array_type_info.count {
	case 1: return .Float_1
	case 2: return .Float_2
	case 3: return .Float_3
	case 4: return .Float_4
	}

	assert(false, "shouldn't be possible to get here")
	return nil
}

gl_vertex :: proc($V: typeid) -> []Vertex_Attribute {
	@(static) attributes: [intrinsics.type_struct_field_count(V)]Vertex_Attribute
	field_types := reflect.struct_field_types(V)
	for type, i in field_types do attributes[i] = gl_vertex_attribute(type)
	return attributes[:]
}

Shader :: struct {
	id: u32,
}

create_shader :: proc(vertex_source, fragment_source: string) -> (shader: Shader, ok := false) {
	vertex_shader := create_sub_shader(vertex_source, gl.VERTEX_SHADER) or_return
	defer gl.DeleteShader(vertex_shader)
	fragment_shader := create_sub_shader(fragment_source, gl.FRAGMENT_SHADER) or_return
	defer gl.DeleteShader(fragment_shader)
	shader.id = link_shader_program(vertex_shader, fragment_shader) or_return
	return shader, true
}

create_shader_from_files :: proc(vertex_path, fragment_path: string) -> (shader: Shader, ok := false) {
	vertex_source := cast(string)os.read_entire_file(vertex_path, context.temp_allocator) or_return
	fragment_source := cast(string)os.read_entire_file(fragment_path, context.temp_allocator) or_return
	return create_shader(vertex_source, fragment_source)
}

destroy_shader :: proc(shader: Shader) {
	gl.DeleteProgram(shader.id)
}

use_shader_object :: proc(shader: Shader) {
	gl.UseProgram(shader.id)
}

use_shader :: proc(id: Shader_Id) {
	use_shader_object(get_shader(id))
}

@(private="file")
create_sub_shader :: proc(shader_source: string, shader_type: u32) -> (u32, bool) {
	shader_type_string :: proc(type: u32) -> string {
		switch type {
		case gl.VERTEX_SHADER: return "vertex"
		case gl.FRAGMENT_SHADER: return "fragment"
		}

		assert(false)
		return "ERROR - unknown shader type"
	}

	sources_array := [1]cstring{ cast(cstring)raw_data(shader_source) }
	lengths_array := [1]i32{ cast(i32)len(shader_source) }

	shader := gl.CreateShader(shader_type)
	gl.ShaderSource(shader, 1, raw_data(sources_array[:]), raw_data(lengths_array[:]))

	gl.CompileShader(shader)
	is_compiled: i32

	if gl.GetShaderiv(shader, gl.COMPILE_STATUS, &is_compiled); is_compiled == gl.FALSE {
		info_log_length: i32
		gl.GetShaderiv(shader, gl.INFO_LOG_LENGTH, &info_log_length)

		info_log_buffer := make([]byte, info_log_length, context.temp_allocator)

		gl.GetShaderInfoLog(shader, info_log_length, nil, raw_data(info_log_buffer))
		info_log := string(info_log_buffer)
		info_log = strings.trim_null(info_log)

		log.errorf("Failed to compile %v shader: %v", shader_type_string(shader_type), info_log)

		gl.DeleteShader(shader)
		return gl.NONE, false
	}

	return shader, true
}

@(private="file")
link_shader_program :: proc(vertex_shader, fragment_shader: u32) -> (u32, bool) {
	program := gl.CreateProgram()

	gl.AttachShader(program, vertex_shader)
	gl.AttachShader(program, fragment_shader)

	gl.LinkProgram(program)
	is_linked: i32

	if gl.GetProgramiv(program, gl.LINK_STATUS, &is_linked); is_linked == gl.FALSE {
		info_log_length: i32
		gl.GetProgramiv(program, gl.INFO_LOG_LENGTH, &info_log_length)

		info_log_buffer := make([]byte, info_log_length, context.temp_allocator)

		gl.GetProgramInfoLog(program, info_log_length, nil, raw_data(info_log_buffer))
		info_log := string(info_log_buffer)
		info_log = strings.trim_null(info_log)

		log.errorf("Failed to link shader: %v", info_log)

		gl.DeleteProgram(program)
		return gl.NONE, false
	}

	gl.DetachShader(program, vertex_shader)
	gl.DetachShader(program, fragment_shader)

	return program, true
}

Uniform :: struct($T: typeid) {
	location: i32,
}

get_uniform :: proc(shader: Shader, uniform: cstring, $T: typeid) -> (Uniform(T), bool) #optional_ok {
	location := gl.GetUniformLocation(shader.id, uniform)

	when ODIN_DEBUG {
		if location == -1 do log.warnf("Uniform \"%v\" does not exist!", uniform)
	}

	return Uniform(T) { location }, location != -1
}

set_uniform :: proc(uniform: Uniform($T), value: T) {
	location := uniform.location
	when ODIN_DEBUG { assert(location != -1) }

	when T == i32 {
		gl.Uniform1i(location, value)
	} else when T == Vec2 {
		gl.Uniform2f(location, value.x, value.y)
	} else when T == Vec3 {
		gl.Uniform3f(location, value.x, value.y, value.z)
	} else when T == Vec4 {
		gl.Uniform4f(location, value.x, value.y, value.z, value.w)
	} else when T == Mat4 {
		value := value
		gl.UniformMatrix4fv(location, 1, false, raw_data(&value))
	} else {
 		#panic("Type T not implemented for set_uniform.")
	}
}

Vertex_Array :: struct {
	id: u32,
}

create_vertex_array :: proc(va: ^Vertex_Array) {
	gl.CreateVertexArrays(1, &va.id)
}

destroy_vertex_array :: proc(va: ^Vertex_Array) {
	gl.DeleteVertexArrays(1, &va.id)
}

bind_vertex_array :: proc(va: Vertex_Array) {
	gl.BindVertexArray(va.id)
}

Vertex_Attribute :: enum {
	Float_1,
	Float_2,
	Float_3,
	Float_4,
}

Vertex_Attribute_Description :: struct {
	count: i32,
	type: u32,
	size: u32,
}

describe_vertex_attribute :: proc(attribute: Vertex_Attribute) -> Vertex_Attribute_Description {
	switch attribute {
	case .Float_1:
		return { 1, gl.FLOAT, 1 * size_of(f32) }
	case .Float_2:
		return { 2, gl.FLOAT, 2 * size_of(f32) }
	case .Float_3:
		return { 3, gl.FLOAT, 3 * size_of(f32) }
	case .Float_4:
		return { 4, gl.FLOAT, 4 * size_of(f32) }
	case:
		assert(false)
		return {}
	}
}

VERTEX_BUFFER_BINDING_INDEX :: 0

set_vertex_array_format :: proc(va: Vertex_Array, format: []Vertex_Attribute) {
	offset: u32 = 0

	for attribute, index in format {
		description := describe_vertex_attribute(attribute)

		gl.EnableVertexArrayAttrib(va.id, u32(index));
		gl.VertexArrayAttribFormat(va.id,
					   u32(index),
					   description.count,
					   description.type,
					   gl.FALSE,
					   offset)
		gl.VertexArrayAttribBinding(va.id, u32(index), VERTEX_BUFFER_BINDING_INDEX)

		offset += description.size
	}
}

bind_vertex_buffer :: proc(va: Vertex_Array, buffer: Gl_Buffer, stride: i32) {
	gl.VertexArrayVertexBuffer(va.id,
				   bindingindex = VERTEX_BUFFER_BINDING_INDEX,
				   buffer = buffer.id,
				   offset = 0,
				   stride = stride)
}

bind_index_buffer :: proc(va: Vertex_Array, buffer: Gl_Buffer) {
	gl.VertexArrayElementBuffer(va.id,
				    buffer = buffer.id)
}

// Buffers can be either static or dynamic.
// Static buffers have a fixed size.
// Dynamic buffers have a dynamic size.
Gl_Buffer :: struct {
	id: u32,
	size: int,
}

create_static_gl_buffer :: proc(buffer: ^Gl_Buffer, size: int) {
	gl.CreateBuffers(1, &buffer.id)
	gl.NamedBufferStorage(buffer.id, size, nil, gl.DYNAMIC_STORAGE_BIT)
	buffer.size = size
}

create_static_gl_buffer_with_data :: proc(buffer: ^Gl_Buffer, data: []byte) {
	gl.CreateBuffers(1, &buffer.id)
	data_size := slice.size(data)
	gl.NamedBufferStorage(buffer.id, data_size, raw_data(data), gl.DYNAMIC_STORAGE_BIT)
	buffer.size = data_size
}

upload_static_gl_buffer_data :: proc(buffer: Gl_Buffer, data: []byte, offset := 0) {
	data_size := slice.size(data)
	assert(offset + data_size <= buffer.size)
	gl.NamedBufferSubData(buffer.id, offset, data_size, raw_data(data))
}

create_dynamic_gl_buffer :: proc(buffer: ^Gl_Buffer, size := 0, usage: u32 = gl.DYNAMIC_DRAW) {
	gl.CreateBuffers(1, &buffer.id)
	gl.NamedBufferData(buffer.id, size, nil, usage)
	buffer.size = size
}

create_dynamic_gl_buffer_with_data :: proc(buffer: ^Gl_Buffer, data: []byte, usage: u32 = gl.DYNAMIC_DRAW) {
	gl.CreateBuffers(1, &buffer.id)
	data_size := slice.size(data)
	gl.NamedBufferData(buffer.id, data_size, raw_data(data), usage)
	buffer.size = data_size
}

upload_dynamic_gl_buffer_data :: proc(buffer: ^Gl_Buffer, data: []byte, usage: u32 = gl.DYNAMIC_DRAW) {
	data_size := slice.size(data)
	reserve_dynamic_gl_buffer_size(buffer, data_size, usage)
	gl.NamedBufferSubData(buffer.id, 0, data_size, raw_data(data))
}

reserve_dynamic_gl_buffer_size :: proc(buffer: ^Gl_Buffer, min_size: int, usage: u32 = gl.DYNAMIC_DRAW) {
	// We can't just create a new buffer and copy the old data into it, because we want the id of the buffer to
	// remain the same. So we copy the data into a temporary buffer, initialize the new data store for the buffer
	// and copy over the data from the temporary buffer back into the old buffer.

	if buffer.size >= min_size do return

	new_size := max(buffer.size + buffer.size / 2, min_size)

	if buffer.size == 0 {
		// No need to do any copying.
		gl.NamedBufferData(buffer.id, new_size, nil, usage)
		buffer.size = new_size
		return
	}

	temp_buffer: Gl_Buffer
	create_static_gl_buffer(&temp_buffer, buffer.size)
	defer destroy_gl_buffer(&temp_buffer)

	gl.CopyNamedBufferSubData(readBuffer = buffer.id,
				  writeBuffer = temp_buffer.id,
				  readOffset = 0,
				  writeOffset = 0,
				  size = buffer.size)

	gl.NamedBufferData(buffer.id, new_size, nil, usage)

	gl.CopyNamedBufferSubData(readBuffer = temp_buffer.id,
				  writeBuffer = buffer.id,
				  readOffset = 0,
				  writeOffset = 0,
				  size = buffer.size)

	buffer.size = new_size
}

destroy_gl_buffer :: proc(buffer: ^Gl_Buffer) {
	gl.DeleteBuffers(1, &buffer.id)
}

bind_uniform_buffer :: proc(buffer: Gl_Buffer, binding_point: u32) {
	gl.BindBufferBase(gl.UNIFORM_BUFFER, binding_point, buffer.id)
}

Texture :: struct {
	id: u32,
	width: u32,
	height: u32,
}

create_texture :: proc(width, height: u32, channels: int, pixels: []byte) -> (texture: Texture) {
	assert(slice.size(pixels) == int(width) * int(height) * channels * size_of(byte))
	gl.CreateTextures(gl.TEXTURE_2D, 1, &texture.id)

	gl.TextureParameteri(texture.id, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TextureParameteri(texture.id, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TextureParameteri(texture.id, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TextureParameteri(texture.id, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

	gl.TextureStorage2D(texture.id,
			    levels = 1,
			    internalformat = gl.RGBA8,
			    width = i32(width),
			    height = i32(height))

	gl.TextureSubImage2D(texture.id,
			     level = 0,
			     xoffset = 0,
			     yoffset = 0,
			     width = i32(width),
			     height = i32(height),
			     format = gl_texture_format_from_channels(channels),
			     type = gl.UNSIGNED_BYTE,
			     pixels = raw_data(pixels))

	texture.width, texture.height = width, height
	return texture
}

create_texture_from_png_in_memory :: proc(png_file_data: []byte) -> (texture: Texture, ok := false) {
	img, error := image.load(png_file_data)
	if error != nil {
		log.errorf("Failed to load image from png file in memory: %v", error)
		return
	}
	defer image.destroy(img)

	texture = create_texture(u32(img.width), u32(img.height), img.channels, bytes.buffer_to_bytes(&img.pixels))
	ok = true
	return
}

create_texture_from_aseprite_in_memory :: proc(aseprite_file_data: []byte) -> (texture: Texture, ok := false) {
	document: ase.Document
	defer ase.destroy_doc(&document)
	unmarshal_error := ase.unmarshal(&document, aseprite_file_data)
	if unmarshal_error != nil {
		log.errorf("Failed to unmarshal aseprite file in memory: %v", unmarshal_error)
		return
	}
	image, image_error := ase_utils.get_image(&document)
	if image_error != nil {
		log.errorf("Failed to get aseprite image: %v", image_error)
		return
	}
	defer ase_utils.destroy(image)

	texture = create_texture(u32(image.width),
				 u32(image.height),
				 channels_from_aseprite_bpp(image.bpp),
				 image.data)
	ok = true
	return
}

create_texture_from_png_file :: proc(path: string) -> (texture: Texture, ok := false) {
	file_data := os.read_entire_file(path, context.temp_allocator) or_return
	assert(strings.to_lower(filepath.ext(path), context.temp_allocator) == ".png", "expected a png file")
	return create_texture_from_png_in_memory(file_data)
}

create_texture_from_aseprite_file :: proc(path: string) -> (texture: Texture, ok := false) {
	file_data := os.read_entire_file(path, context.temp_allocator) or_return
	assert(strings.to_lower(filepath.ext(path), context.temp_allocator) == ".aseprite", "expected an aseprite file")
	return create_texture_from_aseprite_in_memory(file_data)
}

destroy_texture :: proc(texture: ^Texture) {
	gl.DeleteTextures(1, &texture.id)
}

bind_texture_object :: proc(texture: Texture, slot: u32) {
	gl.BindTextureUnit(slot, texture.id)
}

bind_texture :: proc(id: Texture_Id, slot: u32) {
	bind_texture_object(get_texture(id), slot)
}

@(private="file")
gl_texture_format_from_channels :: proc(#any_int channels: int) -> u32 {
	switch channels {
	case 1: return gl.RED
	case 2: return gl.RG
	case 3: return gl.RGB
	case 4: return gl.RGBA
	}

	assert(false)
	return gl.NONE
}

@(private="file")
channels_from_aseprite_bpp :: proc(depth: ase_utils.Pixel_Depth) -> int {
	switch depth {
	case .Indexed:   return 1
	case .Grayscale: return 2
	case .RGBA:      return 4
	}

	assert(false)
	return 0
}
