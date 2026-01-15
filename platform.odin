package blockgame

import "vendor:glfw"
import gl "vendor:OpenGL"

import "core:log"

GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

Window :: struct {
	handle: glfw.WindowHandle,
	size: [2]i32,
	framebuffer_size: [2]i32,
	cursor_pos: Vec2, // TODO: Should be part of input.
}

@(private="file")
s_window: Window

window_init :: proc(width, height: i32, title: cstring) -> (ok := false) {
	glfw.SetErrorCallback(glfw_error_callback)
	if !glfw.Init() {
		log.fatalf("Failed to initialize GLFW.")
		return
	}

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_VERSION_MAJOR)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_VERSION_MINOR)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	glfw.WindowHint(glfw.OPENGL_DEBUG_CONTEXT, glfw.TRUE when ODIN_DEBUG else glfw.FALSE)

	s_window.handle = glfw.CreateWindow(width, height, title, nil, nil)
	if s_window.handle == nil {
		log.fatalf("Failed to create a window.")
		return
	}

	{
		size_x, size_y := glfw.GetWindowSize(s_window.handle)
		s_window.size = { size_x, size_y }
		framebuffer_size_x, framebuffer_size_y := glfw.GetFramebufferSize(s_window.handle)
		s_window.framebuffer_size = { framebuffer_size_x, framebuffer_size_y }
		cursor_pos_x, cursor_pos_y := glfw.GetCursorPos(s_window.handle)
		s_window.cursor_pos = { f32(cursor_pos_x), f32(cursor_pos_y) }
	}

	glfw.MakeContextCurrent(s_window.handle)
	init_gl_context()

	glfw.SetWindowSizeCallback(s_window.handle, glfw_window_size_callback)
	glfw.SetFramebufferSizeCallback(s_window.handle, glfw_framebuffer_size_callback)
	glfw.SetCursorPosCallback(s_window.handle, glfw_cursor_pos_callback)
	glfw.SetKeyCallback(s_window.handle, glfw_key_callback)

	glfw.SetInputMode(s_window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
	if glfw.RawMouseMotionSupported() do glfw.SetInputMode(s_window.handle, glfw.RAW_MOUSE_MOTION, glfw.TRUE)

	return true
}

window_deinit :: proc() {
	glfw.DestroyWindow(s_window.handle)
	glfw.Terminate()
	s_window.handle = nil
}

window_should_close :: proc() -> bool {
	return bool(glfw.WindowShouldClose(s_window.handle))
}

window_close :: proc() {
	glfw.SetWindowShouldClose(s_window.handle, glfw.TRUE)
}

window_poll_events :: proc() {
	glfw.PollEvents()
}

window_swap_buffers :: proc() {
	glfw.SwapBuffers(s_window.handle)
}

window_time :: proc() -> f64 {
	return glfw.GetTime()
}

window_aspect_ratio :: proc() -> f32 {
	return f32(s_window.size.x) / f32(s_window.size.y)
}

window_width :: proc() -> i32 {
	return s_window.size.x
}

window_height :: proc() -> i32 {
	return s_window.size.y
}

window_size :: proc() -> [2]i32 {
	return s_window.size
}

window_framebuffer_size :: proc() -> [2]i32 {
	return s_window.framebuffer_size
}

window_cursor_pos :: proc() -> Vec2 {
	return s_window.cursor_pos
}

window_handle :: proc() -> glfw.WindowHandle {
	return s_window.handle
}

@(private="file")
glfw_error_callback :: proc "c" (error: i32, description: cstring) {
	context = g_context
	log.errorf("GLFW Error %v: %v", error, description)
}

@(private="file")
glfw_key_callback :: proc "c" (window_handle: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = g_context

	switch key {
	case 'A'..='Z', 'a'..='z':
		log.debugf("Key %v pressed", rune(key))
	case:
		log.debugf("Key %v pressed", key)
	}

	if key == glfw.KEY_ESCAPE && action == glfw.PRESS do window_close()
}

@(private="file")
glfw_window_size_callback :: proc "c" (window_handle: glfw.WindowHandle, width, height: i32) {
	s_window.size.x, s_window.size.y = width, height
}

@(private="file")
glfw_framebuffer_size_callback :: proc "c" (window_handle: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)
	s_window.framebuffer_size.x, s_window.framebuffer_size.y = width, height
}

@(private="file")
glfw_cursor_pos_callback :: proc "c" (window_handle: glfw.WindowHandle, xpos, ypos: f64) {
	s_window.cursor_pos.x, s_window.cursor_pos.y = f32(xpos), f32(ypos)
}

init_gl_context :: proc() {
	gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, glfw.gl_set_proc_address)

	when ODIN_DEBUG {
		gl.Enable(gl.DEBUG_OUTPUT)
		gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
		gl.DebugMessageCallback(gl_debug_message_callback, nil)

		log.infof("Vendor: %v", gl.GetString(gl.VENDOR))
		log.infof("Renderer: %v", gl.GetString(gl.RENDERER))
		log.infof("Version: %v", gl.GetString(gl.VERSION))
	}

	gl.Viewport(0, 0, s_window.framebuffer_size.x, s_window.framebuffer_size.y)
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
		context = g_context

		switch severity {
		case gl.DEBUG_SEVERITY_NOTIFICATION:
			log.debugf("OpenGL Notification: %v", message)
		case gl.DEBUG_SEVERITY_LOW:
			log.warnf("OpenGL Warning: %v", message)
		case gl.DEBUG_SEVERITY_MEDIUM, gl.DEBUG_SEVERITY_HIGH:
			log.errorf("OpenGL Error: %v", message)
		case:
			assert(false)
			log.errorf("Unrecognized OpenGL debug message severity: %X", severity)
		}
	}

}
