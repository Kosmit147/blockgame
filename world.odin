package blockgame

import "base:runtime"

import "core:math/noise"
import "core:math/linalg"
import "core:slice"
import "core:thread"
import "core:os"

WORLD_ORIGIN :: Vec3{ 0, 0, 0 }
WORLD_UP :: Vec3{ 0, 1, 0 }

World_Generator_Params :: struct {
	smoothness: f64,
}

default_world_generator_params :: proc "contextless" () -> World_Generator_Params {
	return World_Generator_Params {
		smoothness = 0.01,
	}
}

@(private="file")
s_world_generator_params := default_world_generator_params()

set_world_generator_params :: proc(params: World_Generator_Params) {
	s_world_generator_params = params
}

// World is not allowed to change address after it is initialized (because of the thread pool).
World :: struct {
	chunk_map: map[Chunk_Coordinate]Chunk,
	thread_pool: thread.Pool,
	allocator: runtime.Allocator,
}

// Chunk generation needs to happen in two steps, because an OpenGL mesh can only be created on the main thread.
// So we need to generate the chunk mesh data first on the thread performing the task, and then create the mesh using
// that data on the main thread.
Generate_Chunk_Task_Data :: struct {
	chunk_coordinate: Chunk_Coordinate,
	blocks: ^Chunk_Blocks,
	mesh_data: Chunk_Mesh_Data, // Needs to be freed after the task is complete.
}

generate_chunk_task :: proc(task: thread.Task) {
	data := cast(^Generate_Chunk_Task_Data)task.data
	data.blocks = generate_chunk_blocks(data.chunk_coordinate, task.allocator)
	data.mesh_data = generate_chunk_mesh(data.blocks, task.allocator)
}

world_init :: proc(world: ^World, world_size: i32) -> bool {
	// We want to use a thread-safe heap allocator because the lifetimes of chunks are arbitrary and they are
	// handled from multiple threads.
	world.allocator = runtime.heap_allocator()
	world_side_length := world_size * 2 + 1
	total_chunk_count := world_side_length * world_side_length
	world.chunk_map = make(map[Chunk_Coordinate]Chunk, total_chunk_count, world.allocator)

	MIN_CHUNK_GENERATION_THREADS :: 4
	thread.pool_init(&world.thread_pool,
			 world.allocator,
			 max(os.processor_core_count() - 1, MIN_CHUNK_GENERATION_THREADS))
	thread.pool_start(&world.thread_pool)

	for x in -world_size..=world_size {
		for z in -world_size..=world_size {
			task_data := new(Generate_Chunk_Task_Data, world.allocator)
			task_data.chunk_coordinate = { x, z }
			thread.pool_add_task(&world.thread_pool,
					     world.allocator,
					     generate_chunk_task,
					     task_data)
		}
	}

	return true
}

world_deinit :: proc(world: ^World) {
	for task in thread.pool_pop_waiting(&world.thread_pool) {
		data := cast(^Generate_Chunk_Task_Data)task.data
		free(data, world.allocator)
	}
	thread.pool_finish(&world.thread_pool)
	for task in thread.pool_pop_done(&world.thread_pool) {
		data := cast(^Generate_Chunk_Task_Data)task.data
		free(data.blocks, world.allocator)
		delete_chunk_mesh_data(data.mesh_data)
		free(data, world.allocator)
	}
	thread.pool_destroy(&world.thread_pool)
	for _, &chunk in world.chunk_map do destroy_chunk(&chunk, world.allocator)
	delete(world.chunk_map)
}

world_update :: proc(world: ^World) {
	MAX_CHUNKS_ADDED_PER_UPDATE :: 1
	for _ in 0..<MAX_CHUNKS_ADDED_PER_UPDATE {
		task := thread.pool_pop_done(&world.thread_pool) or_break
		data := cast(^Generate_Chunk_Task_Data)task.data
		world.chunk_map[data.chunk_coordinate] = create_chunk(data.chunk_coordinate,
								      data.blocks,
								      data.mesh_data)
		delete_chunk_mesh_data(data.mesh_data)
		free(data, world.allocator)
	}
}

world_regenerate :: proc(world: ^World, world_size: i32) {
	world_deinit(world)
	world_init(world, world_size)
}

world_get_light_direction :: proc() -> Vec3 {
	return linalg.normalize(Vec3{ -1, 0, 0 })
}

