package blockgame

import "base:runtime"

import "vendor:glfw"
import gl "vendor:OpenGL"

import "core:fmt"

GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

Window :: struct {
	handle: glfw.WindowHandle,
	size: [2]i32,
	framebuffer_size: [2]i32,
	cursor_pos: [2]f32, // TODO: Should be part of input.
}

g_window: Window

create_window :: proc(width, height: i32, title: cstring) -> (ok := false) {
	glfw.SetErrorCallback(glfw_error_callback)
	if !glfw.Init() {
		fmt.eprintln("Failed to initialize GLFW.")
		return
	}

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_VERSION_MAJOR)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_VERSION_MINOR)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_DEBUG_CONTEXT, glfw.TRUE when ODIN_DEBUG else glfw.FALSE)

	g_window.handle = glfw.CreateWindow(width, height, title, nil, nil)
	if g_window.handle == nil {
		fmt.eprintln("Failed to create a window.")
		return
	}

	{
		size_x, size_y := glfw.GetWindowSize(g_window.handle)
		g_window.size = { size_x, size_y }
		framebuffer_size_x, framebuffer_size_y := glfw.GetFramebufferSize(g_window.handle)
		g_window.framebuffer_size = { framebuffer_size_x, framebuffer_size_y }
		cursor_pos_x, cursor_pos_y := glfw.GetCursorPos(g_window.handle)
		g_window.cursor_pos = { f32(cursor_pos_x), f32(cursor_pos_y) }
	}

	glfw.MakeContextCurrent(g_window.handle)
	init_gl_context()

	glfw.SetWindowSizeCallback(g_window.handle, glfw_window_size_callback)
	glfw.SetFramebufferSizeCallback(g_window.handle, glfw_framebuffer_size_callback)
	glfw.SetCursorPosCallback(g_window.handle, glfw_cursor_pos_callback)
	glfw.SetKeyCallback(g_window.handle, glfw_key_callback)

	glfw.SetInputMode(g_window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)

	if glfw.RawMouseMotionSupported() {
		glfw.SetInputMode(g_window.handle, glfw.RAW_MOUSE_MOTION, glfw.TRUE)
	}

	return true
}

destroy_window :: proc() {
	glfw.DestroyWindow(g_window.handle)
	glfw.Terminate()
	g_window.handle = nil
}

window_should_close :: proc() -> bool {
	return bool(glfw.WindowShouldClose(g_window.handle))
}

close_window :: proc() {
	glfw.SetWindowShouldClose(g_window.handle, glfw.TRUE)
}

poll_window_events :: proc() {
	glfw.PollEvents()
}

swap_window_buffers :: proc() {
	glfw.SwapBuffers(g_window.handle)
}

window_time :: proc() -> f64 {
	return glfw.GetTime()
}

window_aspect_ratio :: proc() -> f32 {
	return f32(g_window.size.x) / f32(g_window.size.y)
}

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

	if key == glfw.KEY_ESCAPE && action == glfw.PRESS do close_window()
}

@(private="file")
glfw_window_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	g_window.size.x, g_window.size.y = width, height
}

@(private="file")
glfw_framebuffer_size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)
	g_window.framebuffer_size.x, g_window.framebuffer_size.y = width, height
}

@(private="file")
glfw_cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, xpos, ypos: f64) {
	g_window.cursor_pos.x = f32(xpos)
	g_window.cursor_pos.y = f32(ypos)
}

init_gl_context :: proc() {
	gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, glfw.gl_set_proc_address)

	when ODIN_DEBUG {
		gl.Enable(gl.DEBUG_OUTPUT)
		gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
		gl.DebugMessageCallback(gl_debug_message_callback, nil)

		fmt.printfln("Vendor: %v", gl.GetString(gl.VENDOR))
		fmt.printfln("Renderer: %v", gl.GetString(gl.RENDERER))
		fmt.printfln("Version: %v", gl.GetString(gl.VERSION))
	}

	gl.Viewport(0, 0, g_window.framebuffer_size.x, g_window.framebuffer_size.y)
	gl.Enable(gl.CULL_FACE)
	gl.CullFace(gl.BACK)
	gl.FrontFace(gl.CCW)
	gl.Enable(gl.DEPTH_TEST)
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
