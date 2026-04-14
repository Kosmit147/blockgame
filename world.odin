package blockgame

import "base:runtime"

import "core:mem"
import "core:math/bits"
import "core:math/linalg"
import "core:slice"
import "core:thread"
import "core:os"
import "core:log"
import "core:testing"

WORLD_ORIGIN :: Vec3{  0,  0,  0 }
WORLD_UP     :: Vec3{  0,  1,  0 }
WORLD_DOWN   :: Vec3{  0, -1,  0 }

MIN_WORLD_LOAD_DISTANCE :: 1
MAX_WORLD_LOAD_DISTANCE :: 20

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

when TRACK_MEMORY {
	@(private="file") s_world_tracking_allocator: mem.Tracking_Allocator
	get_world_tracking_allocator :: proc() -> ^mem.Tracking_Allocator {
		return &s_world_tracking_allocator
	}
}

world_init :: proc(world: ^World, player_chunk: Chunk_Coordinate, load_distance: u32) -> (ok := false) {
	load_distance := clamp(load_distance, MIN_WORLD_LOAD_DISTANCE, MAX_WORLD_LOAD_DISTANCE)

	// We want to use a thread-safe heap allocator because the lifetimes of chunks are arbitrary and they are
	// handled from multiple threads.
	when TRACK_MEMORY {
		mem.tracking_allocator_init(&s_world_tracking_allocator, runtime.heap_allocator())
		world.allocator = mem.tracking_allocator(&s_world_tracking_allocator)
	} else {
		world.allocator = runtime.heap_allocator()
	}

	loaded_grid_side_length := load_distance * 2 + 1
	initial_chunk_map_capacity := loaded_grid_side_length * loaded_grid_side_length
	world.chunk_map = make(map[Chunk_Coordinate]Chunk, initial_chunk_map_capacity, world.allocator)

	MIN_CHUNK_GENERATION_THREADS :: 4
	thread.pool_init(&world.thread_pool,
			 world.allocator,
			 max(os.get_processor_core_count() - 1, MIN_CHUNK_GENERATION_THREADS))
	thread.pool_start(&world.thread_pool)

	nearby_chunks_iterator := make_nearby_chunks_iterator(origin = player_chunk, distance = load_distance)
	for chunk_coord in iterate_nearby_chunks(&nearby_chunks_iterator) {
		log.debugf("Loading chunk %v", chunk_coord)
		task_data := new(Generate_Chunk_Task_Data, world.allocator)
		task_data.chunk_coordinate = chunk_coord
		thread.pool_add_task(&world.thread_pool,
				     world.allocator,
				     generate_chunk_task,
				     task_data)
	}

	ok = true
	return
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

	when TRACK_MEMORY {
		check_tracking_allocator(s_world_tracking_allocator)
		mem.tracking_allocator_destroy(&s_world_tracking_allocator)
	}
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

world_regenerate :: proc(world: ^World, player_chunk: Chunk_Coordinate, load_distance: u32) {
	load_distance := clamp(load_distance, MIN_WORLD_LOAD_DISTANCE, MAX_WORLD_LOAD_DISTANCE)
	world_deinit(world)
	world^ = {}
	when TRACK_MEMORY {
		s_world_tracking_allocator = {}
	}
	world_init(world, player_chunk, load_distance)
}

world_raycast :: proc(world: World, ray: Ray, max_distance: f32) -> (block: ^Block,
								     block_position: Grid_World_Position,
								     place_block_offset: Grid_World_Position,
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
			place_block_offset = { -grid_traversal_direction.x, 0, 0 }
			min_t = t.x
		} else if (t.y <= t.x && t.y <= t.z) {
			current_block.y += grid_traversal_direction.y
			place_block_offset = { 0, -grid_traversal_direction.y, 0 }
			min_t = t.y
		} else if (t.z <= t.x && t.z <= t.y) {
			current_block.z += grid_traversal_direction.z
			place_block_offset = { 0, 0, -grid_traversal_direction.z }
			min_t = t.z
		}

		if min_t > max_distance do return

		block_position = Grid_World_Position(origin_block + current_block)
		block_ok: bool
		block, block_ok = world_get_block(world, block_position)

		if block_ok && !block_ignores_raycast(block^) {
			hit = true
			return
		}
	}
}

