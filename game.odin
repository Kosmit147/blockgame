package blockgame

import "core:math"
import "core:log"

MOUSE_SENSITIVITY :: 0.2
BASE_MOVEMENT_SPEED :: 5
SPRINT_MOVEMENT_SPEED :: 10

Game :: struct {
	camera: Camera,
	chunk: Chunk,
}

@(private="file")
s_game: Game

game_init :: proc() -> bool {
	s_game.camera = Camera {
		position = { 0, 0, 2 },
		yaw = math.to_radians(f32(-90)),
		pitch = math.to_radians(f32(0)),
	}

	s_game.chunk = create_chunk({ 0, 0 })
	return true
}

game_deinit :: proc() {
	destroy_chunk(s_game.chunk)
}

game_on_event :: proc(event: Event) {
	switch event in event {
	case Key_Pressed_Event:
		log.debugf("%v key pressed.", event.key)
		if event.key == .Escape do window_close()
	case Mouse_Button_Pressed_Event:
		log.debugf("%v mouse button pressed.", event.button)
	}
}

game_update :: proc(dt: f32) {
	camera_vectors := camera_vectors(s_game.camera)
	cursor_pos_delta := input_cursor_pos_delta()

	s_game.camera.yaw += cursor_pos_delta.x * MOUSE_SENSITIVITY * dt
	s_game.camera.pitch += -cursor_pos_delta.y * MOUSE_SENSITIVITY * dt

	movement_speed := f32(BASE_MOVEMENT_SPEED)

	if input_key_pressed(.Left_Shift) do movement_speed = SPRINT_MOVEMENT_SPEED

	if input_key_pressed(.W) do s_game.camera.position += camera_vectors.forward * movement_speed * dt
	if input_key_pressed(.S) do s_game.camera.position -= camera_vectors.forward * movement_speed * dt
	if input_key_pressed(.A) do s_game.camera.position -= camera_vectors.right   * movement_speed * dt
	if input_key_pressed(.D) do s_game.camera.position += camera_vectors.right   * movement_speed * dt
}

game_render :: proc() {
	renderer_clear()
	renderer_begin_frame(s_game.camera)

	chunk_iterator: Chunk_Iterator
	for block, block_coordinate in iterate_chunk_blocks(s_game.chunk, &chunk_iterator) {
		renderer_render_block(s_game.camera, block^, block_coordinate)
	}

	renderer_2d_render()
}
