package blockgame

import "base:runtime"

import "core:math"
import "core:math/noise"
import "core:math/linalg"
import "core:math/rand"

World_Generator_Params :: struct {
  seed: i64,
  terrain_smoothness: f64,
  spaghetti_cave_smoothness: f64,
  spaghetti_cave_threshold_low: f32,
  spaghetti_cave_threshold_high: f32,
  spaghetti_cave_exponent: f32,
  cheese_cave_smoothness: f64,
  cheese_cave_threshold_low: f32,
  cheese_cave_threshold_high: f32,
  cheese_cave_exponent: f32,
  biome_smoothness: f64,
  min_height: f32,
  max_height: f32,
  iron_ore_chance: f32,
  grassland_tree_chance: f32,
  desert_cactus_chance: f32,
}

DEFAULT_WORLD_GENERATOR_PARAMS :: World_Generator_Params {
  seed = 0,
  terrain_smoothness = 0.013,
  spaghetti_cave_smoothness = 0.017,
  spaghetti_cave_threshold_low = 0.033,
  spaghetti_cave_threshold_high = 0.22,
  spaghetti_cave_exponent = 1.14,
  cheese_cave_smoothness = 0.03,
  cheese_cave_threshold_low = 0.683,
  cheese_cave_threshold_high = 0.973,
  cheese_cave_exponent = 1.00,
  biome_smoothness = 0.001,
  min_height = f32(min(40, CHUNK_SIZE.y)),
  max_height = f32(max(CHUNK_SIZE.y - 10, 0)),
  iron_ore_chance = 0.01,
  grassland_tree_chance = 0.01,
  desert_cactus_chance = 0.005,
}

g_world_generator_params := DEFAULT_WORLD_GENERATOR_PARAMS

Biome :: enum {
  Tundra,
  Grassland,
  Desert,
}

Chunk_Layer :: struct {
  block: Block,
  offset: i32,
  span: i32,
}

@(rodata) chunk_layers := [Biome][]Chunk_Layer {
  .Tundra = {
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
      block = .Snow,
      offset = -1,
      span = 1,
    },
  },
  .Grassland = {
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
  },
  .Desert = {
    {
      block = .Stone,
      offset = -CHUNK_SIZE.y,
      span = CHUNK_SIZE.y,
    },
    {
      block = .Sand,
      offset = -3,
      span = 2,
    },
    {
      block = .Sand,
      offset = -1,
      span = 1,
    },
  },
}

Structure_Block :: struct {
  offset: [3]i32,
  block: Block,
}

Structure :: []Structure_Block

@(rodata) tree := Structure {
  { { 0, 0, 0 }, .Log },
  { { 0, 1, 0 }, .Log },
  { { 0, 2, 0 }, .Log },
  { { 0, 3, 0 }, .Log },
  { { 1, 3, 0 }, .Leaves },
  { { -1, 3, 0 }, .Leaves },
  { { 1, 3, 1 }, .Leaves },
  { { -1, 3, -1 }, .Leaves },
  { { 2, 3, 0 }, .Leaves },
  { { -2, 3, 0 }, .Leaves },
  { { 0, 3, 1 }, .Leaves },
  { { 0, 3, -1 }, .Leaves },
  { { -1, 3, 1 }, .Leaves },
  { { 1, 3, -1 }, .Leaves },
  { { 0, 3, 2 }, .Leaves },
  { { 0, 3, -2 }, .Leaves },
  { { 0, 4, 0 }, .Leaves },
  { { 1, 4, 0 }, .Leaves },
  { { -1, 4, 0 }, .Leaves },
  { { 0, 4, 1 }, .Leaves },
  { { 0, 4, -1 }, .Leaves },
  { { 0, 5, 0 }, .Leaves },
}

