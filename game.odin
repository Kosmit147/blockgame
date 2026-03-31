package blockgame

import "vendor/imgui"

import "core:fmt"
import "core:math"
import "core:math/linalg"

MOUSE_SENSITIVITY     :: 1
BASE_MOVEMENT_SPEED   :: 5
SPRINT_MOVEMENT_SPEED :: 15
PLAYER_REACH          :: 8

// Currently, setting the world size to a big value makes the game unplayable, so limit it to 20 for now.
DEFAULT_WORLD_SIZE :: 6
UI_WORLD_SIZE_MIN  :: 1
UI_WORLD_SIZE_MAX  :: 20

DEFAULT_SKY_COLOR :: Vec3{ 0.7, 0.95, 1 }
DEFAULT_DIRECTIONAL_LIGHT :: Directional_Light {
	ambient = Vec3{ 0.5, 0.5, 0.5 },
	color = Vec3{ 0.8, 0.8, 0.8 },
	direction = Vec3{ -0.5774, -0.5774, -0.5774 },
}

CROSSHAIR_SIZE  :: 0.03
CROSSHAIR_COLOR :: BLACK

QUIT_GAME_KEY     :: Key.Escape
SPRINT_KEY        :: Key.Left_Shift
DEBUG_UI_KEY      :: Key.F_1
TOGGLE_CURSOR_KEY :: Key.Left_Control

DESTROY_BLOCK_BUTTON :: Mouse_Button.Left
PLACE_BLOCK_BUTTON   :: Mouse_Button.Right
PLACEABLE_BLOCK      :: Block.Bricks

Game :: struct {
	camera: Camera,
	world: World,
	world_size: i32,
	world_generator_params: World_Generator_Params,

	highlighted_block_coordinate: Maybe(Block_World_Coordinate),
	destroy_block_on_update: bool,
	place_block_on_update: bool,

	sky_color: Vec3,
	directional_light: Directional_Light,

	debug_ui_enabled: bool,
}

@(private="file")
s_game: Game

game_init :: proc() -> bool {
	s_game.camera = Camera {
		position = { 0, f32(CHUNK_SIZE.y) - 20, 0 },
		yaw = math.to_radians(f32(-90)),
		pitch = math.to_radians(f32(0)),
	}
	s_game.world_size = DEFAULT_WORLD_SIZE
	s_game.world_generator_params = default_world_generator_params()
	set_world_generator_params(s_game.world_generator_params)
	world_init(&s_game.world, s_game.world_size)

	s_game.sky_color = DEFAULT_SKY_COLOR
	renderer_set_clear_color(Vec4{ s_game.sky_color.r, s_game.sky_color.g, s_game.sky_color.b, 1 })
	s_game.directional_light = DEFAULT_DIRECTIONAL_LIGHT
	s_game.directional_light.direction = linalg.normalize(s_game.directional_light.direction)

	s_game.debug_ui_enabled = true

	return true
}

game_deinit :: proc() {
	world_deinit(&s_game.world)
}

game_on_event :: proc(event: Event) {
	#partial switch event in event {
	case Key_Pressed_Event:
		#partial switch event.key {
		case QUIT_GAME_KEY:      window_close()
		case TOGGLE_CURSOR_KEY:  window_toggle_cursor()
		case DEBUG_UI_KEY:       game_toggle_debug_ui()
		}
	case Mouse_Button_Pressed_Event:
		if event.button == DESTROY_BLOCK_BUTTON do s_game.destroy_block_on_update = true
		if event.button == PLACE_BLOCK_BUTTON do s_game.place_block_on_update = true
	}
}

game_update :: proc(dt: f32) {
	world_update(&s_game.world)
	cursor_pos_delta := input_cursor_pos_delta()

	if !window_cursor_enabled() {
		s_game.camera.yaw += cursor_pos_delta.x * MOUSE_SENSITIVITY * 0.001
		s_game.camera.pitch += -cursor_pos_delta.y * MOUSE_SENSITIVITY * 0.001
		s_game.camera.pitch = clamp(s_game.camera.pitch, math.to_radians(f32(-89)), math.to_radians(f32(89)))
	}

	camera_vectors := camera_vectors(s_game.camera)
	movement_speed := f32(SPRINT_MOVEMENT_SPEED) if input_key_pressed(SPRINT_KEY) else BASE_MOVEMENT_SPEED

	if input_key_pressed(.W) do s_game.camera.position += camera_vectors.forward * movement_speed * dt
	if input_key_pressed(.S) do s_game.camera.position -= camera_vectors.forward * movement_speed * dt
	if input_key_pressed(.A) do s_game.camera.position -= camera_vectors.right   * movement_speed * dt
	if input_key_pressed(.D) do s_game.camera.position += camera_vectors.right   * movement_speed * dt

	ray := Ray { origin = s_game.camera.position, direction = camera_vectors.forward }
	_, block_coordinate, place_offset, block_hit := world_raycast(s_game.world, ray, PLAYER_REACH)
	if block_hit {
		s_game.highlighted_block_coordinate = block_coordinate
		if s_game.destroy_block_on_update {
			world_destroy_block(s_game.world, block_coordinate)
		}
		if s_game.place_block_on_update {
			place_coordinate := block_coordinate + Block_World_Coordinate(place_offset)
			world_place_block(s_game.world, place_coordinate, PLACEABLE_BLOCK)
		}
	} else {
		s_game.highlighted_block_coordinate = nil
	}

	s_game.destroy_block_on_update = false
	s_game.place_block_on_update = false
	game_debug_ui()
}

