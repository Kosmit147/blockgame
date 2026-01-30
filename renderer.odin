package blockgame

import gl "vendor:OpenGL"

import "core:log"
import "core:math/linalg"
import "core:math"

// These symbols tell GPU drivers to use the dedicated graphics card.
@(export, rodata)
NvOptimusEnablement: u32 = 1
@(export, rodata)
AmdPowerXpressRequestHighPerformance: u32 = 1

BASE_SHADER_VERTEX_SOURCE :: #load("base_shader.vert", cstring)
BASE_SHADER_FRAGMENT_SOURCE :: #load("base_shader.frag", cstring)

STONE_TEXTURE_FILE_DATA :: #load("textures/stone.png")

Standard_Vertex :: struct {
	position: Vec3,
	normal: Vec3,
	uv: Vec2,
}

Renderer :: struct {
	shader: Shader,
	model_uniform: Uniform(Mat4),
	view_uniform: Uniform(Mat4),
	projection_uniform: Uniform(Mat4),

	block_texture: Texture,
}

@(private="file")
s_renderer: Renderer

renderer_init :: proc() -> (ok := false) {
	gl.ClearColor(0, 0, 0, 1)
	gl.Enable(gl.CULL_FACE)
	gl.CullFace(gl.BACK)
	gl.FrontFace(gl.CCW)
	gl.Enable(gl.DEPTH_TEST)

	s_renderer.shader, ok = create_shader(BASE_SHADER_VERTEX_SOURCE, BASE_SHADER_FRAGMENT_SOURCE) 
	if !ok {
		log.fatal("Failed to compile the base shader.")
		return
	}
	defer if !ok do destroy_shader(s_renderer.shader)

	s_renderer.model_uniform = get_uniform(s_renderer.shader, "model", Mat4)
	s_renderer.view_uniform = get_uniform(s_renderer.shader, "view", Mat4)
	s_renderer.projection_uniform = get_uniform(s_renderer.shader, "projection", Mat4)

	s_renderer.block_texture, ok = create_texture_from_png_in_memory(STONE_TEXTURE_FILE_DATA)
	if !ok {
		log.fatal("Failed to load the block texture.")
		return
	}
	defer if !ok do destroy_texture(&s_renderer.block_texture)

	ok = true
	return
}

renderer_deinit :: proc() {
	destroy_texture(&s_renderer.block_texture)
	destroy_shader(s_renderer.shader)
}

renderer_clear :: proc() {
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
}

renderer_begin_frame :: proc(camera: Camera) {
	camera_vectors := camera_vectors(camera)

	view := linalg.matrix4_look_at(eye = camera.position,
				       centre = camera.position + camera_vectors.forward,
				       up = camera_vectors.up)

	projection := linalg.matrix4_perspective(fovy = math.to_radians(f32(45)),
						 aspect = window_aspect_ratio(),
						 near = 0.1,
						 far = 100)

	use_shader(s_renderer.shader)
	set_uniform(s_renderer.view_uniform, view)
	set_uniform(s_renderer.projection_uniform, projection)
}

renderer_render_mesh :: proc(mesh: Mesh) {
	bind_mesh(mesh)
	gl.DrawElements(gl.TRIANGLES,
			i32(mesh.vertex_count),
			mesh.index_type,
			cast(rawptr)uintptr(mesh.index_data_offset))
}

renderer_render_chunk :: proc(chunk: Chunk) {
	model := linalg.matrix4_translate(Vec3{ f32(chunk.coordinate.x * CHUNK_SIZE.x),
						0,
						f32(chunk.coordinate.z * CHUNK_SIZE.z) })

	set_uniform(s_renderer.model_uniform, model)
	renderer_render_mesh(chunk.mesh)
}

renderer_render_world :: proc(world: World) {
	use_shader(s_renderer.shader)
	bind_texture(s_renderer.block_texture, 0)
	for chunk in world.chunks do renderer_render_chunk(chunk)
}
