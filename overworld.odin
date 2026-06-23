package blockgame

import "vendor/imgui"

import "core:fmt"
import "core:math"
import "core:math/linalg"

MOUSE_SENSITIVITY     :: 1
BASE_MOVEMENT_SPEED   :: 10
SPRINT_MOVEMENT_SPEED :: 30
PLAYER_REACH          :: 8

DEFAULT_WORLD_LOAD_DISTANCE :: 12
UI_LOAD_DISTANCE_MIN :: MIN_WORLD_LOAD_DISTANCE
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

  highlighted_block_position: Maybe(Grid_World_Position),
  picked_block: Block,
  destroy_block_on_update: bool,
  place_block_on_update: bool,
  pick_block_on_update: bool,
}

overworld_init :: proc(scene_data: rawptr) -> (ok := false) {
  overworld := cast(^Overworld)scene_data

  overworld.camera = Camera {
    position = INITIAL_CAMERA_POSITION,
    yaw = math.to_radians(cast(f32)INITIAL_CAMERA_YAW_DEG),
    pitch = math.to_radians(cast(f32)INITIAL_CAMERA_PITCH_DEG),
  }
  world_init(&overworld.world, DEFAULT_WORLD_LOAD_DISTANCE)

  overworld.picked_block = .Bricks
  renderer_set_clear_color(Vec4{ expand_values(overworld.world.sky_color), 1 })

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
  case Scroll_Event:
    delta := int(event.scroll.y)
    block := int(overworld.picked_block)
    block = (block + delta) %% len(Block)
    overworld.picked_block = Block(block)
  }
}

overworld_update :: proc(delta_time: f32, scene_data: rawptr) {
  overworld := cast(^Overworld)scene_data
  player_chunk := to_chunk_coordinate(overworld.camera.position)
  world_update(&overworld.world, delta_time, player_chunk)
  cursor_pos_delta := input_cursor_pos_delta()

  if !window_cursor_enabled() {
    overworld.camera.yaw += cursor_pos_delta.x * MOUSE_SENSITIVITY * 0.001
    overworld.camera.pitch += -cursor_pos_delta.y * MOUSE_SENSITIVITY * 0.001
    overworld.camera.pitch = clamp(overworld.camera.pitch, math.to_radians(f32(-89)), math.to_radians(f32(89)))
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
      block_destroyed := world_destroy_block(overworld.world, block_position)
      if block_destroyed {
        sound_play_destroy_sound()
      }
    }
    if overworld.place_block_on_update {
      place_position := block_position + Grid_World_Position(place_offset)
      block_placed := world_place_block(overworld.world, place_position, overworld.picked_block)
      if block_placed {
        sound_play_place_sound()
      }
    }
  } else {
    overworld.highlighted_block_position = nil
  }

  overworld.destroy_block_on_update = false
  overworld.place_block_on_update = false
  overworld.pick_block_on_update = false
  overworld_debug_ui(overworld, player_chunk)
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

    crosshair_position := Vec2{ -CROSSHAIR_SIZE / 2.0, CROSSHAIR_SIZE / 2.0 }
    crosshair_position.x /= aspect_ratio
    crosshair_size := Vec2(CROSSHAIR_SIZE)
    crosshair_size.x /= aspect_ratio
    crosshair_color := CROSSHAIR_COLOR

    renderer_2d_submit_textured_quad(Quad {
      position = crosshair_position,
      size = crosshair_size,
      color = crosshair_color,
    }, .Crosshair)
  }

  sunlight_line := [2]Line_Vertex {
    {
      position = { 0, 110, 0 },
      color = { **MAGENTA.rgb, 0 },
    },
    {
      position = { 0, 100, 0 } + overworld.world.sunlight.direction * 10,
      color = MAGENTA,
    },
  }

  renderer_render_line(&sunlight_line)
}

