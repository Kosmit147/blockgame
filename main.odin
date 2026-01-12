package blockgame

import "base:runtime"

import "vendor:glfw"
import gl "vendor:OpenGL"

import "core:fmt"
import "core:os"
import "core:mem"
import "core:slice"
import "core:math"
import "core:math/linalg"

GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
INITIAL_WINDOW_WIDTH :: 1080
INITIAL_WINDOW_HEIGHT :: 1080
WINDOW_TITLE :: "Blockgame"
MOUSE_SENSITIVITY :: 1

VERTEX_SHADER_SOURCE :: #load("vertex.glsl", cstring)
FRAGMENT_SHADER_SOURCE :: #load("fragment.glsl", cstring)

MODEL_UNIFORM_NAME :: "model"
MODEL_UNIFORM_TYPE :: Mat4
VIEW_UNIFORM_NAME :: "view"
VIEW_UNIFORM_TYPE :: Mat4
PROJECTION_UNIFORM_NAME :: "projection"
PROJECTION_UNIFORM_TYPE :: Mat4

Triangle_Vertex :: Vec3

TRIANGLE_VERTEX_FORMAT :: [?]Vertex_Attribute{
	.Float3
}

@(rodata)
triangle_vertices := [3]Triangle_Vertex{
	{ -0.5, -0.5, 0 },
	{  0.0,  0.5, 0 },
	{  0.5, -0.5, 0 },
}

@(rodata)
triangle_indices := [3]u32{ 0, 1, 2 }

@(private="file")
glfw_error_callback :: proc "c" (error: i32, description: cstring) {
	context = runtime.default_context()
	fmt.eprintfln("GLFW Error %v: %v", error, description)
}

@(private="file")
glfw_key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = runtime.default_context()

	switch key {
	case 'A'..='Z', 'a'..='z':
		fmt.printfln("Key %v pressed", rune(key))
	case:
		fmt.printfln("Key %v pressed", key)
	}

	if key == glfw.KEY_ESCAPE && action == glfw.PRESS do glfw.SetWindowShouldClose(window, true)
}

@(private="file")
glfw_framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	context = runtime.default_context()
	fmt.printfln("New window size: %v x %v", width, height)
	gl.Viewport(0, 0, width, height)
}

when ODIN_DEBUG {

	@(private="file")
	gl_debug_message_callback :: proc "c" (
		source, type, id, severity: u32,
		length: i32,
		message: cstring,
		user_ptr: rawptr) {
		context = runtime.default_context()
		fmt.printfln("OpenGL message: %v", message)
	}

}

get_aspect_ratio :: proc(window: glfw.WindowHandle) -> f32 {
	width, height := glfw.GetWindowSize(window)
	return f32(width) / f32(height)
}

get_cursor_pos :: proc(window: glfw.WindowHandle) -> Vec2 {
	x, y := glfw.GetCursorPos(window)
	return { f32(x), f32(y) }
}

