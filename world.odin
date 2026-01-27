package blockgame

import "core:math/noise"
import "core:slice"

WORLD_ORIGIN :: Vec3{ 0, 0, 0 }
WORLD_UP :: Vec3{ 0, 1, 0 }

World :: struct {
	chunks: [dynamic]Chunk,
}

world_init :: proc(world: ^World, world_size := i32(3)) -> bool {
	world.chunks = make([dynamic]Chunk, 0, world_size * world_size)
	for x in 0..<world_size {
		for z in 0..<world_size {
			append(&world.chunks, create_chunk({ x, z }))
		}
	}
	assert(len(world.chunks) == int(world_size * world_size))
	return true
}

world_deinit :: proc(world: World) {
	for &chunk in world.chunks do destroy_chunk(&chunk)
	delete(world.chunks)
}

Block :: enum u8 {
	Air = 0,
	Cobble,
}

// Position of the block relative to the chunk that it is a part of.
Block_Chunk_Coordinate :: distinct [3]i32
// Position of the block relative to the world origin.
Block_World_Coordinate :: distinct [3]i32

Chunk :: struct {
	blocks: ^Chunk_Blocks,
	coordinate: Chunk_Coordinate,
	mesh: Mesh,
}

CHUNK_SIZE :: [3]i32{ 16, 64, 16 }
CHUNK_GENERATOR_SEED :: 0

Chunk_Blocks :: [CHUNK_SIZE.y][CHUNK_SIZE.x][CHUNK_SIZE.z]Block

Chunk_Coordinate :: struct {
	x: i32,
	z: i32,
}

create_chunk :: proc(coordinate: Chunk_Coordinate) -> (chunk: Chunk) {
	chunk.blocks = new(Chunk_Blocks)
	chunk.coordinate = coordinate

	for block_x in i32(0)..<CHUNK_SIZE.x {
		for block_z in i32(0)..<CHUNK_SIZE.z {
			height := get_height_at_world_coordinate({ coordinate.x * CHUNK_SIZE.x + block_x,
								   coordinate.z * CHUNK_SIZE.z + block_z })
			for block_y in 0..<height do get_chunk_block(chunk, { block_x, block_y, block_z })^ = .Cobble
		}
	}

	update_chunk_mesh(&chunk)
	return chunk
}

destroy_chunk :: proc(chunk: ^Chunk) {
	destroy_mesh(&chunk.mesh)
	free(chunk.blocks)
}

get_chunk_block :: proc(chunk: Chunk, coordinate: Block_Chunk_Coordinate) -> ^Block {
	return &chunk.blocks[coordinate.y][coordinate.x][coordinate.z]
}

to_chunk_coordinate :: proc(block_coordinate: Block_World_Coordinate) -> Block_Chunk_Coordinate {
	return { block_coordinate.x %% CHUNK_SIZE.x,
		 block_coordinate.y,
		 block_coordinate.z %% CHUNK_SIZE.z }
}

to_world_coordinate :: proc(block_coordinate: Block_Chunk_Coordinate,
			    chunk_coordinate: Chunk_Coordinate) -> Block_World_Coordinate {
	return { chunk_coordinate.x * CHUNK_SIZE.x + block_coordinate.x,
		 block_coordinate.y,
		 chunk_coordinate.z * CHUNK_SIZE.z + block_coordinate.z }
}

Chunk_Iterator :: struct {
	chunk: ^Chunk,
	position: Block_Chunk_Coordinate,
	finished: bool,
}

make_chunk_iterator :: proc(chunk: ^Chunk) -> (iterator: Chunk_Iterator) {
	iterator.chunk = chunk
	return
}