overworld_debug_ui :: proc(overworld: ^Overworld, player_chunk_coordinate: Chunk_Coordinate) {
  if !g_debug_overlay.enabled do return

  imgui.Begin("Overworld")
  if imgui.BeginTabBar("World Tab Bar") {
    if imgui.BeginTabItem("Generator") {
      imgui_input_u32("Load Distance", &overworld.world.load_distance)
      overworld.world.load_distance = clamp(overworld.world.load_distance, UI_LOAD_DISTANCE_MIN, UI_LOAD_DISTANCE_MAX)
      imgui_input_i64("Seed", &g_world_generator_params.seed)
      imgui_drag_double(
        "Terrain Smoothness",
        &g_world_generator_params.terrain_smoothness,
        v_speed = 0.001,
        v_min = 0.000001,
        v_max = 1,
      )
      imgui_drag_double(
        "Spaghetti Cave Smoothness",
        &g_world_generator_params.spaghetti_cave_smoothness,
        v_speed = 0.001,
        v_min = 0.000001,
        v_max = 1,
      )
      imgui.DragFloat(
        "Spaghetti Cave Threshold (Low)",
        &g_world_generator_params.spaghetti_cave_threshold_low,
        v_speed = 0.001,
        v_min = 0,
        v_max = 1,
      )
      imgui.DragFloat(
        "Spaghetti Cave Threshold (High)",
        &g_world_generator_params.spaghetti_cave_threshold_high,
        v_speed = 0.001,
        v_min = 0,
        v_max = 1,
      )
      imgui.DragFloat(
        "Spaghetti Cave Exponent",
        &g_world_generator_params.spaghetti_cave_exponent,
        v_speed = 0.01,
        v_min = 0.1,
        v_max = 100,
      )
      imgui_drag_double(
        "Cheese Cave Smoothness",
        &g_world_generator_params.cheese_cave_smoothness,
        v_speed = 0.001,
        v_min = 0.000001,
        v_max = 1,
      )
      imgui.DragFloat(
        "Cheese Cave Threshold (Low)",
        &g_world_generator_params.cheese_cave_threshold_low,
        v_speed = 0.001,
        v_min = -1,
        v_max = 1,
      )
      imgui.DragFloat(
        "Cheese Cave Threshold (High)",
        &g_world_generator_params.cheese_cave_threshold_high,
        v_speed = 0.001,
        v_min = -1,
        v_max = 1,
      )
      imgui.DragFloat(
        "Cheese Cave Exponent",
        &g_world_generator_params.cheese_cave_exponent,
        v_speed = 0.01,
        v_min = 0.1,
        v_max = 100,
      )
      imgui_drag_double(
        "Biome Smoothness",
        &g_world_generator_params.biome_smoothness,
        v_speed = 0.001,
        v_min = 0.000001,
        v_max = 1,
      )
      if imgui.InputFloat("Min Height", &g_world_generator_params.min_height) {
        g_world_generator_params.min_height = clamp(g_world_generator_params.min_height, 0, f32(CHUNK_SIZE.y))
      }
      if imgui.InputFloat("Max Height", &g_world_generator_params.max_height) {
        g_world_generator_params.max_height = clamp(g_world_generator_params.max_height, 1, f32(CHUNK_SIZE.y))
      }
      if imgui.InputFloat("Iron Ore Chance", &g_world_generator_params.iron_ore_chance) {
        g_world_generator_params.iron_ore_chance = clamp(g_world_generator_params.iron_ore_chance, 0, 1)
      }
      if imgui.InputFloat("Snow Tree Chance", &g_world_generator_params.snow_tree_chance) {
        g_world_generator_params.snow_tree_chance = clamp(g_world_generator_params.snow_tree_chance, 0, 1)
      }
      if imgui.InputFloat("Grassland Tree Chance", &g_world_generator_params.grassland_tree_chance) {
        g_world_generator_params.grassland_tree_chance = clamp(g_world_generator_params.grassland_tree_chance, 0, 1)
      }
      if imgui.InputFloat("Desert Cactus Chance", &g_world_generator_params.desert_cactus_chance) {
        g_world_generator_params.desert_cactus_chance = clamp(g_world_generator_params.desert_cactus_chance, 0, 1)
      }
      if imgui.Button("Regenerate") {
        player_chunk := world_position_to_chunk_coordinate(overworld.camera.position)
        world_regenerate(&overworld.world)
      }
      imgui.EndTabItem()
    }
    if imgui.BeginTabItem("Light") {
      if imgui.ColorEdit3("Sky Color", &overworld.world.sky_color) {
        color := Vec4{ expand_values(overworld.world.sky_color), 1 }
        renderer_set_clear_color(gamma_darken(color, DEFAULT_GAMMA))
      }
      imgui.SeparatorText("Directional Light")
      imgui.ColorEdit3("Ambient", &overworld.world.sunlight.ambient)
      imgui.ColorEdit3("Color", &overworld.world.sunlight.color)
      if imgui.DragFloat3(
        "Direction",
        &overworld.world.sunlight.direction,
        v_speed = 0.001,
        v_min = -1,
        v_max = 1
      ) {
        overworld.world.sunlight.direction = linalg.normalize(overworld.world.sunlight.direction)
      }
      imgui.EndTabItem()
    }
    if imgui.BeginTabItem("Time") {
      imgui.DragFloat("Timescale", &overworld.world.timescale)
      imgui.DragFloat("Time", &overworld.world.sunlight_angle, v_speed = 0.001)
      imgui.EndTabItem()
    }
    if imgui.BeginTabItem("Chunks") {
      player_chunk := overworld.world.chunk_map[player_chunk_coordinate]
      if imgui.TreeNode("Player Chunk") {
        imgui.TextUnformatted(fmt.ctprintf("%#v", player_chunk))
        imgui.TreePop()
      }
      imgui.SeparatorText("All Chunks")
      for chunk_coordinate, chunk in overworld.world.chunk_map {
        if imgui.TreeNode(fmt.ctprintf("%v", chunk_coordinate)) {
          imgui.TextUnformatted(fmt.ctprintf("%#v", chunk))
          imgui.TreePop()
        }
      }
      imgui.EndTabItem()
    }
    imgui.EndTabBar()
  }
  imgui.End()

  imgui.Begin("Player")
  imgui.TextUnformatted(fmt.ctprintf("Position: %v", overworld.camera.position))
  imgui.TextUnformatted(fmt.ctprintf("Player chunk: %v", world_position_to_chunk_coordinate(overworld.camera.position)))
  imgui_enum_select("Picked block", &overworld.picked_block)
  imgui.End()
}
