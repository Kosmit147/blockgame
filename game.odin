package blockgame

import "vendor/imgui"

import "core:fmt"
import "core:math"
import "core:log"

MOUSE_SENSITIVITY :: 0.12
BASE_MOVEMENT_SPEED :: 5
SPRINT_MOVEMENT_SPEED :: 10

Game :: struct {
	camera: Camera,
	world: World,
}

@(private="file")
s_game: Game

game_init :: proc() -> bool {
	s_game.camera = Camera {
		position = { 0, 0, 0 },
		yaw = math.to_radians(f32(-90)),
		pitch = math.to_radians(f32(0)),
	}

	world_init(&s_game.world)
	return true
}

game_deinit :: proc() {
	world_deinit(s_game.world)
}

game_on_event :: proc(event: Event) {
	switch event in event {
	case Key_Pressed_Event:
		log.debugf("%v key pressed.", event.key)
		if event.key == .Escape do window_close()
		else if event.key == .Left_Control do window_toggle_cursor()
	case Mouse_Button_Pressed_Event:
		log.debugf("%v mouse button pressed.", event.button)
	}
}

game_update :: proc(dt: f32) {
	cursor_pos_delta := input_cursor_pos_delta()

	if !window_cursor_enabled() {
		s_game.camera.yaw += cursor_pos_delta.x * MOUSE_SENSITIVITY * dt
		s_game.camera.pitch += -cursor_pos_delta.y * MOUSE_SENSITIVITY * dt
		s_game.camera.pitch = clamp(s_game.camera.pitch, math.to_radians(f32(-89)), math.to_radians(f32(89)))
	}

	camera_vectors := camera_vectors(s_game.camera)
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
	renderer_render_world(s_game.world)

	renderer_2d_submit_quad(Quad {
		position = { -0.9, 0.9 },
		size = { 0.5, 0.5 },
		color = GREEN,
	})

	{
		io := imgui.GetIO()
		renderer_2d_submit_text(fmt.tprintf("FPS: %v", io.Framerate), { 5, 5 }, scale = 2)
	}

	renderer_2d_render()
}