@(rodata) cactus := Structure {
  { { 0, 0, 0 }, .Cactus },
  { { 0, 1, 0 }, .Cactus },
  { { 0, 2, 0 }, .Cactus },
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

      height := generator_height({ world_x, world_z })
      biome := generator_biome({ world_x, world_z })

      for layer in chunk_layers[biome] {
        layer_start := max(height + layer.offset, 0)
        layer_end := min(layer_start + layer.span, height)
        for block_y in layer_start..<layer_end {
          world_coordinate := [3]i32{ world_x, block_y, world_z }
          cave := generator_cheese_cave(world_coordinate) || generator_spaghetti_cave(world_coordinate)
          if cave && block_y != 0 do continue
          block_to_place := layer.block
          if layer.block == .Stone {
            if rand.float32() < g_world_generator_params.iron_ore_chance {
              block_to_place = .Iron_Ore
            }
          }
          get_chunk_block(blocks, { block_x, block_y, block_z })^ = block_to_place
        }
      }

      #partial switch biome {
      case .Grassland:
        if rand.float32() < g_world_generator_params.grassland_tree_chance {
          try_place_structure(blocks, { block_x, height, block_z }, tree)
        }
      case .Desert:
        if rand.float32() < g_world_generator_params.desert_cactus_chance {
          try_place_structure(blocks, { block_x, height, block_z }, cactus)
        }
      }
    }
  }
  return
}

try_place_structure :: proc(blocks: ^Chunk_Blocks, coordinate: [3]i32, structure: Structure) -> bool {
  for block in structure {
    existing_block := get_chunk_block_safe(blocks, Grid_Chunk_Position(coordinate + block.offset)) or_return
    if existing_block^ != .Air do return false
  }

  for block in structure {
    get_chunk_block(blocks, Grid_Chunk_Position(coordinate + block.offset))^ = block.block
  }

  return true
}

generator_height :: proc(coordinate: [2]i32) -> i32 {
  noise_coordinate := cast(noise.Vec2)coordinate * g_world_generator_params.terrain_smoothness
  noise := height_noise(g_world_generator_params.seed, noise_coordinate)
  linear := noise * 0.5 + 0.5
  height := i32(math.lerp(g_world_generator_params.min_height, g_world_generator_params.max_height, linear))
  return clamp(height, 0, CHUNK_SIZE.y)
}

generator_cheese_cave :: proc(coordinate: [3]i32) -> bool {
  noise_coordinate := cast(noise.Vec3)coordinate * g_world_generator_params.cheese_cave_smoothness
  exponent := g_world_generator_params.cheese_cave_exponent
  noise := math.pow(cheese_cave_noise(g_world_generator_params.seed, noise_coordinate), exponent)
  height_factor := f32(coordinate.y) / f32(CHUNK_SIZE.y)
  threshold := math.lerp(
    g_world_generator_params.cheese_cave_threshold_low,
    g_world_generator_params.cheese_cave_threshold_high,
    height_factor,
  )
  return noise > threshold
}

generator_spaghetti_cave :: proc(coordinate: [3]i32) -> bool {
  noise_coordinate := cast(noise.Vec3)coordinate * g_world_generator_params.spaghetti_cave_smoothness
  exponent := g_world_generator_params.spaghetti_cave_exponent
  noise_1 := math.abs(math.pow(spaghetti_cave_noise(g_world_generator_params.seed, noise_coordinate), exponent))
  noise_2 := math.abs(math.pow(spaghetti_cave_noise(g_world_generator_params.seed + 1, noise_coordinate), exponent))
  noise_3 := math.abs(math.pow(spaghetti_cave_noise(g_world_generator_params.seed + 2, noise_coordinate), exponent))
  height_factor := f32(coordinate.y) / f32(CHUNK_SIZE.y)
  threshold := math.lerp(
    g_world_generator_params.spaghetti_cave_threshold_low,
    g_world_generator_params.spaghetti_cave_threshold_high,
    height_factor,
  )
  return math.abs(noise_1) < threshold && math.abs(noise_2) < threshold && math.abs(noise_3) < threshold
}

generator_biome :: proc(coordinate: [2]i32) -> (biome: Biome) {
  noise_coordinate := cast(noise.Vec2)coordinate * g_world_generator_params.biome_smoothness
  noise := biome_noise(g_world_generator_params.seed, noise_coordinate)
  if noise >= -1 && noise < -0.4 {
    biome = .Tundra
  } else if noise >= -0.4 && noise < 0.4 {
    biome = .Grassland
  } else if noise >= 0.4 && noise <= 1 {
    biome = .Desert
  }

  return
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

biome_noise :: proc(seed: i64, coordinate: [2]f64) -> f32 {
  return noise.noise_2d(seed, coordinate)
}
