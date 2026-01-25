package blockgame

import "core:math/noise"

WORLD_ORIGIN :: Vec3{ 0, 0, 0 }
WORLD_UP :: Vec3{ 0, 1, 0 }

Block :: enum u8 {
	Air = 0,
	Cobble,
}

Chunk :: struct {
	blocks: ^Chunk_Blocks,
}

CHUNK_SIZE :: [3]i32{ 16, 64, 16 }
CHUNK_GENERATOR_SEED :: 0

Block_Coordinate :: [3]i32

Chunk_Coordinate :: struct {
	x: i32,
	z: i32,
}

Chunk_Blocks :: [CHUNK_SIZE.y][CHUNK_SIZE.x][CHUNK_SIZE.z]Block

get_chunk_block :: proc(chunk: Chunk, coordinate: Block_Coordinate) -> ^Block {
	return &chunk.blocks[coordinate.y][coordinate.x][coordinate.z]
}

create_chunk :: proc(chunk_coordinate: Chunk_Coordinate) -> Chunk {
	blocks := new(Chunk_Blocks)
	chunk := Chunk{ blocks }

	for block_x in i32(0)..<CHUNK_SIZE.x {
		for block_z in i32(0)..<CHUNK_SIZE.z {
			height := get_world_block_height({ chunk_coordinate.x * CHUNK_SIZE.x + block_x,
							   chunk_coordinate.z * CHUNK_SIZE.z + block_z })
			for block_y in 0..<height do get_chunk_block(chunk, { block_x, block_y, block_z })^ = .Cobble
		}
	}

	return chunk
}

destroy_chunk :: proc(chunk: Chunk) {
	free(chunk.blocks)
}

Chunk_Iterator :: struct {
	position: Block_Coordinate,
	finished: bool,
}

iterate_chunk_blocks :: proc(chunk: Chunk, iterator: ^Chunk_Iterator) -> (^Block, Block_Coordinate, bool) {
	if iterator.finished do return {}, {}, false

	block := get_chunk_block(chunk, iterator.position)
	block_coordinate := iterator.position

	iterator.position.z += 1
	if iterator.position.z >= CHUNK_SIZE.z {
		iterator.position.z = 0
		iterator.position.x += 1
		if iterator.position.x >= CHUNK_SIZE.x {
			iterator.position.x = 0
			iterator.position.y += 1
			if iterator.position.y >= CHUNK_SIZE.y {
				iterator.position.y = 0
				iterator.finished = true
			}
		}
	}

	return block, block_coordinate, true
}

@(private="file")
get_world_block_height :: proc(coordinate: [2]i32) -> i32 {
	noise_coordinate := noise.Vec2{ f64(coordinate.x), f64(coordinate.y) }
	noise := noise.noise_2d(CHUNK_GENERATOR_SEED, noise_coordinate)
	linear := noise * 0.5 + 0.5
	height := i32(linear * f32(CHUNK_SIZE.y))
	return clamp(height, 0, CHUNK_SIZE.y)
}