Block :: enum u8 {
	Air = 0,
	Stone,
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

// This function can be called from the main thread only because it makes OpenGL calls.
create_chunk :: proc(coordinate: Chunk_Coordinate, blocks: ^Chunk_Blocks, mesh_data: Chunk_Mesh_Data) -> (chunk: Chunk) {
	return Chunk{ blocks, coordinate, create_chunk_mesh(mesh_data) }
}

destroy_chunk :: proc(chunk: ^Chunk, allocator: runtime.Allocator) {
	destroy_mesh(&chunk.mesh)
	free(chunk.blocks, allocator)
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

get_chunk_block :: proc(blocks: ^Chunk_Blocks, coordinate: Block_Chunk_Coordinate) -> ^Block {
	return &blocks[coordinate.y][coordinate.x][coordinate.z]
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
	blocks: ^Chunk_Blocks,
	position: Block_Chunk_Coordinate,
	finished: bool,
}

make_chunk_iterator :: proc(blocks: ^Chunk_Blocks) -> (iterator: Chunk_Iterator) {
	iterator.blocks = blocks
	return
}

iterate_chunk :: proc(iterator: ^Chunk_Iterator) -> (^Block, Block_Chunk_Coordinate, bool) {
	if iterator.finished do return {}, {}, false

	block := get_chunk_block(iterator.blocks, iterator.position)
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

Chunk_Mesh_Data :: struct {
	vertices: [dynamic]Chunk_Mesh_Vertex,
	indices: [dynamic]Chunk_Mesh_Index,
}

delete_chunk_mesh_data :: proc(mesh_data: Chunk_Mesh_Data) {
	delete(mesh_data.vertices)
	delete(mesh_data.indices)
}

// This function can be called from the main thread only because it makes OpenGL calls.
create_chunk_mesh :: proc(mesh_data: Chunk_Mesh_Data) -> (mesh: Mesh) {
	create_mesh(&mesh,
		    vertices = slice.to_bytes(mesh_data.vertices[:]),
		    vertex_stride = size_of(Chunk_Mesh_Vertex),
		    vertex_format = gl_vertex(Chunk_Mesh_Vertex),
		    indices = slice.to_bytes(mesh_data.indices[:]),
		    index_type = gl_index(Chunk_Mesh_Index))
	return
}

generate_chunk_mesh :: proc(blocks: ^Chunk_Blocks, allocator: runtime.Allocator) -> (mesh: Chunk_Mesh_Data) {
	// TODO: Don't generate vertices for faces which are not visible.

	mesh.vertices = make([dynamic]Standard_Vertex, allocator)
	mesh.indices = make([dynamic]u32, allocator)

	chunk_iterator := make_chunk_iterator(blocks)
	index_offset := u32(0)
	for block, block_coordinate in iterate_chunk(&chunk_iterator) {
		if block^ == .Air do continue
		for vertex in block_vertices {
			vertex := vertex
			vertex.position += Vec3{ f32(block_coordinate.x), f32(block_coordinate.y), f32(block_coordinate.z) }
			append(&mesh.vertices, vertex)
		}
		for index in block_indices {
			append(&mesh.indices, index_offset + index)
		}
		index_offset += len(block_vertices)
	}

	return
}

Chunk_Mesh_Vertex :: Standard_Vertex
Chunk_Mesh_Index :: u32

@(rodata)
block_vertices := [24]Chunk_Mesh_Vertex{
	// Front wall.
	{ position = { 0, 0, 1 }, normal = {  0,  0,  1 }, uv = { 0, 0 } },
	{ position = { 1, 0, 1 }, normal = {  0,  0,  1 }, uv = { 1, 0 } },
	{ position = { 1, 1, 1 }, normal = {  0,  0,  1 }, uv = { 1, 1 } },
	{ position = { 0, 1, 1 }, normal = {  0,  0,  1 }, uv = { 0, 1 } },

	// Back wall.
	{ position = { 0, 0, 0 }, normal = {  0,  0, -1 }, uv = { 0, 0 } },
	{ position = { 0, 1, 0 }, normal = {  0,  0, -1 }, uv = { 0, 1 } },
	{ position = { 1, 1, 0 }, normal = {  0,  0, -1 }, uv = { 1, 1 } },
	{ position = { 1, 0, 0 }, normal = {  0,  0, -1 }, uv = { 1, 0 } },

	// Left wall.
	{ position = { 0, 1, 1 }, normal = { -1,  0,  0 }, uv = { 1, 1 } },
	{ position = { 0, 1, 0 }, normal = { -1,  0,  0 }, uv = { 0, 1 } },
	{ position = { 0, 0, 0 }, normal = { -1,  0,  0 }, uv = { 0, 0 } },
	{ position = { 0, 0, 1 }, normal = { -1,  0,  0 }, uv = { 1, 0 } },

	// Right wall.
	{ position = { 1, 1, 1 }, normal = {  1,  0,  0 }, uv = { 0, 1 } },
	{ position = { 1, 0, 1 }, normal = {  1,  0,  0 }, uv = { 0, 0 } },
	{ position = { 1, 0, 0 }, normal = {  1,  0,  0 }, uv = { 1, 0 } },
	{ position = { 1, 1, 0 }, normal = {  1,  0,  0 }, uv = { 1, 1 } },

	// Bottom wall.
	{ position = { 0, 0, 0 }, normal = {  0, -1,  0 }, uv = { 0, 1 } },
	{ position = { 1, 0, 0 }, normal = {  0, -1,  0 }, uv = { 1, 1 } },
	{ position = { 1, 0, 1 }, normal = {  0, -1,  0 }, uv = { 1, 0 } },
	{ position = { 0, 0, 1 }, normal = {  0, -1,  0 }, uv = { 0, 0 } },

	// Top wall.
	{ position = { 0, 1, 0 }, normal = {  0,  1,  0 }, uv = { 0, 1 } },
	{ position = { 0, 1, 1 }, normal = {  0,  1,  0 }, uv = { 0, 0 } },
	{ position = { 1, 1, 1 }, normal = {  0,  1,  0 }, uv = { 1, 0 } },
	{ position = { 1, 1, 0 }, normal = {  0,  1,  0 }, uv = { 1, 1 } },
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
