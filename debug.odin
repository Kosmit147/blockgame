package blockgame

import "vendor/imgui"

import "core:fmt"
import "core:mem"
import "core:mem/virtual"

QUIT_GAME_KEY            :: Key.Escape
DEBUG_OVERLAY_TOGGLE_KEY :: Key.F_1
TOGGLE_CURSOR_KEY        :: Key.Left_Control

Debug_Overlay :: struct {
	enabled: bool,
	fps_limit: u32,
}

@(private="file")
s_overlay: Debug_Overlay

debug_overlay_init :: proc() -> (ok := false) {
	s_overlay.enabled = ODIN_DEBUG
	s_overlay.fps_limit = window_fps_limit() or_else 120
	ok = true
	return
}

debug_overlay_deinit :: proc() {}

debug_overlay_on_event :: proc(event: Event) {
	if key_pressed_event, is_key_pressed_event := event.(Key_Pressed_Event); is_key_pressed_event {
		if key_pressed_event.key == DEBUG_OVERLAY_TOGGLE_KEY do s_overlay.enabled = !s_overlay.enabled
	}

	if !s_overlay.enabled do return

	#partial switch event in event {
	case Key_Pressed_Event:
		if event.key == QUIT_GAME_KEY do window_close()
		else if event.key == TOGGLE_CURSOR_KEY do window_toggle_cursor()
	}
}

debug_overlay_update :: proc() {
	if !s_overlay.enabled do return

	imgui.Begin("Settings")
	full_screen := window_is_full_screen()
	if imgui.Checkbox("Fullscreen", &full_screen) do window_set_full_screen(full_screen)
	gamma := renderer_gamma()
	if imgui.DragFloat("Gamma", &gamma, 0.005, 0.1, 5.0) do renderer_set_gamma(gamma)
	fps_limit, fps_limit_set := window_fps_limit()
	if fps_limit_set do s_overlay.fps_limit = fps_limit
	if imgui.Checkbox("Enable FPS limit", &fps_limit_set) {
		if fps_limit_set do window_enable_fps_limit(s_overlay.fps_limit)
		else do window_disable_fps_limit()
	}
	if imgui_input_u32("FPS limit", &s_overlay.fps_limit) && fps_limit_set {
		window_enable_fps_limit(s_overlay.fps_limit)
	}
	imgui.TextUnformatted(fmt.ctprintf("Target frame time: %.6fs", window_target_frame_time()))
	vsync_mode := window_vsync_mode()
	if imgui_enum_select("Vertical Sync", &vsync_mode) do window_set_vsync_mode(vsync_mode)
	master_volume := sound_master_volume()
	wireframe := renderer_wireframe_enabled()
	if imgui.Checkbox("Wireframe", &wireframe) do renderer_set_wireframe_enabled(wireframe)
	if imgui.SliderFloat("Master Volume", &master_volume, 0, 1) do sound_set_master_volume(master_volume)
	music_volume := sound_music_volume()
	if imgui.SliderFloat("Music Volume", &music_volume, 0, 1) do sound_set_music_volume(music_volume)
	imgui.TextUnformatted(fmt.ctprintf("Window size: %v", window_size()))
	imgui.TextUnformatted(fmt.ctprintf("Framebuffer size: %v", window_framebuffer_size()))
	imgui.End()

	imgui.Begin("Music Player")
	track_index := sound_current_track_index()
	if imgui_slice_list_select(&track_index, sound_tracks()) do sound_play_track(track_index)
	imgui.End()

	when TRACK_MEMORY {
		tracking_allocator_info_text :: proc(allocator: mem.Tracking_Allocator) -> cstring {
			return fmt.ctprintf(
				"Current memory allocated: %v\n" +
				"Peak memory allocated: %v\n" +
				"Total allocation count: %v\n" +
				"Total free count: %v\n" +
				"Total memory allocated: %v\n" +
				"Total memory freed: %v\n",
				allocator.current_memory_allocated,
				allocator.peak_memory_allocated,
				allocator.total_allocation_count,
				allocator.total_free_count,
				allocator.total_memory_allocated,
				allocator.total_memory_freed,
			)
		}

		arena_info_text :: proc(arena: virtual.Arena) -> cstring {
			return fmt.ctprintf(
				"Total used: %v\n" +
				"Total reserved: %v\n",
				arena.total_used,
				arena.total_reserved,
			)
		}

		imgui.Begin("Memory")
		imgui.SeparatorText("Global Allocator")
		imgui.TextUnformatted(tracking_allocator_info_text(get_global_tracking_allocator()^))
		imgui.SeparatorText("World Allocator")
		imgui.TextUnformatted(tracking_allocator_info_text(get_world_tracking_allocator()^))
		imgui.SeparatorText("Sound Arena")
		imgui.TextUnformatted(arena_info_text(get_sound_arena()^))
		imgui.End()
	}
}

@(require_results)
debug_overlay_enabled :: proc() -> bool {
	return s_overlay.enabled
}