main :: proc() {
	when ODIN_DEBUG {
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)

		defer {
			if len(tracking_allocator.allocation_map) > 0 {
				fmt.eprintfln("MEMORY LEAK: %v allocations not freed:",
					      len(tracking_allocator.allocation_map))

				for _, entry in tracking_allocator.allocation_map {
					fmt.eprintfln("- %v bytes at %v", entry.size, entry.location)
				}
			}

			mem.tracking_allocator_destroy(&tracking_allocator)
		}
	}

	glfw.SetErrorCallback(glfw_error_callback)

	if !glfw.Init() {
		fmt.eprintln("Failed to initialize GLFW.")
		os.exit(-1)
	}

	defer glfw.Terminate()

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_VERSION_MAJOR)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_VERSION_MINOR)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_DEBUG_CONTEXT, glfw.TRUE when ODIN_DEBUG else glfw.FALSE)

	window := glfw.CreateWindow(INITIAL_WINDOW_WIDTH, INITIAL_WINDOW_HEIGHT, WINDOW_TITLE, nil, nil)

	if window == nil {
		fmt.eprintln("Failed to create a window.")
		os.exit(-1)
	}

	defer glfw.DestroyWindow(window)

	glfw.MakeContextCurrent(window)
	gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, glfw.gl_set_proc_address)

	when ODIN_DEBUG {
		gl.Enable(gl.DEBUG_OUTPUT)
		gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
		gl.DebugMessageCallback(gl_debug_message_callback, nil)

		fmt.printfln("Vendor: %v", gl.GetString(gl.VENDOR))
		fmt.printfln("Renderer: %v", gl.GetString(gl.RENDERER))
		fmt.printfln("Version: %v", gl.GetString(gl.VERSION))
	}

	gl.Viewport(0, 0, INITIAL_WINDOW_WIDTH, INITIAL_WINDOW_HEIGHT)

	glfw.SetFramebufferSizeCallback(window, glfw_framebuffer_size_callback)
	glfw.SetKeyCallback(window, glfw_key_callback)
	glfw.SetInputMode(window, glfw.CURSOR, glfw.CURSOR_DISABLED)

	if glfw.RawMouseMotionSupported() {
		glfw.SetInputMode(window, glfw.RAW_MOUSE_MOTION, glfw.TRUE)
	}

	shader: Shader
	if !create_shader(&shader, VERTEX_SHADER_SOURCE, FRAGMENT_SHADER_SOURCE) {
		fmt.eprintln("Failed to compile the shader.")
		os.exit(-1)
	}
	defer destroy_shader(&shader)

	use_shader(shader)

	model_uniform, model_uniform_ok := get_uniform(shader, MODEL_UNIFORM_NAME, MODEL_UNIFORM_TYPE)
	view_uniform, view_uniform_ok := get_uniform(shader, VIEW_UNIFORM_NAME, VIEW_UNIFORM_TYPE)
	projection_uniform, projection_uniform_ok := get_uniform(shader, PROJECTION_UNIFORM_NAME, PROJECTION_UNIFORM_TYPE)

	assert(model_uniform_ok)
	assert(view_uniform_ok)
	assert(projection_uniform_ok)

	va: Vertex_Array
	create_vertex_array(&va)
	set_vertex_array_format(va, TRIANGLE_VERTEX_FORMAT)
	defer destroy_vertex_array(&va)

	vb: Gl_Buffer
	create_gl_buffer_with_data(&vb, slice.to_bytes(triangle_vertices[:]))
	defer destroy_gl_buffer(&vb)

	ib: Gl_Buffer
	create_gl_buffer_with_data(&ib, slice.to_bytes(triangle_indices[:]))
	defer destroy_gl_buffer(&ib)

	bind_vertex_array(va)
	// TODO: size_of(Triangle_Vertex) shouldn't be hardcoded here.
	bind_vertex_buffer(va, vb, size_of(Triangle_Vertex))
	bind_index_buffer(va, ib)

	camera := Camera {
		position = { 0, 0, 1 },
		yaw = math.to_radians(f32(-90)),
		pitch = math.to_radians(f32(0)),
	}

	prev_cursor_pos := get_cursor_pos(window)
	prev_time := glfw.GetTime()

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		time := glfw.GetTime()
		dt := time - prev_time
		prev_time = time

		cursor_pos := get_cursor_pos(window)
		cursor_pos_delta := cursor_pos - prev_cursor_pos
		prev_cursor_pos = cursor_pos

		camera.yaw += cursor_pos_delta.x * MOUSE_SENSITIVITY * f32(dt)
		camera.pitch += -cursor_pos_delta.y * MOUSE_SENSITIVITY * f32(dt)

		camera_vectors := camera_vectors(camera)

		if glfw.GetKey(window, glfw.KEY_W) == glfw.PRESS do camera.position += camera_vectors.forward * f32(dt)
		if glfw.GetKey(window, glfw.KEY_S) == glfw.PRESS do camera.position -= camera_vectors.forward * f32(dt)
		if glfw.GetKey(window, glfw.KEY_A) == glfw.PRESS do camera.position -= camera_vectors.right * f32(dt)
		if glfw.GetKey(window, glfw.KEY_D) == glfw.PRESS do camera.position += camera_vectors.right * f32(dt)

		model: Mat4 = 1

		view := linalg.matrix4_look_at(eye = camera.position,
					       centre = camera.position + camera_vectors.forward,
					       up = camera_vectors.up)

		projection := linalg.matrix4_perspective(fovy = math.to_radians(f32(45)),
							 aspect = get_aspect_ratio(window),
							 near = 0.1,
							 far = 100)

		gl.ClearColor(0, 0, 0, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		set_uniform(model_uniform, model)
		set_uniform(view_uniform, view)
		set_uniform(projection_uniform, projection)

		// TODO: gl.UNSIGNED_INT shouldn't be hardcoded here.
		gl.DrawElements(gl.TRIANGLES, len(triangle_vertices), gl.UNSIGNED_INT, nil)

		glfw.SwapBuffers(window)
		free_all(context.temp_allocator)
	}
}
