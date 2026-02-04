package blockgame

import "core:sys/windows"

@(private="file")
s_swap_interval_proc: windows.SwapIntervalEXTType

window_platform_init :: proc "contextless" () {
	s_swap_interval_proc = auto_cast windows.wglGetProcAddress("wglSwapIntervalEXT")
}

window_platform_set_vsync_mode :: proc "contextless" (mode: V_Sync_Mode) {
	s_swap_interval_proc(i32(mode))
}