world_get_block :: proc(world: World, block_position: Grid_World_Position) -> (block: ^Block, ok := false) {
	chunk := world_get_block_owner(world, block_position) or_return
	return get_chunk_block_safe(chunk.blocks, to_grid_chunk_position(block_position))
}

world_get_block_owner :: proc(world: World, block_position: Grid_World_Position) -> (^Chunk, bool) {
	return &world.chunk_map[to_chunk_coordinate(block_position)]
}

world_destroy_block :: proc(world: World, block_position: Grid_World_Position) -> (block_destroyed := false) {
	block := world_get_block(world, block_position) or_return
	if block_can_be_destroyed(block^) {
		block^ = .Air
		block_destroyed = true
		world_update_chunk_mesh(world, to_chunk_coordinate(block_position))
		return
	}
	return
}

world_place_block :: proc(world: World, place_position: Grid_World_Position, block: Block) -> (block_placed := false) {
	replaced_block := world_get_block(world, place_position) or_return
	if block_can_be_placed_over(replaced_block^) {
		replaced_block^ = block
		block_placed = true
		world_update_chunk_mesh(world, to_chunk_coordinate(place_position))
		return
	}
	return
}

world_update_chunk_mesh :: proc(world: World, chunk_coordinate: Chunk_Coordinate) -> bool {
	chunk := (&world.chunk_map[chunk_coordinate]) or_return
	mesh_data := generate_chunk_mesh(chunk.blocks, context.temp_allocator)
	destroy_mesh(&chunk.mesh)
	chunk.mesh = create_chunk_mesh(mesh_data)
	return true
}

Block :: enum u8 {
	Air = 0,
	Stone,
	Dirt,
	Grass,
	Bricks,
}

// Position of a grid cell relative to the chunk origin.
Grid_Chunk_Position :: distinct [3]i32
// Position of a grid cell relative to the world origin.
Grid_World_Position :: distinct [3]i32
// Position of a grid cell corner relative to the chunk origin.
Grid_Corner_Chunk_Position :: distinct [3]i32
// Position of a grid cell corner relative to the world origin.
Grid_Corner_World_Position :: distinct [3]i32

to_grid_chunk_position :: proc(position: Grid_World_Position) -> Grid_Chunk_Position {
	return { position.x %% CHUNK_SIZE.x,
		 position.y,
		 position.z %% CHUNK_SIZE.z }
}

to_grid_world_position :: proc(position: Grid_Chunk_Position,
			       chunk_coordinate: Chunk_Coordinate) -> Grid_World_Position {
	return { chunk_coordinate.x * CHUNK_SIZE.x + position.x,
		 position.y,
		 chunk_coordinate.z * CHUNK_SIZE.z + position.z }
}

grid_world_position_to_chunk_coordinate :: proc(world_position: Grid_World_Position) -> Chunk_Coordinate {
	when ODIN_DEBUG {
		assert(bits.is_power_of_two(CHUNK_SIZE.x))
		assert(bits.is_power_of_two(CHUNK_SIZE.z))
	}
	return Chunk_Coordinate {
		x = (world_position.x & ~(CHUNK_SIZE.x - 1)) / CHUNK_SIZE.x,
		z = (world_position.z & ~(CHUNK_SIZE.z - 1)) / CHUNK_SIZE.z,
	}
}

world_position_to_chunk_coordinate :: proc(position: Vec3) -> Chunk_Coordinate {
	world_position := Grid_World_Position(linalg.array_cast(position, i32))
	return grid_world_position_to_chunk_coordinate(world_position)
}

