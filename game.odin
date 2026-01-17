package blockgame

import "core:math"
import "core:log"

MOUSE_SENSITIVITY :: 1
CUBE_MOVE_SPEED :: 1

Game :: struct {
	camera: Camera,
	cube_position: Vec3,
}

@(private="file")
s_game: Game

game_init :: proc() -> bool {
	s_game.camera = Camera {
		position = { 0, 0, 2 },
		yaw = math.to_radians(f32(-90)),
		pitch = math.to_radians(f32(0)),
	}

	return true
}

game_deinit :: proc() {}

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
	cursor_pos_delta := input_cursor_pos_delta()
	s_game.camera.yaw += cursor_pos_delta.x * MOUSE_SENSITIVITY * dt
	s_game.camera.pitch += -cursor_pos_delta.y * MOUSE_SENSITIVITY * dt

	camera_vectors := camera_vectors(s_game.camera)

	if input_key_pressed(.W) do s_game.camera.position += camera_vectors.forward * dt
	if input_key_pressed(.S) do s_game.camera.position -= camera_vectors.forward * dt
	if input_key_pressed(.A) do s_game.camera.position -= camera_vectors.right   * dt
	if input_key_pressed(.D) do s_game.camera.position += camera_vectors.right   * dt

	if input_key_pressed(.Up)    do s_game.cube_position.y += CUBE_MOVE_SPEED * dt
	if input_key_pressed(.Down)  do s_game.cube_position.y -= CUBE_MOVE_SPEED * dt
	if input_key_pressed(.Left)  do s_game.cube_position.x -= CUBE_MOVE_SPEED * dt
	if input_key_pressed(.Right) do s_game.cube_position.x += CUBE_MOVE_SPEED * dt
}

game_render :: proc() {
	renderer_render(s_game.camera, s_game.cube_position)
}
