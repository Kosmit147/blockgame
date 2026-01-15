package blockgame

import "base:runtime"

import "vendor:glfw"
import gl "vendor:OpenGL"

import "core:log"
import "core:os"
import "core:mem"
import "core:slice"
import "core:math"
import "core:math/linalg"

MOUSE_SENSITIVITY :: 0.15
MODEL_MOVE_SPEED :: 1

SHADER_VERTEX_SOURCE :: #load("shader_vertex.glsl", cstring)
SHADER_FRAGMENT_SOURCE :: #load("shader_fragment.glsl", cstring)

MODEL_UNIFORM_NAME :: "model"
MODEL_UNIFORM_TYPE :: Mat4
VIEW_UNIFORM_NAME :: "view"
VIEW_UNIFORM_TYPE :: Mat4
PROJECTION_UNIFORM_NAME :: "projection"
PROJECTION_UNIFORM_TYPE :: Mat4

COBBLE_TEXTURE_FILE_DATA :: #load("cobble.png")

Vertex :: struct {
	position: Vec3,
	normal: Vec3,
	uv: Vec2,
}

VERTEX_FORMAT :: [?]Vertex_Attribute{
	.Float3,
	.Float3,
	.Float2,
}

@(rodata)
vertices := [24]Vertex{
	// Front wall.
	{ position = { -0.5, -0.5,  0.5 }, normal = {  0,  0,  1 }, uv = { 0, 0 } },
	{ position = {  0.5, -0.5,  0.5 }, normal = {  0,  0,  1 }, uv = { 1, 0 } },
	{ position = {  0.5,  0.5,  0.5 }, normal = {  0,  0,  1 }, uv = { 1, 1 } },
	{ position = { -0.5,  0.5,  0.5 }, normal = {  0,  0,  1 }, uv = { 0, 1 } },

	// Back wall.
	{ position = { -0.5, -0.5, -0.5 }, normal = {  0,  0, -1 }, uv = { 0, 0 } },
	{ position = { -0.5,  0.5, -0.5 }, normal = {  0,  0, -1 }, uv = { 0, 1 } },
	{ position = {  0.5,  0.5, -0.5 }, normal = {  0,  0, -1 }, uv = { 1, 1 } },
	{ position = {  0.5, -0.5, -0.5 }, normal = {  0,  0, -1 }, uv = { 1, 0 } },

	// Left wall.
	{ position = { -0.5,  0.5,  0.5 }, normal = { -1,  0,  0 }, uv = { 1, 0 } },
	{ position = { -0.5,  0.5, -0.5 }, normal = { -1,  0,  0 }, uv = { 1, 1 } },
	{ position = { -0.5, -0.5, -0.5 }, normal = { -1,  0,  0 }, uv = { 0, 1 } },
	{ position = { -0.5, -0.5,  0.5 }, normal = { -1,  0,  0 }, uv = { 0, 0 } },

	// Right wall.
	{ position = {  0.5,  0.5,  0.5 }, normal = {  1,  0,  0 }, uv = { 1, 0 } },
	{ position = {  0.5, -0.5,  0.5 }, normal = {  1,  0,  0 }, uv = { 0, 0 } },
	{ position = {  0.5, -0.5, -0.5 }, normal = {  1,  0,  0 }, uv = { 0, 1 } },
	{ position = {  0.5,  0.5, -0.5 }, normal = {  1,  0,  0 }, uv = { 1, 1 } },

	// Bottom wall.
	{ position = { -0.5, -0.5, -0.5 }, normal = {  0, -1,  0 }, uv = { 0, 1 } },
	{ position = {  0.5, -0.5, -0.5 }, normal = {  0, -1,  0 }, uv = { 1, 1 } },
	{ position = {  0.5, -0.5,  0.5 }, normal = {  0, -1,  0 }, uv = { 1, 0 } },
	{ position = { -0.5, -0.5,  0.5 }, normal = {  0, -1,  0 }, uv = { 0, 0 } },

	// Top wall.
	{ position = { -0.5,  0.5, -0.5 }, normal = {  0,  1,  0 }, uv = { 0, 1 } },
	{ position = { -0.5,  0.5,  0.5 }, normal = {  0,  1,  0 }, uv = { 0, 0 } },
	{ position = {  0.5,  0.5,  0.5 }, normal = {  0,  1,  0 }, uv = { 1, 0 } },
	{ position = {  0.5,  0.5, -0.5 }, normal = {  0,  1,  0 }, uv = { 1, 1 } },
}

@(rodata)
indices := [36]u16{
	// Front wall.
	0, 1, 2, 0, 2, 3,

	// Back wall.
	4, 5, 6, 4, 6, 7,

	// Left wall.
	8, 9, 10, 8, 10, 11,

	// Right wall.
	12, 13, 14, 12, 14, 15,

	// Bottom wall.
	16, 17, 18, 16, 18, 19,

	// Top wall.
	20, 21, 22, 20, 22, 23,
}

g_context: runtime.Context

