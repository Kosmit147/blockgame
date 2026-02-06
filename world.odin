package blockgame

import "base:runtime"

import "core:math/bits"
import "core:math/linalg"
import "core:slice"
import "core:thread"
import "core:os"

WORLD_ORIGIN :: Vec3{  0,  0,  0 }
WORLD_UP     :: Vec3{  0,  1,  0 }
WORLD_DOWN   :: Vec3{  0, -1,  0 }

World_Directions :: bit_set[World_Direction]
World_Direction :: enum {
	Plus_X,
	Minus_X,
	Plus_Y,
	Minus_Y,
	Plus_Z,
	Minus_Z,
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

world_raycast :: proc(world: World, ray: Ray, max_distance: f32) -> (block: ^Block,
								     block_coordinate: Block_World_Coordinate,
								     hit := false) {
	grid_traversal_direction := [3]i32{ 1 if ray.direction.x >= 0 else -1,
					    1 if ray.direction.y >= 0 else -1,
					    1 if ray.direction.z >= 0 else -1 }

	grid_boundary_increment := [3]i32{ 1 if ray.direction.x >= 0 else 0,
					   1 if ray.direction.y >= 0 else 0,
					   1 if ray.direction.z >= 0 else 0 }

	origin_block := linalg.array_cast(linalg.floor(ray.origin), i32)
	current_block := [3]i32{ 0, 0, 0 }
	delta_fractional := linalg.fract(ray.origin)

	for {
		// delta is the distance from the origin to the next grid boundary.
		delta := linalg.array_cast(current_block + grid_boundary_increment, f32) - delta_fractional
		// t is the length that we have to travel along the ray to reach the next grid boundary.
		t := delta / ray.direction
		when ODIN_DEBUG { assert(t.x >= 0 && t.y >= 0 && t.z >= 0) }

		min_t: f32
		if (t.x <= t.y && t.x <= t.z) {
			current_block.x += grid_traversal_direction.x
			min_t = t.x
		} else if (t.y <= t.x && t.y <= t.z) {
			current_block.y += grid_traversal_direction.y
			min_t = t.y
		} else if (t.z <= t.x && t.z <= t.y) {
			current_block.z += grid_traversal_direction.z
			min_t = t.z
		}

		if min_t > max_distance do return

		block_coordinate = Block_World_Coordinate(origin_block + current_block)
		block_ok: bool
		block, block_ok = world_get_block(world, block_coordinate)

		if block_ok && !block_ignores_raycast(block^) {
			hit = true
			return
		}
	}
}

world_get_block :: proc(world: World, coordinate: Block_World_Coordinate) -> (^Block, bool) {
	when ODIN_DEBUG { assert(bits.is_power_of_two(CHUNK_SIZE.x)) }
	when ODIN_DEBUG { assert(bits.is_power_of_two(CHUNK_SIZE.z)) }

	chunk_coordinate := Chunk_Coordinate {
		x = (coordinate.x & ~(CHUNK_SIZE.x - 1)) / CHUNK_SIZE.x,
		z = (coordinate.z & ~(CHUNK_SIZE.z - 1)) / CHUNK_SIZE.z,
	}

	chunk, chunk_ok := world.chunk_map[chunk_coordinate]
	if !chunk_ok do return nil, false

	return get_chunk_block_safe(chunk.blocks, to_chunk_coordinate(coordinate))
}

Block :: enum u8 {
	Air = 0,
	Stone,
	Dirt,
	Grass,
}

// Position of the block relative to the chunk that it is a part of.
Block_Chunk_Coordinate :: distinct [3]i32
// Position of the block relative to the world origin.
Block_World_Coordinate :: distinct [3]i32

@(require_results)
block_is_invisible :: proc(block: Block) -> bool {
	return block == .Air
}

@(require_results)
block_is_fully_opaque :: proc(block: Block) -> bool {
	return block != .Air
}

@(require_results)
block_ignores_raycast :: proc(block: Block) -> bool {
	return block == .Air
}

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

// TODO: Should probably be #no_bounds_check.
get_chunk_block :: proc(blocks: ^Chunk_Blocks, coordinate: Block_Chunk_Coordinate) -> ^Block {
	return &blocks[coordinate.y][coordinate.x][coordinate.z]
}

get_chunk_block_safe :: proc(blocks: ^Chunk_Blocks, coordinate: Block_Chunk_Coordinate) -> (^Block, bool) {
	x_in_bounds := coordinate.x >= 0 && coordinate.x < CHUNK_SIZE.x
	y_in_bounds := coordinate.y >= 0 && coordinate.y < CHUNK_SIZE.y
	z_in_bounds := coordinate.z >= 0 && coordinate.z < CHUNK_SIZE.z
	if !x_in_bounds || !y_in_bounds || !z_in_bounds do return nil, false
	return get_chunk_block(blocks, coordinate), true
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

// TODO: Optimize mesh generation.
generate_chunk_mesh :: proc(blocks: ^Chunk_Blocks, allocator: runtime.Allocator) -> (mesh: Chunk_Mesh_Data) {
	// TODO: Don't generate vertices for faces which are not visible at chunk boundaries.

	mesh.vertices = make([dynamic]Standard_Vertex, allocator)
	mesh.indices = make([dynamic]u32, allocator)

	chunk_iterator := make_chunk_iterator(blocks)
	index_offset := u32(0)
	for block, block_coordinate in iterate_chunk(&chunk_iterator) {
		if block_is_invisible(block^) do continue
		visible_faces_directions := visible_faces(blocks, block_coordinate)
		for face_vertices, facing_direction in block_faces {
			if facing_direction not_in visible_faces_directions do continue
			vertex_position_offset := linalg.array_cast(block_coordinate, f32)
			vertices := face_vertices
			for &vertex in vertices {
				vertex.position += vertex_position_offset
				vertex.uv = map_block_uv_to_atlas(vertex.uv, block^, facing_direction)
			}
			indices := block_indices
			for &index in indices do index += index_offset
			append(&mesh.vertices, ..vertices[:])
			append(&mesh.indices, ..indices[:])
			index_offset += len(vertices)
		}
	}

	return
}

@(private="file")
visible_faces :: proc(blocks: ^Chunk_Blocks, coordinate: Block_Chunk_Coordinate) -> (directions: World_Directions) {
	offsets := [World_Direction][3]i32{
		.Plus_X  = { +1,  0,  0 },
		.Minus_X = { -1,  0,  0 },
		.Plus_Y  = {  0, +1,  0 },
		.Minus_Y = {  0, -1,  0 },
		.Plus_Z  = {  0,  0, +1 },
		.Minus_Z = {  0,  0, -1 },
	}

	for offset, direction in offsets {
		neighbor, neighbor_ok := get_chunk_block_safe(blocks, coordinate + Block_Chunk_Coordinate(offset))
		if !neighbor_ok || (neighbor_ok && !block_is_fully_opaque(neighbor^)) do directions += { direction }
	}
	return
}

@(private="file")
map_block_uv_to_atlas :: proc(uv: Vec2, block: Block, block_facing: World_Direction) -> Vec2 {
	atlas_rect_origin: Vec2
	atlas_rect_size := Vec2{ 0.5, 0.5 }

	switch block {
	case .Air:
	case .Stone: atlas_rect_origin = Vec2{ 0.0, 0.0 }
	case .Dirt:  atlas_rect_origin = Vec2{ 0.5, 0.0 }
	case .Grass:
		#partial switch block_facing {
		case .Plus_Y:      atlas_rect_origin = Vec2{ 0.0, 0.5 }
		case .Minus_Y:     atlas_rect_origin = Vec2{ 0.5, 0.0 }
		case:              atlas_rect_origin = Vec2{ 0.5, 0.5 }
		}
	}

	return atlas_rect_origin + uv * atlas_rect_size
}

Chunk_Mesh_Vertex :: Standard_Vertex
Chunk_Mesh_Index :: u32

@(private="file", rodata)
block_faces := [World_Direction][4]Chunk_Mesh_Vertex{
	// Front wall.
	.Plus_Z = {
		{ position = { 0, 0, 1 }, normal = {  0,  0,  1 }, uv = { 0, 1 } },
		{ position = { 1, 0, 1 }, normal = {  0,  0,  1 }, uv = { 1, 1 } },
		{ position = { 1, 1, 1 }, normal = {  0,  0,  1 }, uv = { 1, 0 } },
		{ position = { 0, 1, 1 }, normal = {  0,  0,  1 }, uv = { 0, 0 } },
	},

	// Back wall.
	.Minus_Z = {
		{ position = { 0, 0, 0 }, normal = {  0,  0, -1 }, uv = { 0, 1 } },
		{ position = { 0, 1, 0 }, normal = {  0,  0, -1 }, uv = { 0, 0 } },
		{ position = { 1, 1, 0 }, normal = {  0,  0, -1 }, uv = { 1, 0 } },
		{ position = { 1, 0, 0 }, normal = {  0,  0, -1 }, uv = { 1, 1 } },
	},

	// Left wall.
	.Minus_X = {
		{ position = { 0, 1, 1 }, normal = { -1,  0,  0 }, uv = { 1, 0 } },
		{ position = { 0, 1, 0 }, normal = { -1,  0,  0 }, uv = { 0, 0 } },
		{ position = { 0, 0, 0 }, normal = { -1,  0,  0 }, uv = { 0, 1 } },
		{ position = { 0, 0, 1 }, normal = { -1,  0,  0 }, uv = { 1, 1 } },
	},

	// Right wall.
	.Plus_X = {
		{ position = { 1, 1, 1 }, normal = {  1,  0,  0 }, uv = { 0, 0 } },
		{ position = { 1, 0, 1 }, normal = {  1,  0,  0 }, uv = { 0, 1 } },
		{ position = { 1, 0, 0 }, normal = {  1,  0,  0 }, uv = { 1, 1 } },
		{ position = { 1, 1, 0 }, normal = {  1,  0,  0 }, uv = { 1, 0 } },
	},

	// Bottom wall.
	.Minus_Y = {
		{ position = { 0, 0, 0 }, normal = {  0, -1,  0 }, uv = { 0, 0 } },
		{ position = { 1, 0, 0 }, normal = {  0, -1,  0 }, uv = { 1, 0 } },
		{ position = { 1, 0, 1 }, normal = {  0, -1,  0 }, uv = { 1, 1 } },
		{ position = { 0, 0, 1 }, normal = {  0, -1,  0 }, uv = { 0, 1 } },
	},

	// Top wall.
	.Plus_Y = {
		{ position = { 0, 1, 0 }, normal = {  0,  1,  0 }, uv = { 0, 0 } },
		{ position = { 0, 1, 1 }, normal = {  0,  1,  0 }, uv = { 0, 1 } },
		{ position = { 1, 1, 1 }, normal = {  0,  1,  0 }, uv = { 1, 1 } },
		{ position = { 1, 1, 0 }, normal = {  0,  1,  0 }, uv = { 1, 0 } },
	},
}

@(rodata)
block_indices := [6]Chunk_Mesh_Index{
	0, 1, 2, 0, 2, 3,
}
