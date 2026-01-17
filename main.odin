package blockgame

import "base:runtime"

import "core:log"
import "core:mem"
import "core:math"

MOUSE_SENSITIVITY :: 1
MODEL_MOVE_SPEED :: 1

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

	if !renderer_init() do log.panic("Failed to initialize the renderer.")
	defer renderer_deinit()

	camera := Camera {
		position = { 0, 0, 2 },
		yaw = math.to_radians(f32(-90)),
		pitch = math.to_radians(f32(0)),
	}

	cube_position: Vec3

	prev_time := window_time()

	for !window_should_close() {
		window_poll_events()

		time := window_time()
		dt := time - prev_time
		prev_time = time

		for event in window_pop_event() {
			switch event in event {
			case Key_Pressed_Event:
				log.debugf("%v key pressed.", event.key)
				if event.key == .Escape do window_close()
			case Mouse_Button_Pressed_Event:
				log.debugf("%v mouse button pressed.", event.button)
			}
		}

		cursor_pos_delta := input_cursor_pos_delta()
		camera.yaw += cursor_pos_delta.x * MOUSE_SENSITIVITY * f32(dt)
		camera.pitch += -cursor_pos_delta.y * MOUSE_SENSITIVITY * f32(dt)

		camera_vectors := camera_vectors(camera)

		if input_key_pressed(.W) do camera.position += camera_vectors.forward * f32(dt)
		if input_key_pressed(.S) do camera.position -= camera_vectors.forward * f32(dt)
		if input_key_pressed(.A) do camera.position -= camera_vectors.right   * f32(dt)
		if input_key_pressed(.D) do camera.position += camera_vectors.right   * f32(dt)

		if input_key_pressed(.Up)    do cube_position.y += MODEL_MOVE_SPEED * f32(dt)
		if input_key_pressed(.Down)  do cube_position.y -= MODEL_MOVE_SPEED * f32(dt)
		if input_key_pressed(.Left)  do cube_position.x -= MODEL_MOVE_SPEED * f32(dt)
		if input_key_pressed(.Right) do cube_position.x += MODEL_MOVE_SPEED * f32(dt)

		renderer_render(camera, cube_position)

		window_swap_buffers()
		free_all(context.temp_allocator)
	}
}
