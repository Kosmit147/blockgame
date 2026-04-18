package blockgame

import "vendor/imgui"

import "core:fmt"
import "core:math"
import "core:math/linalg"

MOUSE_SENSITIVITY     :: 1
BASE_MOVEMENT_SPEED   :: 5
SPRINT_MOVEMENT_SPEED :: 15
PLAYER_REACH          :: 8

DEFAULT_WORLD_LOAD_DISTANCE :: 10
UI_LOAD_DISTANCE_MIN :: MIN_WORLD_LOAD_DISTANCE
// Currently, setting the load distance to a big value makes the game unplayable, so limit it to 20 for now.
UI_LOAD_DISTANCE_MAX :: MAX_WORLD_LOAD_DISTANCE

CROSSHAIR_SIZE  :: 0.03
CROSSHAIR_COLOR :: BLACK

SPRINT_KEY :: Key.Left_Shift

DESTROY_BLOCK_BUTTON :: Mouse_Button.Left
PLACE_BLOCK_BUTTON   :: Mouse_Button.Right
PICK_BLOCK_BUTTON    :: Mouse_Button.Middle

INITIAL_CAMERA_POSITION  :: Vec3{ 0, f32(CHUNK_SIZE.y) - 20, 0 }
INITIAL_CAMERA_YAW_DEG   :: -90
INITIAL_CAMERA_PITCH_DEG :: 0

Overworld :: struct {
	camera: Camera,
	world: World,
	load_distance: u32,
	world_generator_params: World_Generator_Params,

	highlighted_block_position: Maybe(Grid_World_Position),
	picked_block: Block,
	destroy_block_on_update: bool,
	place_block_on_update: bool,
	pick_block_on_update: bool,

	test_line: [2]Line_Vertex, // TODO: Remove once it's not needed.
}

overworld_init :: proc(scene_data: rawptr) -> (ok := false) {
	overworld := cast(^Overworld)scene_data

	overworld.camera = Camera {
		position = INITIAL_CAMERA_POSITION,
		yaw = math.to_radians(cast(f32)INITIAL_CAMERA_YAW_DEG),
		pitch = math.to_radians(cast(f32)INITIAL_CAMERA_PITCH_DEG),
	}
	overworld.load_distance = 6
	overworld.world_generator_params = DEFAULT_WORLD_GENERATOR_PARAMS
	set_world_generator_params(overworld.world_generator_params)
	player_chunk := world_position_to_chunk_coordinate(overworld.camera.position)
	world_init(&overworld.world, player_chunk, overworld.load_distance)

	overworld.picked_block = .Bricks

	sky_color := overworld.world.sky_color
	renderer_set_clear_color(Vec4{ sky_color.r, sky_color.g, sky_color.b, 1 })

	overworld.test_line = {
		Line_Vertex {
			position = { -10,  50,  10 },
			color = MAGENTA,
		},
		Line_Vertex {
			position = {  10,  50, -10 },
			color = MAGENTA,
		}
	}

	ok = true
	return
}

overworld_deinit :: proc(scene_data: rawptr) {
	overworld := cast(^Overworld)scene_data
	world_deinit(&overworld.world)
}

overworld_on_event :: proc(event: Event, scene_data: rawptr) {
	overworld := cast(^Overworld)scene_data

	#partial switch event in event {
	case Mouse_Button_Pressed_Event:
		#partial switch event.button {
		case DESTROY_BLOCK_BUTTON:  overworld.destroy_block_on_update = true
		case PLACE_BLOCK_BUTTON:    overworld.place_block_on_update = true
		case PICK_BLOCK_BUTTON:     overworld.pick_block_on_update = true
		}
	}
}

