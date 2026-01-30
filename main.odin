package blockgame

import "base:runtime"

import "core:log"
import "core:mem"

import "vendor/dmon"

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

	if !window_init(1920, 1080, "Blockgame") do log.panic("Failed to create a window.")
	defer window_deinit()

	init_gl_context()
	init_imgui()
	defer deinit_imgui()

	if !renderer_init() do log.panic("Failed to initialize the renderer.")
	defer renderer_deinit()

	if !renderer_2d_init() do log.panic("Failed to initialize the 2D renderer.")
	defer renderer_2d_deinit()

	if !game_init() do log.panic("Failed to initialize the game state.")
	defer game_deinit()

	DELTA_TIME_LIMIT :: 1.0 / 30.0
	prev_time := f32(window_time())

	for !window_should_close() {
		time := f32(window_time())
		dt := min(time - prev_time, DELTA_TIME_LIMIT)
		prev_time = time

		window_poll_events()
		for event in window_pop_event() do game_on_event(event)

		imgui_new_frame()

		game_update(dt)
		game_render()

		imgui_render()

		window_swap_buffers()
		free_all(context.temp_allocator)
	}
}
