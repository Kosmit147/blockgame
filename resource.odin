package blockgame

import gl "vendor:OpenGL"

import "core:log"
import "core:strings"

Shader_Id :: enum {
	Block,
	D2,
}

Texture_Id :: enum {
	White,
	Black,
	Transparent,
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
	for &shader, shader_id in s_shaders {
		vertex_source, fragment_source := shader_sources_map[shader_id][0], shader_sources_map[shader_id][1]
		shader = create_shader(vertex_source, fragment_source) or_return
	}

	ok = true
	return
}

@(private="file")
deinit_shaders :: proc() {
	for shader in s_shaders do destroy_shader(shader)
}

@(private="file")
init_textures :: proc() -> (ok := false) {
	defer if !ok do deinit_textures()
	for &texture, texture_id in s_textures {
		texture_file_data := texture_data_map[texture_id]
		texture = create_texture_from_png_in_memory(texture_file_data) or_return
	}

	ok = true
	return
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

	// Keep in mind that this will probably be called from a separate tread.
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
		any_shader_reloaded := false
		for dirty_shader in s_dirty_shaders {
			if reload_shader(dirty_shader) {
				any_shader_reloaded = true
				log.infof("Reloaded shader %v", dirty_shader)
			} else {
				log.errorf("Failed to reload shader %v", dirty_shader)
			}
		}
		s_dirty_shaders = {}

		for dirty_texture in s_dirty_textures {
			if reload_texture(dirty_texture) {
				log.infof("Reloaded texture %v", dirty_texture)
			} else {
				log.errorf("Failed to reload texture %v", dirty_texture)
			}
		}
		s_dirty_textures = {}

		if any_shader_reloaded do renderer_get_uniforms()
	}

	@(private="file")
	mark_shader_as_dirty :: proc(file_path: string) {
		switch file_path {
		case BLOCK_SHADER_VERTEX_PATH, BLOCK_SHADER_FRAGMENT_PATH: s_dirty_shaders += { .Block }
		case D2_SHADER_VERTEX_PATH, D2_SHADER_FRAGMENT_PATH:       s_dirty_shaders += { .D2 }
		case: log.warnf("Hot reload - unrecognized shader resource: %v", file_path)
		}
	}

	@(private="file")
	mark_texture_as_dirty :: proc(file_path: string) {
		switch file_path {
		case WHITE_TEXTURE_PATH:       s_dirty_textures += { .White }
		case BLACK_TEXTURE_PATH:       s_dirty_textures += { .Black }
		case TRANSPARENT_TEXTURE_PATH: s_dirty_textures += { .Transparent }
		case STONE_TEXTURE_PATH:       s_dirty_textures += { .Stone }
		case: log.warnf("Hot reload - unrecognized texture resource: %v", file_path)
		}
	}

	@(private="file")
	reload_shader :: proc(id: Shader_Id) -> (ok := false) {
		vertex_path, fragment_path := shader_file_paths_map[id][0], shader_file_paths_map[id][1]
		reloaded_shader := create_shader_from_files(vertex_path, fragment_path) or_return
		destroy_shader(s_shaders[id])
		s_shaders[id] = reloaded_shader

		ok = true
		return
	}

	@(private="file")
	reload_texture :: proc(id: Texture_Id) -> (ok := false) {
		texture_path := texture_file_paths_map[id]
		reloaded_texture := create_texture_from_png_file(texture_path) or_return
		destroy_texture(&s_textures[id])
		s_textures[id] = reloaded_texture

		ok = true
		return
	}
}

SHADERS_PATH :: "shaders/"
BLOCK_SHADER_VERTEX_PATH :: "shaders/block.vert"
BLOCK_SHADER_FRAGMENT_PATH :: "shaders/block.frag"
D2_SHADER_VERTEX_PATH :: "shaders/2d.vert"
D2_SHADER_FRAGMENT_PATH :: "shaders/2d.frag"

TEXTURES_PATH :: "textures/"
WHITE_TEXTURE_PATH :: "textures/white.png"
BLACK_TEXTURE_PATH :: "textures/black.png"
TRANSPARENT_TEXTURE_PATH :: "textures/transparent.png"
STONE_TEXTURE_PATH :: "textures/stone.png"

@(rodata, private="file")
shader_sources_map := [Shader_Id][2]string{
	.Block = { #load(BLOCK_SHADER_VERTEX_PATH, string), #load(BLOCK_SHADER_FRAGMENT_PATH, string) },
	.D2 = { #load(D2_SHADER_VERTEX_PATH, string), #load(D2_SHADER_FRAGMENT_PATH, string) },
}

@(rodata, private="file")
texture_data_map := [Texture_Id][]byte{
	.White = #load(WHITE_TEXTURE_PATH),
	.Black = #load(BLACK_TEXTURE_PATH),
	.Transparent = #load(TRANSPARENT_TEXTURE_PATH),
	.Stone = #load(STONE_TEXTURE_PATH),
}

when HOT_RELOAD {
	@(rodata, private="file")
	shader_file_paths_map := [Shader_Id][2]string{
		.Block = { BLOCK_SHADER_VERTEX_PATH, BLOCK_SHADER_FRAGMENT_PATH },
		.D2 = { D2_SHADER_VERTEX_PATH, D2_SHADER_FRAGMENT_PATH },
	}

	@(rodata, private="file")
	texture_file_paths_map := [Texture_Id]string{
		.White = WHITE_TEXTURE_PATH,
		.Black = BLACK_TEXTURE_PATH,
		.Transparent = TRANSPARENT_TEXTURE_PATH,
		.Stone = STONE_TEXTURE_PATH,
	}
}
