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

glfw_error_callback :: proc "c" (error: i32, description: cstring) {
	context = runtime.default_context()
	fmt.eprintfln("GLFW Error %v: %v", error, description)
}

// TODO List:
// - Use the context's logger

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

	window := glfw.CreateWindow(INITIAL_WINDOW_WIDTH, INITIAL_WINDOW_HEIGHT, WINDOW_TITLE, nil, nil)

	if window == nil {
		fmt.eprintln("Failed to create a window.")
		os.exit(-1)
	}

	defer glfw.DestroyWindow(window)

	glfw.MakeContextCurrent(window)
	gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, glfw.gl_set_proc_address)

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		gl.ClearColor(0, 0, 0, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		glfw.SwapBuffers(window)
	}
}
