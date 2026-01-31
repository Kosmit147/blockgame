package blockgame

import "core:log"

SHADERS_PATH :: "shaders"
D2_SHADER_VERTEX_PATH :: "shaders/2d.vert"
D2_SHADER_FRAGMENT_PATH :: "shaders/2d.frag"
D2_SHADER_VERTEX_SOURCE :: #load(D2_SHADER_VERTEX_PATH, string)
D2_SHADER_FRAGMENT_SOURCE :: #load(D2_SHADER_FRAGMENT_PATH, string)
BASE_SHADER_VERTEX_PATH :: "shaders/base.vert"
BASE_SHADER_FRAGMENT_PATH :: "shaders/base.frag"
BASE_SHADER_VERTEX_SOURCE :: #load(BASE_SHADER_VERTEX_PATH, string)
BASE_SHADER_FRAGMENT_SOURCE :: #load(BASE_SHADER_FRAGMENT_PATH, string)

TEXTURES_PATH :: "textures"
STONE_TEXTURE_PATH :: "textures/stone.png"
STONE_TEXTURE_FILE_DATA :: #load(STONE_TEXTURE_PATH)

when HOT_RELOAD {
	@(private="file")
	s_reload_base_shader: bool
	@(private="file")
	s_reload_2d_shader: bool
	@(private="file")
	s_reload_stone_texture: bool

	reload_resource :: proc(resource_path: string) {
		switch resource_path {
		case BASE_SHADER_VERTEX_PATH, BASE_SHADER_FRAGMENT_PATH:  s_reload_base_shader = true
		case D2_SHADER_VERTEX_PATH, D2_SHADER_FRAGMENT_PATH:      s_reload_2d_shader = true
		case STONE_TEXTURE_PATH:                                  s_reload_stone_texture = true
		case: log.warnf("Hot reload - unrecognized resource path: %v", resource_path)
		}
	}

	hot_reload :: proc() {
		if s_reload_base_shader do renderer_reload_base_shader()
		if s_reload_2d_shader do renderer_2d_reload_2d_shader()
		if s_reload_stone_texture do renderer_reload_stone_texture()

		s_reload_base_shader = false
		s_reload_2d_shader = false
		s_reload_stone_texture = false
	}
}
