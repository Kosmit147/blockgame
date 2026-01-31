package blockgame

import gl "vendor:OpenGL"

import "core:log"
import "core:strings"

Shader_Id :: enum {
	Base,
	D2,
}

Texture_Id :: enum {
	Stone,
}

@(private="file")
s_shaders: [Shader_Id]Shader
@(private="file")
s_textures: [Texture_Id]Texture

init_resources :: proc() -> (ok := false) {
	init_shaders() or_return
	defer if !ok do deinit_shaders()
	init_textures() or_return
	defer if !ok do deinit_textures()

	ok = true
	return
}

deinit_resources :: proc() {
	deinit_shaders()
	deinit_textures()
}

@(require_results)
get_shader :: proc(id: Shader_Id) -> Shader {
	when ODIN_DEBUG { assert(s_shaders[id].id != gl.NONE) }
	return s_shaders[id]
}

@(require_results)
get_texture :: proc(id: Texture_Id) -> Texture {
	when ODIN_DEBUG { assert(s_textures[id].id != gl.NONE) }
	return s_textures[id]
}

@(private="file")
init_shaders :: proc() -> (ok := false) {
	defer if !ok do deinit_shaders()
	for &shader, shader_id in s_shaders do shader = create_shader(get_shader_sources(shader_id)) or_return

	ok = true
	return
}

@(private="file")
get_shader_sources :: proc(id: Shader_Id) -> (string, string) {
	switch id {
	case .Base: return base_shader_vertex_source, base_shader_fragment_source
	case .D2:   return d2_shader_vertex_source, d2_shader_fragment_source
	}

	assert(false)
	return {}, {}
}

@(private="file")
deinit_shaders :: proc() {
	for shader in s_shaders do destroy_shader(shader)
}

@(private="file")
init_textures :: proc() -> (ok := false) {
	defer if !ok do deinit_textures()
	for &texture, texture_id in s_textures {
		texture = create_texture_from_png_in_memory(get_texture_file_data(texture_id)) or_return
	}

	ok = true
	return
}

@(private="file")
get_texture_file_data :: proc(id: Texture_Id) -> []byte {
	switch id {
	case .Stone: return stone_texture_file_data
	}

	assert(false)
	return {}
}

@(private="file")
deinit_textures :: proc() {
	for &texture in s_textures do destroy_texture(&texture)
}

when HOT_RELOAD {
	@(private="file")
	s_dirty_shaders: bit_set[Shader_Id]
	@(private="file")
	s_dirty_textures: bit_set[Texture_Id]

	request_resource_reload :: proc(path: string) {
		if strings.starts_with(path, SHADERS_PATH) {
			mark_shader_as_dirty(path)
		} else if strings.starts_with(path, TEXTURES_PATH) {
			mark_texture_as_dirty(path)
		} else {
			log.warnf("Hot reload - unrecognized resource path: %v", path)
		}
	}

	hot_reload :: proc() {
		for dirty_shader in s_dirty_shaders {
			if !reload_shader(dirty_shader) do log.errorf("Failed to reload shader %v", dirty_shader)
		}
		s_dirty_shaders = {}

		for dirty_texture in s_dirty_textures {
			if !reload_texture(dirty_texture) do log.errorf("Failed to reload texture %v", dirty_texture)
		}
		s_dirty_textures = {}
	}

	@(private="file")
	mark_shader_as_dirty :: proc(file_path: string) {
		switch file_path {
		case BASE_SHADER_VERTEX_PATH, BASE_SHADER_FRAGMENT_PATH: s_dirty_shaders += { .Base }
		case D2_SHADER_VERTEX_PATH, D2_SHADER_FRAGMENT_PATH:     s_dirty_shaders += { .D2 }
		case: log.warnf("Hot reload - unrecognized shader resource: %v", file_path)
		}
	}

	@(private="file")
	mark_texture_as_dirty :: proc(file_path: string) {
		switch file_path {
		case STONE_TEXTURE_PATH: s_dirty_textures += { .Stone }
		case: log.warnf("Hot reload - unrecognized texture resource: %v", file_path)
		}
	}

	@(private="file")
	reload_shader :: proc(id: Shader_Id) -> (ok := false) {
		vertex_path, fragment_path: string

		switch id {
		case .Base: vertex_path, fragment_path = BASE_SHADER_VERTEX_PATH, BASE_SHADER_FRAGMENT_PATH
		case .D2:   vertex_path, fragment_path = D2_SHADER_VERTEX_PATH, D2_SHADER_FRAGMENT_PATH
		case:       assert(false)
		}

		reloaded_shader := create_shader_from_files(vertex_path, fragment_path) or_return
		destroy_shader(s_shaders[id])
		s_shaders[id] = reloaded_shader

		ok = true
		return
	}

	@(private="file")
	reload_texture :: proc(id: Texture_Id) -> (ok := false) {
		texture_path: string

		switch id {
		case .Stone: texture_path = STONE_TEXTURE_PATH
		case:        assert(false)
		}

		reloaded_texture := create_texture_from_png_file(texture_path) or_return
		destroy_texture(&s_textures[id])
		s_textures[id] = reloaded_texture

		ok = true
		return
	}
}

SHADERS_PATH :: "shaders/"
TEXTURES_PATH :: "textures/"

BASE_SHADER_VERTEX_PATH :: "shaders/base.vert"
BASE_SHADER_FRAGMENT_PATH :: "shaders/base.frag"
@(rodata) base_shader_vertex_source := #load(BASE_SHADER_VERTEX_PATH, string)
@(rodata) base_shader_fragment_source := #load(BASE_SHADER_FRAGMENT_PATH, string)

D2_SHADER_VERTEX_PATH :: "shaders/2d.vert"
D2_SHADER_FRAGMENT_PATH :: "shaders/2d.frag"
@(rodata) d2_shader_vertex_source := #load(D2_SHADER_VERTEX_PATH, string)
@(rodata) d2_shader_fragment_source := #load(D2_SHADER_FRAGMENT_PATH, string)

STONE_TEXTURE_PATH :: "textures/stone.png"
@(rodata) stone_texture_file_data := #load(STONE_TEXTURE_PATH)
