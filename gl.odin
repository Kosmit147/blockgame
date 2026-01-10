package blockgame

import gl "vendor:OpenGL"

import "core:fmt"
import "core:strings"

Shader :: struct {
	id: u32
}

create_shader :: proc(shader: ^Shader, vertex_source, fragment_source: cstring) -> bool {
	vertex_shader := create_sub_shader(vertex_source, gl.VERTEX_SHADER) or_return
	defer gl.DeleteShader(vertex_shader)
	fragment_shader := create_sub_shader(fragment_source, gl.FRAGMENT_SHADER) or_return
	defer gl.DeleteShader(fragment_shader)
	shader_program := link_shader_program(vertex_shader, fragment_shader) or_return
	shader.id = shader_program
	return true
}

destroy_shader :: proc(shader: ^Shader) {
	gl.DeleteProgram(shader.id)
}

@(private="file")
create_sub_shader :: proc(shader_source: cstring, shader_type: u32) -> (u32, bool) {
	sources_array := [1]cstring{ shader_source }

	shader := gl.CreateShader(shader_type)
	gl.ShaderSource(shader, 1, raw_data(sources_array[:]), nil)

	gl.CompileShader(shader)
	is_compiled: i32

	if gl.GetShaderiv(shader, gl.COMPILE_STATUS, &is_compiled); is_compiled == gl.FALSE {
		info_log_length: i32
		gl.GetShaderiv(shader, gl.INFO_LOG_LENGTH, &info_log_length)

		info_log_buffer := make([]byte, info_log_length)
		defer delete(info_log_buffer)

		gl.GetShaderInfoLog(shader, info_log_length, nil, raw_data(info_log_buffer))
		info_log := string(info_log_buffer)
		info_log = strings.trim_null(info_log)

		fmt.eprintf("Failed to compile shader: %v", info_log)

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

		info_log_buffer := make([]byte, info_log_length)
		defer delete(info_log_buffer)

		gl.GetProgramInfoLog(program, info_log_length, nil, raw_data(info_log_buffer))
		info_log := string(info_log_buffer)
		info_log = strings.trim_null(info_log)

		fmt.eprintf("Failed to link shader: %v", info_log)

		gl.DeleteProgram(program)
		return gl.NONE, false
	}

	gl.DetachShader(program, vertex_shader)
	gl.DetachShader(program, fragment_shader)

	return program, true
}