to_chunk_coordinate :: proc{ grid_world_position_to_chunk_coordinate, world_position_to_chunk_coordinate }

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

@(require_results)
block_can_be_placed_over :: proc(block: Block) -> bool {
	return block == .Air
}

@(require_results)
block_can_be_destroyed :: proc(block: Block) -> bool {
	return true
}

@(require_results)
block_occludes_light :: proc(block: Block) -> bool {
	return block != .Air
}

Chunk :: struct {
	blocks: ^Chunk_Blocks,
	coordinate: Chunk_Coordinate,
	mesh: Mesh,
}

CHUNK_SIZE :: [3]i32{ 16, 64, 16 }
Chunk_Blocks :: [CHUNK_SIZE.y][CHUNK_SIZE.x][CHUNK_SIZE.z]Block

Chunk_Coordinate :: struct {
	x: i32,
	z: i32,
}

// This function can be called only from the main thread because it makes OpenGL calls.
create_chunk :: proc(coordinate: Chunk_Coordinate, blocks: ^Chunk_Blocks, mesh_data: Chunk_Mesh_Data) -> (chunk: Chunk) {
	return Chunk{ blocks, coordinate, create_chunk_mesh(mesh_data) }
}

destroy_chunk :: proc(chunk: ^Chunk, allocator: runtime.Allocator) {
	destroy_mesh(&chunk.mesh)
	free(chunk.blocks, allocator)
}

// TODO: Should probably be #no_bounds_check.
get_chunk_block :: proc(blocks: ^Chunk_Blocks, position: Grid_Chunk_Position) -> ^Block {
	return &blocks[position.y][position.x][position.z]
}

get_chunk_block_safe :: proc(blocks: ^Chunk_Blocks, position: Grid_Chunk_Position) -> (^Block, bool) {
	x_in_bounds := position.x >= 0 && position.x < CHUNK_SIZE.x
	y_in_bounds := position.y >= 0 && position.y < CHUNK_SIZE.y
	z_in_bounds := position.z >= 0 && position.z < CHUNK_SIZE.z
	if !x_in_bounds || !y_in_bounds || !z_in_bounds do return nil, false
	return get_chunk_block(blocks, position), true
}

Chunk_Blocks_Iterator :: struct {
	blocks: ^Chunk_Blocks,
	position: Grid_Chunk_Position,
	finished: bool,
}

make_chunk_blocks_iterator :: proc(blocks: ^Chunk_Blocks) -> (iterator: Chunk_Blocks_Iterator) {
	iterator.blocks = blocks
	return
}

iterate_chunk_blocks :: proc(iterator: ^Chunk_Blocks_Iterator) -> (^Block, Grid_Chunk_Position, bool) {
	if iterator.finished do return {}, {}, false

	return_block := get_chunk_block(iterator.blocks, iterator.position)
	return_block_position := iterator.position

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

	return return_block, return_block_position, true
}

// Iterates over chunk coordinates around the origin coordinate in a spiral pattern.
// 4 - 3 - 2
// |       |
// 5   0 - 1
// |
// 6 - 7 - 8
Nearby_Chunks_Iterator :: struct {
	current_coords: [2]i32,
	direction_index: i32,
	walked: i32,
	current_walk_length: i32, // How far we have to walk until we change direction.
	max_walk_length: i32, // When do we stop walking.
	finished: bool,
}

make_nearby_chunks_iterator :: proc(origin: Chunk_Coordinate, distance: u32) -> Nearby_Chunks_Iterator {
	return Nearby_Chunks_Iterator {
		current_coords = { origin.x, origin.z },
		current_walk_length = 1,
		max_walk_length = i32(distance * 2),
	}
}

