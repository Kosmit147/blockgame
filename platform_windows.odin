package blockgame

import "core:sys/windows"
import "core:time"

@(private="file")
s_swap_interval_proc: windows.SwapIntervalEXTType

platform_window_init :: proc "contextless" () {
	s_swap_interval_proc = auto_cast windows.wglGetProcAddress("wglSwapIntervalEXT")
}

platform_window_set_vsync_mode :: proc "contextless" (mode: V_Sync_Mode) {
	s_swap_interval_proc(i32(mode))
}

platform_accurate_sleep :: proc(seconds: f64) {
	windows.timeBeginPeriod(1)
	time.accurate_sleep(time.Duration(seconds * f64(time.Second)))
	windows.timeEndPeriod(1)
}