overworld_update :: proc(delta_time: f32, scene_data: rawptr) {
	overworld := cast(^Overworld)scene_data
	world_update(&overworld.world, delta_time)
	cursor_pos_delta := input_cursor_pos_delta()

	if !window_cursor_enabled() {
		overworld.camera.yaw += cursor_pos_delta.x * MOUSE_SENSITIVITY * 0.001
		overworld.camera.pitch += -cursor_pos_delta.y * MOUSE_SENSITIVITY * 0.001
		overworld.camera.pitch = clamp(overworld.camera.pitch,
					       math.to_radians(f32(-89)),
					       math.to_radians(f32(89)))
	}

	camera_vectors := camera_vectors(overworld.camera)
	movement_speed := f32(SPRINT_MOVEMENT_SPEED) if input_key_pressed(SPRINT_KEY) else BASE_MOVEMENT_SPEED

	if input_key_pressed(.W) do overworld.camera.position += camera_vectors.forward * movement_speed * delta_time
	if input_key_pressed(.S) do overworld.camera.position -= camera_vectors.forward * movement_speed * delta_time
	if input_key_pressed(.A) do overworld.camera.position -= camera_vectors.right   * movement_speed * delta_time
	if input_key_pressed(.D) do overworld.camera.position += camera_vectors.right   * movement_speed * delta_time

	ray := Ray { origin = overworld.camera.position, direction = camera_vectors.forward }
	block, block_position, place_offset, block_hit := world_raycast(overworld.world, ray, PLAYER_REACH)
	if block_hit {
		overworld.highlighted_block_position = block_position
		if overworld.pick_block_on_update {
			overworld.picked_block = block^
		}
		if overworld.destroy_block_on_update {
			world_destroy_block(overworld.world, block_position)
		}
		if overworld.place_block_on_update {
			place_position := block_position + Grid_World_Position(place_offset)
			world_place_block(overworld.world, place_position, overworld.picked_block)
		}
	} else {
		overworld.highlighted_block_position = nil
	}

	overworld.destroy_block_on_update = false
	overworld.place_block_on_update = false
	overworld.pick_block_on_update = false
	overworld_debug_ui(overworld)
}

overworld_render :: proc(scene_data: rawptr) {
	overworld := cast(^Overworld)scene_data

	renderer_begin_3d_frame(overworld.camera, overworld.world.sunlight)
	defer renderer_end_frame()

	renderer_render_world(overworld.world)

	highlighted_block_position, do_highlight := overworld.highlighted_block_position.?
	if do_highlight do renderer_render_block_highlight(highlighted_block_position)

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

	renderer_render_line(&overworld.test_line)
}

@(private="file")
overworld_debug_ui :: proc(overworld: ^Overworld) {
	if !debug_overlay_enabled() do return

	imgui.Begin("Overworld")
	if imgui.BeginTabBar("World Tab Bar") {
		if imgui.BeginTabItem("Generator") {
			imgui_input_u32("Load Distance", &overworld.load_distance)
			overworld.load_distance = clamp(overworld.load_distance,
							UI_LOAD_DISTANCE_MIN,
							UI_LOAD_DISTANCE_MAX)
			if imgui_input_i64("Seed", &overworld.world_generator_params.seed) {
				set_world_generator_params(overworld.world_generator_params)
			}
			if imgui_drag_double("Smoothness",
					     &overworld.world_generator_params.smoothness,
					     v_speed = 0.001,
					     v_min = 0.000001,
					     v_max = 1) {
				set_world_generator_params(overworld.world_generator_params)
			}
			if imgui.Button("Regenerate") {
				player_chunk := world_position_to_chunk_coordinate(overworld.camera.position)
				world_regenerate(&overworld.world, player_chunk, overworld.load_distance)
			}
			imgui.EndTabItem()
		}
		if imgui.BeginTabItem("Light") {
			if imgui.ColorEdit3("Sky Color", &overworld.world.sky_color) {
				color := Vec4{ overworld.world.sky_color.r,
					       overworld.world.sky_color.g,
					       overworld.world.sky_color.b,
					       1 }
				renderer_set_clear_color(gamma_darken(color, DEFAULT_GAMMA))
			}
			imgui.SeparatorText("Directional Light")
			imgui.ColorEdit3("Ambient", &overworld.world.sunlight.ambient)
			imgui.ColorEdit3("Color", &overworld.world.sunlight.color)
			if imgui.DragFloat3("Direction",
					    &overworld.world.sunlight.direction,
					    v_speed = 0.001,
					    v_min = -1,
					    v_max = 1) {
				overworld.world.sunlight.direction =
					linalg.normalize(overworld.world.sunlight.direction)
			}
			imgui.EndTabItem()
		}
		if imgui.BeginTabItem("Time") {
			imgui.DragFloat("Timescale", &overworld.world.timescale)
			imgui.EndTabItem()
		}
		imgui.EndTabBar()
	}
	imgui.End()

	imgui.Begin("Player")
	imgui.TextUnformatted(fmt.ctprintf("Position: %v", overworld.camera.position))
	imgui.TextUnformatted(fmt.ctprintf("Player chunk: %v",
			      world_position_to_chunk_coordinate(overworld.camera.position)))
	imgui_enum_select("Picked block", &overworld.picked_block)
	imgui.End()

	imgui.Begin("Line")
	imgui.SeparatorText("Point A")
	imgui.DragFloat3("Position##A", &overworld.test_line[0].position)
	imgui.ColorEdit4("Color##A", &overworld.test_line[0].color)
	imgui.SeparatorText("Point B")
	imgui.DragFloat3("Position##B", &overworld.test_line[1].position)
	imgui.ColorEdit4("Color##B", &overworld.test_line[1].color)
	imgui.End()
}
