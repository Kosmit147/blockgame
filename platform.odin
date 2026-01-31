package blockgame

import "vendor:glfw"
import gl "vendor:OpenGL"
import "vendor/imgui"
import "vendor/imgui/imgui_impl_glfw"
import "vendor/imgui/imgui_impl_opengl3"

import "core:log"
import "core:container/queue"

GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6
IMGUI_FONT_SCALE :: 1.5

Window :: struct {
	handle: glfw.WindowHandle,
	size: [2]i32,
	framebuffer_size: [2]i32,
	cursor_enabled: bool,
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

	glfw.WindowHint(glfw.MAXIMIZED, glfw.TRUE)

	s_window.handle = glfw.CreateWindow(width, height, title, nil, nil)
	if s_window.handle == nil {
		log.fatalf("Failed to create a window.")
		return
	}

	window_update_size()
	window_update_framebuffer_size()
	input_update_cursor_pos()

	glfw.MakeContextCurrent(s_window.handle)

	window_init_event_queue()
	glfw.SetWindowSizeCallback(s_window.handle, glfw_window_size_callback)
	glfw.SetFramebufferSizeCallback(s_window.handle, glfw_framebuffer_size_callback)
	glfw.SetKeyCallback(s_window.handle, glfw_key_callback)
	glfw.SetCursorPosCallback(s_window.handle, glfw_cursor_pos_callback)
	glfw.SetMouseButtonCallback(s_window.handle, glfw_mouse_button_callback)

	window_set_cursor_enabled(false)
	if glfw.RawMouseMotionSupported() do glfw.SetInputMode(s_window.handle, glfw.RAW_MOUSE_MOTION, glfw.TRUE)

	ok = true
	return
}

