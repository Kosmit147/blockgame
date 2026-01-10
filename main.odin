package blockgame

import "base:runtime"

import "vendor:glfw"
import gl "vendor:OpenGL"

import "core:fmt"
import "core:os"

GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
INITIAL_WINDOW_WIDTH :: 1080
INITIAL_WINDOW_HEIGHT :: 1080
WINDOW_TITLE :: "Blockgame"

VERTEX_SHADER_SOURCE ::
`
#version 460 core

void main()
{
	gl_Position = vec4(0, 0, 0, 1);
}
`

FRAGMENT_SHADER_SOURCE ::
`
#version 460 core

out vec4 outColor;

void main()
{
	outColor = vec4(1, 1, 1, 1);
}
`

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

@(private="file")
gl_debug_message_callback :: proc "c" (
	source, type, id, severity: u32,
	length: i32,
	message: cstring,
	user_ptr: rawptr) {
	context = runtime.default_context()
	fmt.printfln("OpenGL message: %v", message)
}

// TODO List:
// - Use the context's logger
// - Disable OpenGL debug context in non-debug builds

main :: proc() {
	glfw.SetErrorCallback(glfw_error_callback)

	if !bool(glfw.Init()) {
		fmt.eprintln("Failed to initialize GLFW.")
		os.exit(-1)
	}

	defer glfw.Terminate()

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_VERSION_MAJOR)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_VERSION_MINOR)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_DEBUG_CONTEXT, glfw.TRUE)

	window := glfw.CreateWindow(INITIAL_WINDOW_WIDTH, INITIAL_WINDOW_HEIGHT, WINDOW_TITLE, nil, nil)

	if window == nil {
		fmt.eprintln("Failed to create a window.")
		os.exit(-1)
	}

	defer glfw.DestroyWindow(window)

	glfw.MakeContextCurrent(window)
	gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, glfw.gl_set_proc_address)
	gl.Enable(gl.DEBUG_OUTPUT)
	gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
	gl.DebugMessageCallback(gl_debug_message_callback, nil)
	gl.Viewport(0, 0, INITIAL_WINDOW_WIDTH, INITIAL_WINDOW_HEIGHT)

	glfw.SetFramebufferSizeCallback(window, glfw_framebuffer_size_callback)
	glfw.SetKeyCallback(window, glfw_key_callback)

	shader: Shader
	if !create_shader(&shader, VERTEX_SHADER_SOURCE, FRAGMENT_SHADER_SOURCE) {
		fmt.eprintln("Failed to compile the shader.")
		os.exit(-1)
	}
	defer destroy_shader(&shader)

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		gl.ClearColor(0, 0, 0, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		glfw.SwapBuffers(window)
		free_all(context.temp_allocator)
	}
}