iterate_nearby_chunks :: proc(iterator: ^Nearby_Chunks_Iterator) -> (Chunk_Coordinate, bool) {
	@(static, rodata)
	walk_directions := [4][2]i32{
		{  1,  0 },
		{  0,  1 },
		{ -1,  0 },
		{  0, -1 },
	}

	if iterator.finished do return {}, false

	return_chunk_coord := iterator.current_coords
	iterator.current_coords += walk_directions[iterator.direction_index]
	iterator.walked += 1
	if iterator.walked >= iterator.current_walk_length {
		if iterator.walked > iterator.max_walk_length do iterator.finished = true
		iterator.walked = 0
		iterator.direction_index += 1
		if iterator.direction_index % 2 == 0 do iterator.current_walk_length += 1
		if iterator.direction_index >= len(walk_directions) do iterator.direction_index = 0
	}

	return Chunk_Coordinate{ return_chunk_coord.x, return_chunk_coord.y }, true
}

@(test)
nearby_chunks_iterator_test :: proc(t: ^testing.T) {
	@(static, rodata) expected := [?]Chunk_Coordinate {
		// Distance 0
		{  0,  0 },

		// Distance 1
		{  1,  0 }, {  1,  1 },
		{  0,  1 }, { -1,  1 },
		{ -1,  0 }, { -1, -1 },
		{  0, -1 }, {  1, -1 },

		// Distance 2
		{  2, -1 }, {  2,  0 }, {  2,  1 }, {  2,  2 },
		{  1,  2 }, {  0,  2 }, { -1,  2 }, { -2,  2 },
		{ -2,  1 }, { -2,  0 }, { -2, -1 }, { -2, -2 },
		{ -1, -2 }, {  0, -2 }, {  1, -2 }, {  2, -2 },

		// Distance 3
		{  3, -2 }, {  3, -1 }, {  3,  0 }, {  3,  1 }, {  3,  2 }, {  3,  3 },
		{  2,  3 }, {  1,  3 }, {  0,  3 }, { -1,  3 }, { -2,  3 }, { -3,  3 },
		{ -3,  2 }, { -3,  1 }, { -3,  0 }, { -3, -1 }, { -3, -2 }, { -3, -3 },
		{ -2, -3 }, { -1, -3 }, {  0, -3 }, {  1, -3 }, {  2, -3 }, {  3, -3 },
	}

	{
		iterator := make_nearby_chunks_iterator({ 0, 0 }, 3)
		i := 0
		for coord in iterate_nearby_chunks(&iterator) {
			testing.expectf(t, coord == expected[i], "i = %v, coord = %v, expected = %v", i, coord, expected[i])
			i += 1
		}
		testing.expect(t, i == len(expected))
	}

	{
		origin := Chunk_Coordinate{ 7, -5 }
		iterator := make_nearby_chunks_iterator(origin, 3)
		i := 0
		for coord in iterate_nearby_chunks(&iterator) {
			expected := Chunk_Coordinate{ expected[i].x + origin.x, expected[i].z + origin.z }
			testing.expectf(t, coord == expected, "i = %v, coord = %v, expected = %v", i, coord, expected)
			i += 1
		}
		testing.expect(t, i == len(expected))
	}
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

	mesh.vertices = make([dynamic]Chunk_Mesh_Vertex, allocator)
	mesh.indices = make([dynamic]Chunk_Mesh_Index, allocator)

	chunk_blocks_iterator := make_chunk_blocks_iterator(blocks)
	index_offset := u32(0)
	for block, block_position in iterate_chunk_blocks(&chunk_blocks_iterator) {
		if block_is_invisible(block^) do continue
		visible_faces_directions := visible_faces(blocks, block_position)
		for face_vertices_data, facing_direction in block_faces {
			if facing_direction not_in visible_faces_directions do continue
			vertices: [4]Chunk_Mesh_Vertex
			assert(len(face_vertices_data) == len(vertices))
			for &vertex, vertex_index in vertices {
				vertex_data := face_vertices_data[vertex_index]
				corner_position := vertex_data.position + Grid_Corner_Chunk_Position(block_position)

				vertex = Chunk_Mesh_Vertex {
					position = linalg.array_cast(corner_position, f32),
					normal = vertex_data.normal,
					uv = map_block_uv_to_atlas(vertex_data.uv, block^, facing_direction),
					ambient_occlusion = ambient_occlusion(blocks, corner_position),
				}
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
visible_faces :: proc(blocks: ^Chunk_Blocks, position: Grid_Chunk_Position) -> (directions: World_Directions) {
	offsets := [World_Direction][3]i32{
		.Plus_X  = { +1,  0,  0 },
		.Minus_X = { -1,  0,  0 },
		.Plus_Y  = {  0, +1,  0 },
		.Minus_Y = {  0, -1,  0 },
		.Plus_Z  = {  0,  0, +1 },
		.Minus_Z = {  0,  0, -1 },
	}

	for offset, direction in offsets {
		neighbor, neighbor_ok := get_chunk_block_safe(blocks, position + Grid_Chunk_Position(offset))
		if !neighbor_ok || (neighbor_ok && !block_is_fully_opaque(neighbor^)) do directions += { direction }
	}
	return
}

@(private="file")
map_block_uv_to_atlas :: proc(uv: Vec2, block: Block, block_facing: World_Direction) -> Vec2 {
	ATLAS_SIZE :: 10

	atlas_rect_origin: Vec2
	atlas_rect_size := Vec2{ 1.0 / ATLAS_SIZE, 1.0 / ATLAS_SIZE }

	switch block {
	case .Air:
	case .Stone:   atlas_rect_origin = Vec2{ 0.0, 0.0 }
	case .Dirt:    atlas_rect_origin = Vec2{ 0.1, 0.0 }
	case .Grass:
		#partial switch block_facing {
		case .Plus_Y:      atlas_rect_origin = Vec2{ 0.2, 0.0 }
		case .Minus_Y:     atlas_rect_origin = Vec2{ 0.1, 0.0 }
		case:              atlas_rect_origin = Vec2{ 0.3, 0.0 }
		}
	case .Bricks:  atlas_rect_origin = Vec2{ 0.4, 0.0 }
	}

	return atlas_rect_origin + uv * atlas_rect_size
}

// Ambient occlusion is a value between 0 and 8 which represents the number of light-occluding blocks around the block
// corner.
@(private="file")
ambient_occlusion :: proc(blocks: ^Chunk_Blocks, position: Grid_Corner_Chunk_Position) -> (occlusion := u32(0)) {
	// TODO: Fix occlusion not working properly on chunk boundaries.
	neighboring_block_positions := [8]Grid_Chunk_Position{
		Grid_Chunk_Position(position) + { -1, -1, -1 },
		Grid_Chunk_Position(position) + { -1, -1,  0 },
		Grid_Chunk_Position(position) + {  0, -1, -1 },
		Grid_Chunk_Position(position) + {  0, -1,  0 },
		Grid_Chunk_Position(position) + { -1,  0, -1 },
		Grid_Chunk_Position(position) + { -1,  0,  0 },
		Grid_Chunk_Position(position) + {  0,  0, -1 },
		Grid_Chunk_Position(position) + {  0,  0,  0 },
	}

	for block_position in neighboring_block_positions {
		block := get_chunk_block_safe(blocks, block_position) or_continue
		if block_occludes_light(block^) do occlusion += 1
	}

	return
}

Chunk_Mesh_Vertex :: struct #all_or_none {
	position: Vec3,
	normal: Vec3,
	uv: Vec2,
	ambient_occlusion: u32,
}

Chunk_Mesh_Index :: u32

Chunk_Mesh_Vertex_Input_Data :: struct {
	position: Grid_Corner_Chunk_Position,
	normal: Vec3,
	uv: Vec2,
}

@(private="file", rodata)
block_faces := [World_Direction][4]Chunk_Mesh_Vertex_Input_Data{
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

@(private="file", rodata)
block_indices := [6]Chunk_Mesh_Index{ 0, 1, 2, 0, 2, 3 }