window_deinit :: proc() {
	window_deinit_event_queue()
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
	input_new_frame()
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

@(private="file")
window_update_size :: proc() {
	window_size_x, window_size_y := glfw.GetWindowSize(s_window.handle)
	s_window.size = { window_size_x, window_size_y }
}

@(private="file")
window_update_framebuffer_size :: proc() {
	framebuffer_size_x, framebuffer_size_y := glfw.GetFramebufferSize(s_window.handle)
	s_window.framebuffer_size = { framebuffer_size_x, framebuffer_size_y }
}

window_handle :: proc() -> glfw.WindowHandle {
	return s_window.handle
}

window_cursor_enabled :: proc() -> bool {
	return s_window.cursor_enabled
}

window_set_cursor_enabled :: proc(cursor_enabled: bool) {
	glfw.SetInputMode(s_window.handle, glfw.CURSOR, glfw.CURSOR_NORMAL if cursor_enabled else glfw.CURSOR_DISABLED)
	s_window.cursor_enabled = cursor_enabled
	input_update_cursor_pos()
}

window_toggle_cursor :: proc() {
	window_set_cursor_enabled(!s_window.cursor_enabled)
}

normalize_screen_position_i :: proc(screen_position: [2]i32) -> Vec2 {
	screen_position := Vec2{ f32(screen_position.x), f32(screen_position.y) }
	return normalize_screen_position_f(screen_position)
}

normalize_screen_position_f :: proc(screen_position: Vec2) -> Vec2 {
	window_size := Vec2{ f32(s_window.size.x), f32(s_window.size.y) }
	normalized := screen_position / window_size * 2 - 1
	normalized.y = -normalized.y
	return normalized
}

normalize_screen_position :: proc{ normalize_screen_position_i, normalize_screen_position_f }

normalize_screen_size_i :: proc(screen_size: [2]i32) -> Vec2 {
	screen_size := Vec2{ f32(screen_size.x), f32(screen_size.y) }
	return normalize_screen_size_f(screen_size)
}

normalize_screen_size_f :: proc(screen_size: Vec2) -> Vec2 {
	window_size := Vec2{ f32(s_window.size.x), f32(s_window.size.y) }
	return screen_size / window_size * 2
}

normalize_screen_size :: proc{ normalize_screen_size_i, normalize_screen_size_f }

Key :: enum u8 {
	Space,
	Apostrophe,
	Comma,
	Minus,
	Period,
	Slash,
	Semicolon,
	Equal,
	Left_Bracket,
	Backslash,
	Right_Bracket,
	Grave_Accent,
	World_1,
	World_2,

	Num_0,
	Num_1,
	Num_2,
	Num_3,
	Num_4,
	Num_5,
	Num_6,
	Num_7,
	Num_8,
	Num_9,

	A,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,

	Escape,
	Enter,
	Tab,
	Backspace,
	Insert,
	Delete,
	Right,
	Left,
	Down,
	Up,
	Page_Up,
	Page_Down,
	Home,
	End,
	Caps_Lock,
	Scroll_Lock,
	Num_Lock,
	Print_Screen,
	Pause,

	F_1,
	F_2,
	F_3,
	F_4,
	F_5,
	F_6,
	F_7,
	F_8,
	F_9,
	F_10,
	F_11,
	F_12,
	F_13,
	F_14,
	F_15,
	F_16,
	F_17,
	F_18,
	F_19,
	F_20,
	F_21,
	F_22,
	F_23,
	F_24,
	F_25,

	KP_0,
	KP_1,
	KP_2,
	KP_3,
	KP_4,
	KP_5,
	KP_6,
	KP_7,
	KP_8,
	KP_9,

	KP_Decimal,
	KP_Divide,
	KP_Multiply,
	KP_Subtract,
	KP_Add,
	KP_Enter,
	KP_Equal,

	Left_Shift,
	Left_Control,
	Left_Alt,
	Left_Super,
	Right_Shift,
	Right_Control,
	Right_Alt,
	Right_Super,
	Menu,

	Unknown,
}

@(private="file")
map_glfw_key :: proc "contextless" (glfw_key: i32) -> Key {
	switch glfw_key {
	case glfw.KEY_SPACE:          return .Space
	case glfw.KEY_APOSTROPHE:     return .Apostrophe
	case glfw.KEY_COMMA:          return .Comma
	case glfw.KEY_MINUS:          return .Minus
	case glfw.KEY_PERIOD:         return .Period
	case glfw.KEY_SLASH:          return .Slash
	case glfw.KEY_SEMICOLON:      return .Semicolon
	case glfw.KEY_EQUAL:          return .Equal
	case glfw.KEY_LEFT_BRACKET:   return .Left_Bracket
	case glfw.KEY_BACKSLASH:      return .Backslash
	case glfw.KEY_RIGHT_BRACKET:  return .Right_Bracket
	case glfw.KEY_GRAVE_ACCENT:   return .Grave_Accent
	case glfw.KEY_WORLD_1:        return .World_1
	case glfw.KEY_WORLD_2:        return .World_2

	case glfw.KEY_0:              return .Num_0
	case glfw.KEY_1:              return .Num_1
	case glfw.KEY_2:              return .Num_2
	case glfw.KEY_3:              return .Num_3
	case glfw.KEY_4:              return .Num_4
	case glfw.KEY_5:              return .Num_5
	case glfw.KEY_6:              return .Num_6
	case glfw.KEY_7:              return .Num_7
	case glfw.KEY_8:              return .Num_8
	case glfw.KEY_9:              return .Num_9

	case glfw.KEY_A:              return .A
	case glfw.KEY_B:              return .B
	case glfw.KEY_C:              return .C
	case glfw.KEY_D:              return .D
	case glfw.KEY_E:              return .E
	case glfw.KEY_F:              return .F
	case glfw.KEY_G:              return .G
	case glfw.KEY_H:              return .H
	case glfw.KEY_I:              return .I
	case glfw.KEY_J:              return .J
	case glfw.KEY_K:              return .K
	case glfw.KEY_L:              return .L
	case glfw.KEY_M:              return .M
	case glfw.KEY_N:              return .N
	case glfw.KEY_O:              return .O
	case glfw.KEY_P:              return .P
	case glfw.KEY_Q:              return .Q
	case glfw.KEY_R:              return .R
	case glfw.KEY_S:              return .S
	case glfw.KEY_T:              return .T
	case glfw.KEY_U:              return .U
	case glfw.KEY_V:              return .V
	case glfw.KEY_W:              return .W
	case glfw.KEY_X:              return .X
	case glfw.KEY_Y:              return .Y
	case glfw.KEY_Z:              return .Z

	case glfw.KEY_ESCAPE:         return .Escape
	case glfw.KEY_ENTER:          return .Enter
	case glfw.KEY_TAB:            return .Tab
	case glfw.KEY_BACKSPACE:      return .Backspace
	case glfw.KEY_INSERT:         return .Insert
	case glfw.KEY_DELETE:         return .Delete
	case glfw.KEY_RIGHT:          return .Right
	case glfw.KEY_LEFT:           return .Left
	case glfw.KEY_DOWN:           return .Down
	case glfw.KEY_UP:             return .Up
	case glfw.KEY_PAGE_UP:        return .Page_Up
	case glfw.KEY_PAGE_DOWN:      return .Page_Down
	case glfw.KEY_HOME:           return .Home
	case glfw.KEY_END:            return .End
	case glfw.KEY_CAPS_LOCK:      return .Caps_Lock
	case glfw.KEY_SCROLL_LOCK:    return .Scroll_Lock
	case glfw.KEY_NUM_LOCK:       return .Num_Lock
	case glfw.KEY_PRINT_SCREEN:   return .Print_Screen
	case glfw.KEY_PAUSE:          return .Pause

	case glfw.KEY_F1:             return .F_1
	case glfw.KEY_F2:             return .F_2
	case glfw.KEY_F3:             return .F_3
	case glfw.KEY_F4:             return .F_4
	case glfw.KEY_F5:             return .F_5
	case glfw.KEY_F6:             return .F_6
	case glfw.KEY_F7:             return .F_7
	case glfw.KEY_F8:             return .F_8
	case glfw.KEY_F9:             return .F_9
	case glfw.KEY_F10:            return .F_10
	case glfw.KEY_F11:            return .F_11
	case glfw.KEY_F12:            return .F_12
	case glfw.KEY_F13:            return .F_13
	case glfw.KEY_F14:            return .F_14
	case glfw.KEY_F15:            return .F_15
	case glfw.KEY_F16:            return .F_16
	case glfw.KEY_F17:            return .F_17
	case glfw.KEY_F18:            return .F_18
	case glfw.KEY_F19:            return .F_19
	case glfw.KEY_F20:            return .F_20
	case glfw.KEY_F21:            return .F_21
	case glfw.KEY_F22:            return .F_22
	case glfw.KEY_F23:            return .F_23
	case glfw.KEY_F24:            return .F_24
	case glfw.KEY_F25:            return .F_25

	case glfw.KEY_KP_0:           return .KP_0
	case glfw.KEY_KP_1:           return .KP_1
	case glfw.KEY_KP_2:           return .KP_2
	case glfw.KEY_KP_3:           return .KP_3
	case glfw.KEY_KP_4:           return .KP_4
	case glfw.KEY_KP_5:           return .KP_5
	case glfw.KEY_KP_6:           return .KP_6
	case glfw.KEY_KP_7:           return .KP_7
	case glfw.KEY_KP_8:           return .KP_8
	case glfw.KEY_KP_9:           return .KP_9

	case glfw.KEY_KP_DECIMAL:     return .KP_Decimal
	case glfw.KEY_KP_DIVIDE:      return .KP_Divide
	case glfw.KEY_KP_MULTIPLY:    return .KP_Multiply
	case glfw.KEY_KP_SUBTRACT:    return .KP_Subtract
	case glfw.KEY_KP_ADD:         return .KP_Add
	case glfw.KEY_KP_ENTER:       return .KP_Enter
	case glfw.KEY_KP_EQUAL:       return .KP_Equal

	case glfw.KEY_LEFT_SHIFT:     return .Left_Shift
	case glfw.KEY_LEFT_CONTROL:   return .Left_Control
	case glfw.KEY_LEFT_ALT:       return .Left_Alt
	case glfw.KEY_LEFT_SUPER:     return .Left_Super
	case glfw.KEY_RIGHT_SHIFT:    return .Right_Shift
	case glfw.KEY_RIGHT_CONTROL:  return .Right_Control
	case glfw.KEY_RIGHT_ALT:      return .Right_Alt
	case glfw.KEY_RIGHT_SUPER:    return .Right_Super
	case glfw.KEY_MENU:           return .Menu
	case:                         return .Unknown
	}
}

Mouse_Button :: enum u8 {
	Button_1,
	Button_2,
	Button_3,
	Button_4,
	Button_5,
	Button_6,
	Button_7,
	Button_8,

	Unknown,

	Left   = Button_1,
	Right  = Button_2,
	Middle = Button_3,
}

@(private="file")
map_glfw_mouse_button :: proc "contextless" (glfw_mouse_button: i32) -> Mouse_Button {
	switch glfw_mouse_button {
 	case glfw.MOUSE_BUTTON_1:  return .Button_1
 	case glfw.MOUSE_BUTTON_2:  return .Button_2
 	case glfw.MOUSE_BUTTON_3:  return .Button_3
 	case glfw.MOUSE_BUTTON_4:  return .Button_4
 	case glfw.MOUSE_BUTTON_5:  return .Button_5
 	case glfw.MOUSE_BUTTON_6:  return .Button_6
 	case glfw.MOUSE_BUTTON_7:  return .Button_7
 	case glfw.MOUSE_BUTTON_8:  return .Button_8
	case:                      return .Unknown
	}
}

Input :: struct {
	pressed_keys: bit_set[Key],
	pressed_mouse_buttons: bit_set[Mouse_Button],
	cursor_pos: Vec2,
	cursor_pos_delta: Vec2,
}

@(private="file")
s_input: Input

@(private="file")
input_new_frame :: proc() {
	s_input.cursor_pos_delta = 0
}

input_key_pressed :: proc(key: Key) -> bool {
	return key in s_input.pressed_keys
}

input_mouse_button_pressed :: proc(mouse_button: Mouse_Button) -> bool {
	return mouse_button in s_input.pressed_mouse_buttons
}

input_cursor_pos :: proc() -> Vec2 {
	return s_input.cursor_pos
}

input_cursor_pos_delta :: proc() -> Vec2 {
	return s_input.cursor_pos_delta
}

@(private="file")
input_update_cursor_pos :: proc() {
	cursor_pos_x, cursor_pos_y := glfw.GetCursorPos(s_window.handle)
	s_input.cursor_pos = { f32(cursor_pos_x), f32(cursor_pos_y) }
}

@(private="file")
glfw_error_callback :: proc "c" (error: i32, description: cstring) {
	context = g_context
	log.errorf("GLFW Error %v: %v", error, description)
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

Key_Pressed_Event :: struct {
	key: Key,
}

@(private="file")
glfw_key_callback :: proc "c" (window_handle: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = g_context
	key := map_glfw_key(key)
	if action == glfw.PRESS {
		s_input.pressed_keys += { key }
		window_push_event(Key_Pressed_Event{ key })
	} else if action == glfw.RELEASE { 
		s_input.pressed_keys -= { key }
	}
}

@(private="file")
glfw_cursor_pos_callback :: proc "c" (window_handle: glfw.WindowHandle, xpos, ypos: f64) {
	new_pos := Vec2{ f32(xpos), f32(ypos) }
	s_input.cursor_pos_delta += (new_pos - s_input.cursor_pos)
	s_input.cursor_pos = new_pos
}

Mouse_Button_Pressed_Event :: struct {
	button: Mouse_Button,
}

@(private="file")
glfw_mouse_button_callback :: proc "c" (window_handle: glfw.WindowHandle, button, action, mods: i32) {
	context = g_context
	button := map_glfw_mouse_button(button)
	if action == glfw.PRESS { 
		s_input.pressed_mouse_buttons += { button }
		window_push_event(Mouse_Button_Pressed_Event{ button })
	} else if action == glfw.RELEASE {
		s_input.pressed_mouse_buttons -= { button }
	}
}

Event :: union #no_nil {
	Key_Pressed_Event,
	Mouse_Button_Pressed_Event,
}

@(private="file")
s_event_queue: queue.Queue(Event)

@(private="file")
window_init_event_queue :: proc() {
	queue.init(&s_event_queue)
}

@(private="file")
window_deinit_event_queue :: proc() {
	queue.destroy(&s_event_queue)
}

window_pop_event :: proc() -> (Event, bool) {
	return queue.pop_front_safe(&s_event_queue)
}

window_push_event :: proc(event: Event) {
	queue.push_back(&s_event_queue, event)
}

init_gl_context :: proc() {
	gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, glfw.gl_set_proc_address)

	when ODIN_DEBUG {
		gl.Enable(gl.DEBUG_OUTPUT)
		gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS)
		gl.DebugMessageCallback(gl_debug_message_callback, nil)

		disabled_messages := [?]u32{
			131185, // Buffer detailed info from NVIDIA.
		}
		gl.DebugMessageControl(source = gl.DEBUG_SOURCE_API,
				       type = gl.DEBUG_TYPE_OTHER,
				       severity = gl.DONT_CARE,
				       count = len(disabled_messages),
				       ids = raw_data(&disabled_messages),
				       enabled = gl.FALSE)

		log.infof("Vendor: %v", gl.GetString(gl.VENDOR))
		log.infof("Renderer: %v", gl.GetString(gl.RENDERER))
		log.infof("Version: %v", gl.GetString(gl.VERSION))
	}

	gl.Viewport(0, 0, s_window.framebuffer_size.x, s_window.framebuffer_size.y)
}

