package blockgame

import "base:runtime"

import "vendor/dmon"

import "core:log"
import "core:mem"
import "core:strings"
import "core:os"

HOT_RELOAD   :: #config(HOT_RELOAD, false)
TRACK_MEMORY :: #config(TRACK_MEMORY, ODIN_DEBUG)

when HOT_RELOAD {
	// This callback gets called from a separate thread.
	@(private="file")
	watcher_callback :: proc "c" (watch_id: dmon.Watch_Id,
				      action: dmon.Action,
				      rootdir: cstring,
				      filepath: cstring,
				      oldfilepath: cstring,
				      user: rawptr) {
		context = g_context

		full_path_builder := strings.builder_make(context.temp_allocator)
		defer strings.builder_destroy(&full_path_builder)
		strings.write_string(&full_path_builder, string(rootdir))
		strings.write_string(&full_path_builder, string(filepath))
		full_path := strings.to_string(full_path_builder)
		request_resource_reload(full_path)
	}
}

g_context: runtime.Context
when TRACK_MEMORY {
	@(private="file") s_tracking_allocator: mem.Tracking_Allocator
	get_global_tracking_allocator :: proc() -> ^mem.Tracking_Allocator {
		return &s_tracking_allocator
	}
}

check_tracking_allocator :: proc(allocator: mem.Tracking_Allocator) -> (ok := true) {
	if len(allocator.allocation_map) > 0 {
		ok = false
		log.errorf("MEMORY LEAK: %v allocations not freed:", len(allocator.allocation_map))
		for _, entry in allocator.allocation_map do log.errorf("- %v bytes at %v", entry.size, entry.location)
	}
	if len(allocator.bad_free_array) > 0 {
		ok = false
		log.errorf("BAD FREES: %v incorrect frees:", len(allocator.bad_free_array))
		for entry in allocator.bad_free_array do log.errorf("- %p at %v", entry.memory, entry.location)
	}

	return
}

main :: proc() {
	context.logger = log.create_console_logger(.Debug when ODIN_DEBUG else .Info)
	defer log.destroy_console_logger(context.logger)

	when TRACK_MEMORY {
		log.infof("Memory tracking enabled.")
		mem.tracking_allocator_init(&s_tracking_allocator, runtime.heap_allocator())
		context.allocator = mem.tracking_allocator(&s_tracking_allocator)
		defer {
			check_tracking_allocator(s_tracking_allocator)
			mem.tracking_allocator_destroy(&s_tracking_allocator)
		}
	} else {
		context.allocator = runtime.heap_allocator()
	}

	g_context = context

	when HOT_RELOAD {
		dmon.init()
		defer dmon.deinit()
		dmon.watch(TEXTURES_PATH, watcher_callback, nil, nil)
		dmon.watch(SHADERS_PATH, watcher_callback, nil, nil)
	}

	starting_scene := Scene_Id.Main_Menu

	for arg in os.args[1:] {
		switch arg {
		case "-overworld":  starting_scene = .Overworld
		case:               log.warnf("Unrecognized command-line argument: %v.", arg)
		}
	}

	if !window_init() do log.panic("Failed to create a window.")
	defer window_deinit()

	if !gl_init() do log.panic("Failed to initialize OpenGL context.")
	defer gl_deinit()

	if !init_imgui() do log.panic("Failed to initialize Dear ImGui.")
	defer deinit_imgui()

	if !init_resources() do log.panic("Failed to initialize the resources.")
	defer deinit_resources()

	if !renderer_init() do log.panic("Failed to initialize the renderer.")
	defer renderer_deinit()

	if !renderer_2d_init() do log.panic("Failed to initialize the 2D renderer.")
	defer renderer_2d_deinit()

	if !init_sound() do log.panic("Failed to initialize the sound system.")
	defer deinit_sound()

	if !change_scene(starting_scene) do log.panic("Failed to initialize the starting scene.")
	defer scene_deinit()

	if !debug_overlay_init() do log.panic("Failed to initialize the debug overlay.")
	defer debug_overlay_deinit()

	MAX_DELTA_TIME :: 1.0 / 30.0
	prev_time := f32(window_time())

	for !window_should_close() {
		when HOT_RELOAD { hot_reload() }

		time := f32(window_time())
		delta_time := min(time - prev_time, MAX_DELTA_TIME)
		prev_time = time

		window_poll_events()
		for event in window_pop_event() {
			renderer_on_event(event)
			scene_on_event(event)
			debug_overlay_on_event(event)
		}

		imgui_new_frame()

		scene_update(delta_time)
		sound_update()
		debug_overlay_update()

		if !window_is_minimized() do scene_render()
		imgui_render()

		window_swap_buffers()
		free_all(context.temp_allocator)
	}
}
