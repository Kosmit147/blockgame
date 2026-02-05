package blockgame

import "base:runtime"

import "core:math/noise"

World_Generator_Params :: struct {
	smoothness: f64,
}

default_world_generator_params :: proc "contextless" () -> World_Generator_Params {
	return World_Generator_Params {
		smoothness = 0.021,
	}
}

@(private="file")
s_world_generator_params := default_world_generator_params()

set_world_generator_params :: proc(params: World_Generator_Params) {
	s_world_generator_params = params
}

generate_chunk_blocks :: proc(coordinate: Chunk_Coordinate, allocator: runtime.Allocator) -> (blocks: ^Chunk_Blocks) {
	blocks = new(Chunk_Blocks, allocator)
	for block_x in i32(0)..<CHUNK_SIZE.x {
		for block_z in i32(0)..<CHUNK_SIZE.z {
			height := get_height_at_world_coordinate({ coordinate.x * CHUNK_SIZE.x + block_x,
								   coordinate.z * CHUNK_SIZE.z + block_z })
			for block_y in 0..<height {
				get_chunk_block(blocks, { block_x, block_y, block_z })^ = .Stone
			}

			if height > 0 do get_chunk_block(blocks, { block_x, height - 1, block_z })^ = .Grass
			if height > 1 do get_chunk_block(blocks, { block_x, height - 2, block_z })^ = .Dirt
		}
	}
	return
}

@(private="file")
get_height_at_world_coordinate :: proc(coordinate: [2]i32) -> i32 {
	noise_coordinate := noise.Vec2{ f64(coordinate.x), f64(coordinate.y) } * s_world_generator_params.smoothness
	noise := noise.noise_2d(CHUNK_GENERATOR_SEED, noise_coordinate)
	linear := noise * 0.5 + 0.5
	height := i32(linear * f32(CHUNK_SIZE.y))
	return clamp(height, 0, CHUNK_SIZE.y)
}
