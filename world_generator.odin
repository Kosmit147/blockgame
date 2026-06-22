package blockgame

import "base:runtime"

import "core:math"
import "core:math/noise"
import "core:math/linalg"

World_Generator_Params :: struct {
  seed: i64,
  terrain_smoothness: f64,
  spaghetti_cave_smoothness: f64,
  spaghetti_cave_threshold: f32,
  spaghetti_cave_exponent: f32,
  cheese_cave_smoothness: f64,
  cheese_cave_threshold: f32,
  cheese_cave_exponent: f32,
  min_height: i32,
}

DEFAULT_WORLD_GENERATOR_PARAMS :: World_Generator_Params {
  seed = 0,
  terrain_smoothness = 0.013,
  spaghetti_cave_smoothness = 0.017,
  spaghetti_cave_threshold = 0.133,
  spaghetti_cave_exponent = 1.14,
  cheese_cave_smoothness = 0.03,
  cheese_cave_threshold = 0.87,
  cheese_cave_exponent = 1.00,
  min_height = 1,
}

g_world_generator_params := DEFAULT_WORLD_GENERATOR_PARAMS

Chunk_Layer :: struct {
  block: Block,
  offset: i32,
  span: i32,
}

@(rodata) chunk_layers := []Chunk_Layer {
  {
    block = .Stone,
    offset = -CHUNK_SIZE.y,
    span = CHUNK_SIZE.y,
  },
  {
    block = .Dirt,
    offset = -3,
    span = 2,
  },
  {
    block = .Grass,
    offset = -1,
    span = 1,
  },
}

generator_generate_chunk_blocks :: proc(
  coordinate: Chunk_Coordinate,
  allocator: runtime.Allocator,
) -> (blocks: ^Chunk_Blocks) {
  blocks = new(Chunk_Blocks, allocator)
  for block_x in 0..<CHUNK_SIZE.x {
    for block_z in 0..<CHUNK_SIZE.z {
      world_x := coordinate.x * CHUNK_SIZE.x + block_x
      world_z := coordinate.z * CHUNK_SIZE.z + block_z

      height := max(generator_height({ world_x, world_z }), g_world_generator_params.min_height)

      for layer in chunk_layers {
        layer_start := max(height + layer.offset, 0)
        layer_end := min(layer_start + layer.span, height)
        for block_y in layer_start..<layer_end {
          world_coordinate := [3]i32{ world_x, block_y, world_z }
          cave := generator_cheese_cave(world_coordinate) || generator_spaghetti_cave(world_coordinate)
          if cave && block_y != 0 do continue
          get_chunk_block(blocks, { block_x, block_y, block_z })^ = layer.block
        }
      }
    }
  }
  return
}

generator_height :: proc(coordinate: [2]i32) -> i32 {
  noise_coordinate := cast(noise.Vec2)coordinate * g_world_generator_params.terrain_smoothness
  noise := height_noise(g_world_generator_params.seed, noise_coordinate)
  linear := noise * 0.5 + 0.5
  height := i32(linear * f32(CHUNK_SIZE.y))
  return clamp(height, 0, CHUNK_SIZE.y)
}

generator_cheese_cave :: proc(coordinate: [3]i32) -> bool {
  noise_coordinate := cast(noise.Vec3)coordinate * g_world_generator_params.cheese_cave_smoothness
  exponent := g_world_generator_params.cheese_cave_exponent
  noise := math.pow(cheese_cave_noise(g_world_generator_params.seed, noise_coordinate), exponent)
  threshold := g_world_generator_params.cheese_cave_threshold
  return noise > threshold
}

generator_spaghetti_cave :: proc(coordinate: [3]i32) -> bool {
  noise_coordinate := cast(noise.Vec3)coordinate * g_world_generator_params.spaghetti_cave_smoothness
  exponent := g_world_generator_params.spaghetti_cave_exponent
  noise_1 := math.abs(math.pow(spaghetti_cave_noise(g_world_generator_params.seed, noise_coordinate), exponent))
  noise_2 := math.abs(math.pow(spaghetti_cave_noise(g_world_generator_params.seed + 1, noise_coordinate), exponent))
  noise_3 := math.abs(math.pow(spaghetti_cave_noise(g_world_generator_params.seed + 2, noise_coordinate), exponent))
  threshold := g_world_generator_params.spaghetti_cave_threshold
  return math.abs(noise_1) < threshold && math.abs(noise_2) < threshold && math.abs(noise_3) < threshold
}

height_noise :: proc(seed: i64, coordinate: [2]f64) -> f32 {
  return noise.noise_2d(seed, coordinate)
}

cheese_cave_noise :: proc(seed: i64, coordinate: [3]f64) -> f32 {
  return noise.noise_3d_improve_xz(seed, coordinate)
}

spaghetti_cave_noise :: proc(seed: i64, coordinate: [3]f64) -> f32 {
  return noise.noise_3d_improve_xz(seed, coordinate)
}
