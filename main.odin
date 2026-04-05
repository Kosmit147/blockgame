package blockgame

import "base:runtime"

import "vendor/dmon"

import "core:log"
import "core:mem"
import "core:strings"

HOT_RELOAD :: #config(HOT_RELOAD, false)

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

main :: proc() {
	context.logger = log.create_console_logger(.Debug when ODIN_DEBUG else .Info)
	defer log.destroy_console_logger(context.logger)

	when ODIN_DEBUG {
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, context.allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)

		defer {
			if len(tracking_allocator.allocation_map) > 0 {
				log.errorf("MEMORY LEAK: %v allocations not freed:",
					   len(tracking_allocator.allocation_map))

				for _, entry in tracking_allocator.allocation_map {
					log.errorf("- %v bytes at %v", entry.size, entry.location)
				}
			}

			mem.tracking_allocator_destroy(&tracking_allocator)
		}
	}

	g_context = context

	when HOT_RELOAD {
		dmon.init()
		defer dmon.deinit()
		dmon.watch(TEXTURES_PATH, watcher_callback, nil, nil)
		dmon.watch(SHADERS_PATH, watcher_callback, nil, nil)
	}

	if !window_init() do log.panic("Failed to create a window.")
	defer window_deinit()

	init_gl_context()
	init_imgui()
	defer deinit_imgui()

	if !init_resources() do log.panic("Failed to initialize the resources.")
	defer deinit_resources()

	if !renderer_init() do log.panic("Failed to initialize the renderer.")
	defer renderer_deinit()

	if !renderer_2d_init() do log.panic("Failed to initialize the 2D renderer.")
	defer renderer_2d_deinit()

	if !init_sound() do log.panic("Failed to initialize the sound system.")
	defer deinit_sound()

	if !change_scene(.Main_Menu) do log.panic("Failed to initialize the starting scene.")
	defer scene_deinit()

	MAX_DELTA_TIME :: 1.0 / 30.0
	prev_time := f32(window_time())

	for !window_should_close() {
		when HOT_RELOAD { hot_reload() }

		time := f32(window_time())
		delta_time := min(time - prev_time, MAX_DELTA_TIME)
		prev_time = time

		window_poll_events()
		for event in window_pop_event() do scene_on_event(event)

		imgui_new_frame()

		scene_update(delta_time)
		sound_update()

		renderer_clear()
		if !window_is_minimized() {
			scene_render()
			renderer_2d_render()
		}
		imgui_render()
		renderer_finish_render()

		window_swap_buffers()
		free_all(context.temp_allocator)
	}
}