game_render :: proc() {
	renderer_clear()
	renderer_begin_frame(s_game.camera, s_game.directional_light)
	renderer_render_world(s_game.world)

	highlighted_block_coordinate, do_highlight := s_game.highlighted_block_coordinate.?
	if do_highlight do renderer_render_block_highlight(highlighted_block_coordinate)

	{
		io := imgui.GetIO()
		renderer_2d_submit_text(fmt.tprintf("FPS: %v", io.Framerate), { 5, 5 }, scale = 2)
	}

	{
		aspect_ratio := window_aspect_ratio()

		crosshair_position := Vec2{ 0.0 - CROSSHAIR_SIZE / 2.0, 0.0 + CROSSHAIR_SIZE / 2.0 }
		crosshair_position.x /= aspect_ratio
		crosshair_size := Vec2{ CROSSHAIR_SIZE, CROSSHAIR_SIZE }
		crosshair_size.x /= aspect_ratio
		crosshair_color := CROSSHAIR_COLOR

		renderer_2d_submit_textured_quad(Quad {
			position = crosshair_position,
			size = crosshair_size,
			color = crosshair_color,
		}, .Crosshair)
	}

	renderer_2d_render()
}

@(private="file")
game_debug_ui :: proc() {
	if !s_game.debug_ui_enabled do return

	imgui.Begin("World")
	if imgui.BeginTabBar("World Tab Bar") {
		if imgui.BeginTabItem("Generator") {
			imgui.InputInt("World Size", &s_game.world_size)
			s_game.world_size = clamp(s_game.world_size, UI_WORLD_SIZE_MIN, UI_WORLD_SIZE_MAX)
			if imgui_drag_double("Smoothness",
					     &s_game.world_generator_params.smoothness,
					     v_speed = 0.001,
					     v_min = 0.000001,
					     v_max = 1) {
				set_world_generator_params(s_game.world_generator_params)
			}
			if imgui.Button("Regenerate") do world_regenerate(&s_game.world, s_game.world_size)
			imgui.EndTabItem()
		}
		if imgui.BeginTabItem("Light") {
			if imgui.ColorEdit3("Sky Color", &s_game.sky_color) {
				renderer_set_clear_color(Vec4{ s_game.sky_color.r, s_game.sky_color.g, s_game.sky_color.b, 1 })
			}
			imgui.SeparatorText("Directional Light")
			imgui.ColorEdit3("Ambient", &s_game.directional_light.ambient)
			imgui.ColorEdit3("Color", &s_game.directional_light.color)
			if imgui.DragFloat3("Direction",
					    &s_game.directional_light.direction,
					    v_speed = 0.001,
					    v_min = -1,
					    v_max = 1) {
				s_game.directional_light.direction = linalg.normalize(s_game.directional_light.direction)
			}
			imgui.EndTabItem()
		}
		imgui.EndTabBar()
	}
	imgui.End()

	imgui.Begin("Settings")
	full_screen := window_is_full_screen()
	if imgui.Checkbox("Fullscreen", &full_screen) do window_set_full_screen(full_screen)
	vsync_mode := window_vsync_mode()
	if imgui_enum_select("Vertical Sync", &vsync_mode) do window_set_vsync_mode(vsync_mode)
	master_volume := sound_master_volume()
	if imgui.SliderFloat("Master Volume", &master_volume, 0, 1) do sound_set_master_volume(master_volume)
	music_volume := sound_music_volume()
	if imgui.SliderFloat("Music Volume", &music_volume, 0, 1) do sound_set_music_volume(music_volume)
	imgui.TextUnformatted(fmt.ctprintf("Window size: %v", window_size()))
	imgui.TextUnformatted(fmt.ctprintf("Framebuffer size: %v", window_framebuffer_size()))
	imgui.End()

	imgui.Begin("Player")
	imgui.TextUnformatted(fmt.ctprintf("Position: %v", s_game.camera.position))
	imgui.End()

	imgui.Begin("Music Player")
	track_index := sound_current_track_index()
	if imgui_slice_list_select(&track_index, sound_tracks()) do sound_play_track(track_index)
	imgui.End()
}

game_toggle_debug_ui :: proc() {
	s_game.debug_ui_enabled = !s_game.debug_ui_enabled
}
