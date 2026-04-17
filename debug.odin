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
	if imgui.BeginTabBar("Settings Tab Bar") {
		if imgui.BeginTabItem("Window") {
			full_screen := window_is_full_screen()
			if imgui.Checkbox("Fullscreen", &full_screen) do window_set_full_screen(full_screen)
			vsync_mode := window_vsync_mode()
			if imgui_enum_select("Vertical Sync", &vsync_mode) do window_set_vsync_mode(vsync_mode)
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
			imgui.TextUnformatted(fmt.ctprintf("Window size: %v", window_size()))
			imgui.TextUnformatted(fmt.ctprintf("Framebuffer size: %v", window_framebuffer_size()))
			imgui.EndTabItem()
		}
		if imgui.BeginTabItem("Renderer") {
			gamma := renderer_gamma()
			if imgui.DragFloat("Gamma", &gamma, 0.005, 0.1, 5.0) do renderer_set_gamma(gamma)
			wireframe := renderer_wireframe_enabled()
			if imgui.Checkbox("Wireframe", &wireframe) do renderer_set_wireframe_enabled(wireframe)
			imgui.SeparatorText("OpenGL context info")
			imgui.TextUnformatted(fmt.ctprintf("Vendor: %v", gl_get_vendor()))
			imgui.TextUnformatted(fmt.ctprintf("Renderer: %v", gl_get_renderer()))
			imgui.TextUnformatted(fmt.ctprintf("Version: %v", gl_get_version()))
			imgui.SeparatorText("OpenGL extensions")
			for extension in gl_get_extensions() {
				imgui.TextUnformatted(extension)
			}
			imgui.EndTabItem()
		}
		if imgui.BeginTabItem("Sound") {
			master_volume := sound_master_volume()
			if imgui.SliderFloat("Master Volume", &master_volume, 0, 1) do sound_set_master_volume(master_volume)
			music_volume := sound_music_volume()
			if imgui.SliderFloat("Music Volume", &music_volume, 0, 1) do sound_set_music_volume(music_volume)
			imgui.EndTabItem()
		}
		imgui.EndTabBar()
	}
	imgui.End()

	imgui.Begin("Music Player")
	track_index := sound_current_track_index()
	if imgui_slice_list_select(&track_index, sound_tracks()) do sound_play_track(track_index)
	imgui.End()

	memory_window()
}

@(require_results)
debug_overlay_enabled :: proc() -> bool {
	return s_overlay.enabled
}

@(private="file")
memory_window :: proc() {
	gpu_memory_info, have_gpu_memory_info := get_gpu_memory_info()
	show_memory_window := have_gpu_memory_info || TRACK_MEMORY
	if !show_memory_window do return

	format_memory_size :: proc(#any_int size: int) -> string {
		switch size {
		case 0..<512 * mem.Byte:
			return fmt.tprintf("%v B", size)
		case 512 * mem.Byte..<512 * mem.Kilobyte:
			return fmt.tprintf("%.2f KB", f64(size) / mem.Kilobyte)
		case 512 * mem.Kilobyte..<512 * mem.Megabyte:
			return fmt.tprintf("%.2f MB", f64(size) / mem.Megabyte)
		case:
			return fmt.tprintf("%.2f GB", f64(size) / mem.Gigabyte)
		}
	}

	imgui.Begin("Memory")
	if imgui.BeginTabBar("Memory Tab Bar") {
		when TRACK_MEMORY {
			if imgui.BeginTabItem("RAM") {
				tracking_allocator_info_text :: proc(allocator: mem.Tracking_Allocator) -> cstring {
					return fmt.ctprintf(
						"Current memory allocated: %v\n" +
						"Peak memory allocated: %v\n" +
						"Total allocation count: %v\n" +
						"Total free count: %v\n" +
						"Total memory allocated: %v\n" +
						"Total memory freed: %v\n",
						format_memory_size(allocator.current_memory_allocated),
						format_memory_size(allocator.peak_memory_allocated),
						allocator.total_allocation_count,
						allocator.total_free_count,
						format_memory_size(allocator.total_memory_allocated),
						format_memory_size(allocator.total_memory_freed),
					)
				}

				arena_info_text :: proc(arena: virtual.Arena) -> cstring {
					return fmt.ctprintf(
						"Total used: %v\n" +
						"Total reserved: %v\n",
						format_memory_size(arena.total_used),
						format_memory_size(arena.total_reserved),
					)
				}

				imgui.SeparatorText("Global Allocator")
				imgui.TextUnformatted(tracking_allocator_info_text(get_global_tracking_allocator()^))
				imgui.SeparatorText("World Allocator")
				imgui.TextUnformatted(tracking_allocator_info_text(get_world_tracking_allocator()^))
				imgui.SeparatorText("Sound Arena")
				imgui.TextUnformatted(arena_info_text(get_sound_arena()^))
				imgui.EndTabItem()
			}
		}
		if have_gpu_memory_info {
			if imgui.BeginTabItem("VRAM") {
				gpu_memory_info_text :: proc(info: Gpu_Memory_Info) -> cstring {
					return fmt.ctprintf(
						"Dedicated video memory: %v\n" +
						"Total available memory: %v\n" +
						"Current available memory: %v\n" +
						"Eviction count: %v\n" +
						"Evicted memory: %v\n",
						format_memory_size(info.dedicated_vidmem_kb * mem.Kilobyte),
						format_memory_size(info.total_available_memory_kb * mem.Kilobyte),
						format_memory_size(info.current_available_vidmem_kb * mem.Kilobyte),
						info.eviction_count,
						format_memory_size(info.evicted_memory_kb * mem.Kilobyte))
				}

				imgui.TextUnformatted(gpu_memory_info_text(gpu_memory_info))
				imgui.EndTabItem()
			}
		}
		imgui.EndTabBar()
	}
	imgui.End()
}