main :: proc() {
	context.logger = log.create_console_logger(.Debug when ODIN_DEBUG else .Info)
	defer log.destroy_console_logger(context.logger)

	when ODIN_DEBUG {
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)

		defer {
			if len(tracking_allocator.allocation_map) > 0 {
				log.errorf("MEMORY LEAK: %v allocations not freed:",
					   len(tracking_allocator.allocation_map))

				for _, entry in tracking_allocator.allocation_map {
					log.errorf("- %v bytes at %v", entry.size, entry.location)
				}
			}

			mem.tracking_allocator_destroy(&tracking_allocator)
		}
	}

	g_context = context

	if !window_init(1920, 1080, "Blockgame") do log.panic("Failed to create a window.")
	defer window_deinit()

	shader, shader_ok := create_shader(SHADER_VERTEX_SOURCE, SHADER_FRAGMENT_SOURCE) 
	if !shader_ok do log.panic("Failed to compile the shader.")
	defer destroy_shader(shader)
	use_shader(shader)

	model_uniform := get_uniform(shader, MODEL_UNIFORM_NAME, MODEL_UNIFORM_TYPE)
	view_uniform := get_uniform(shader, VIEW_UNIFORM_NAME, VIEW_UNIFORM_TYPE)
	projection_uniform := get_uniform(shader, PROJECTION_UNIFORM_NAME, PROJECTION_UNIFORM_TYPE)

	texture, texture_ok := create_texture_from_png_in_memory(COBBLE_TEXTURE_FILE_DATA)
	if !texture_ok do log.panic("Failed to load the texture.")
	defer destroy_texture(&texture)
	bind_texture(texture, 0)

	va: Vertex_Array
	create_vertex_array(&va)
	set_vertex_array_format(va, VERTEX_FORMAT)
	defer destroy_vertex_array(&va)

	vb: Gl_Buffer
	create_gl_buffer_with_data(&vb, slice.to_bytes(vertices[:]))
	defer destroy_gl_buffer(&vb)

	ib: Gl_Buffer
	create_gl_buffer_with_data(&ib, slice.to_bytes(indices[:]))
	defer destroy_gl_buffer(&ib)

	bind_vertex_array(va)
	bind_vertex_buffer(va, vb, size_of(Vertex))
	bind_index_buffer(va, ib)

	camera := Camera {
		position = { 0, 0, 2 },
		yaw = math.to_radians(f32(-90)),
		pitch = math.to_radians(f32(0)),
	}

	cube_translation: Vec3

	prev_cursor_pos := window_cursor_pos()
	prev_time := window_time()

	for !window_should_close() {
		window_poll_events()

		time := window_time()
		dt := time - prev_time
		prev_time = time

		cursor_pos := window_cursor_pos()
		cursor_pos_delta := cursor_pos - prev_cursor_pos
		prev_cursor_pos = cursor_pos

		camera.yaw += cursor_pos_delta.x * MOUSE_SENSITIVITY * f32(dt)
		camera.pitch += -cursor_pos_delta.y * MOUSE_SENSITIVITY * f32(dt)

		camera_vectors := camera_vectors(camera)

		if glfw.GetKey(window_handle(), glfw.KEY_W) == glfw.PRESS     do camera.position += camera_vectors.forward * f32(dt)
		if glfw.GetKey(window_handle(), glfw.KEY_S) == glfw.PRESS     do camera.position -= camera_vectors.forward * f32(dt)
		if glfw.GetKey(window_handle(), glfw.KEY_A) == glfw.PRESS     do camera.position -= camera_vectors.right * f32(dt)
		if glfw.GetKey(window_handle(), glfw.KEY_D) == glfw.PRESS     do camera.position += camera_vectors.right * f32(dt)

		if glfw.GetKey(window_handle(), glfw.KEY_UP) == glfw.PRESS    do cube_translation.y += MODEL_MOVE_SPEED * f32(dt)
		if glfw.GetKey(window_handle(), glfw.KEY_DOWN) == glfw.PRESS  do cube_translation.y -= MODEL_MOVE_SPEED * f32(dt)
		if glfw.GetKey(window_handle(), glfw.KEY_LEFT) == glfw.PRESS  do cube_translation.x -= MODEL_MOVE_SPEED * f32(dt)
		if glfw.GetKey(window_handle(), glfw.KEY_RIGHT) == glfw.PRESS do cube_translation.x += MODEL_MOVE_SPEED * f32(dt)

		model := linalg.matrix4_translate(cube_translation)

		view := linalg.matrix4_look_at(eye = camera.position,
					       centre = camera.position + camera_vectors.forward,
					       up = camera_vectors.up)

		projection := linalg.matrix4_perspective(fovy = math.to_radians(f32(45)),
							 aspect = window_aspect_ratio(),
							 near = 0.1,
							 far = 100)

		gl.ClearColor(0, 0, 0, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		use_shader(shader)
		set_uniform(model_uniform, model)
		set_uniform(view_uniform, view)
		set_uniform(projection_uniform, projection)

		gl.DrawElements(gl.TRIANGLES, len(indices), gl.UNSIGNED_SHORT, nil)

		window_swap_buffers()
		free_all(context.temp_allocator)
	}
}