init_imgui :: proc() {
	imgui.CHECKVERSION()
	imgui.CreateContext()

	io := imgui.GetIO()
	io.ConfigFlags += { .DockingEnable, .ViewportsEnable }
	io.FontGlobalScale = IMGUI_FONT_SCALE

	imgui_impl_glfw.InitForOpenGL(s_window.handle, install_callbacks = true)
	imgui_impl_opengl3.Init("#version 430 core")
}

deinit_imgui :: proc() {
	imgui_impl_opengl3.Shutdown()
	imgui_impl_glfw.Shutdown()
	imgui.DestroyContext()
}

imgui_new_frame :: proc() {
	imgui_impl_opengl3.NewFrame()
	imgui_impl_glfw.NewFrame()
	imgui.NewFrame()
}

imgui_render :: proc() {
	imgui.Render()
	imgui_impl_opengl3.RenderDrawData(imgui.GetDrawData())
	imgui.UpdatePlatformWindows()
	imgui.RenderPlatformWindowsDefault()
	glfw.MakeContextCurrent(s_window.handle)
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
		case gl.DEBUG_SEVERITY_LOW, gl.DEBUG_SEVERITY_MEDIUM:
			log.warnf("OpenGL Warning: %v", message)
		case gl.DEBUG_SEVERITY_HIGH:
			log.errorf("OpenGL Error: %v", message)
		case:
			assert(false)
			log.errorf("Unrecognized OpenGL debug message severity: %X", severity)
		}
	}
}