iterate_chunk :: proc(iterator: ^Chunk_Iterator) -> (^Block, Block_Chunk_Coordinate, bool) {
	if iterator.finished do return {}, {}, false

	block := get_chunk_block(iterator.chunk^, iterator.position)
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
get_height_at_world_coordinate :: proc(coordinate: [2]i32) -> i32 {
	noise_coordinate := noise.Vec2{ f64(coordinate.x), f64(coordinate.y) }
	noise := noise.noise_2d(CHUNK_GENERATOR_SEED, noise_coordinate)
	linear := noise * 0.5 + 0.5
	height := i32(linear * f32(CHUNK_SIZE.y))
	return clamp(height, 0, CHUNK_SIZE.y)
}

update_chunk_mesh :: proc(chunk: ^Chunk) {
	// TODO: Don't generate faces for blocks which are not visible.

	vertices := make([dynamic]Standard_Vertex, context.temp_allocator)
	defer delete(vertices)
	indices := make([dynamic]u32, context.temp_allocator)
	defer delete(indices)

	chunk_iterator := make_chunk_iterator(chunk)
	index_offset := u32(0)
	for block, block_coordinate in iterate_chunk(&chunk_iterator) {
		if block^ == .Air do continue
		for vertex in block_vertices {
			vertex := vertex
			vertex.position += Vec3{ f32(block_coordinate.x), f32(block_coordinate.y), f32(block_coordinate.z) }
			append(&vertices, vertex)
		}
		for index in block_indices {
			append(&indices, index_offset + index)
		}
		index_offset += len(block_vertices)
	}

	// TODO: Trying to destroy the previous mesh is dubious when we're working with a completely new chunk.
	destroy_mesh(&chunk.mesh)
	create_mesh(mesh = &chunk.mesh,
		    vertices = slice.to_bytes(vertices[:]),
		    vertex_stride = size_of(Chunk_Mesh_Vertex),
		    vertex_format = chunk_mesh_vertex_format[:],
		    indices = slice.to_bytes(indices[:]),
		    index_type = gl_index(Chunk_Mesh_Index))
}

Chunk_Mesh_Vertex :: Standard_Vertex
Chunk_Mesh_Index :: u32

@(rodata)
chunk_mesh_vertex_format := STANDARD_VERTEX_FORMAT

@(rodata)
block_vertices := [24]Chunk_Mesh_Vertex{
	// Front wall.
	{ position = { 0.0, 0.0, 1.0 }, normal = {  0,  0,  1 }, uv = { 0, 0 } },
	{ position = { 1.0, 0.0, 1.0 }, normal = {  0,  0,  1 }, uv = { 1, 0 } },
	{ position = { 1.0, 1.0, 1.0 }, normal = {  0,  0,  1 }, uv = { 1, 1 } },
	{ position = { 0.0, 1.0, 1.0 }, normal = {  0,  0,  1 }, uv = { 0, 1 } },

	// Back wall.
	{ position = { 0.0, 0.0, 0.0 }, normal = {  0,  0, -1 }, uv = { 0, 0 } },
	{ position = { 0.0, 1.0, 0.0 }, normal = {  0,  0, -1 }, uv = { 0, 1 } },
	{ position = { 1.0, 1.0, 0.0 }, normal = {  0,  0, -1 }, uv = { 1, 1 } },
	{ position = { 1.0, 0.0, 0.0 }, normal = {  0,  0, -1 }, uv = { 1, 0 } },

	// Left wall.
	{ position = { 0.0, 1.0, 1.0 }, normal = { -1,  0,  0 }, uv = { 1, 0 } },
	{ position = { 0.0, 1.0, 0.0 }, normal = { -1,  0,  0 }, uv = { 1, 1 } },
	{ position = { 0.0, 0.0, 0.0 }, normal = { -1,  0,  0 }, uv = { 0, 1 } },
	{ position = { 0.0, 0.0, 1.0 }, normal = { -1,  0,  0 }, uv = { 0, 0 } },

	// Right wall.
	{ position = { 1.0, 1.0, 1.0 }, normal = {  1,  0,  0 }, uv = { 1, 0 } },
	{ position = { 1.0, 0.0, 1.0 }, normal = {  1,  0,  0 }, uv = { 0, 0 } },
	{ position = { 1.0, 0.0, 0.0 }, normal = {  1,  0,  0 }, uv = { 0, 1 } },
	{ position = { 1.0, 1.0, 0.0 }, normal = {  1,  0,  0 }, uv = { 1, 1 } },

	// Bottom wall.
	{ position = { 0.0, 0.0, 0.0 }, normal = {  0, -1,  0 }, uv = { 0, 1 } },
	{ position = { 1.0, 0.0, 0.0 }, normal = {  0, -1,  0 }, uv = { 1, 1 } },
	{ position = { 1.0, 0.0, 1.0 }, normal = {  0, -1,  0 }, uv = { 1, 0 } },
	{ position = { 0.0, 0.0, 1.0 }, normal = {  0, -1,  0 }, uv = { 0, 0 } },

	// Top wall.
	{ position = { 0.0, 1.0, 0.0 }, normal = {  0,  1,  0 }, uv = { 0, 1 } },
	{ position = { 0.0, 1.0, 1.0 }, normal = {  0,  1,  0 }, uv = { 0, 0 } },
	{ position = { 1.0, 1.0, 1.0 }, normal = {  0,  1,  0 }, uv = { 1, 0 } },
	{ position = { 1.0, 1.0, 0.0 }, normal = {  0,  1,  0 }, uv = { 1, 1 } },
}

@(rodata)
block_indices := [36]Chunk_Mesh_Index{
	// Front wall.
	0, 1, 2, 0, 2, 3,

	// Back wall.
	4, 5, 6, 4, 6, 7,

	// Left wall.
	8, 9, 10, 8, 10, 11,

	// Right wall.
	12, 13, 14, 12, 14, 15,

	// Bottom wall.
	16, 17, 18, 16, 18, 19,

	// Top wall.
	20, 21, 22, 20, 22, 23,
}
