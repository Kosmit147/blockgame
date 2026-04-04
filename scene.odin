package blockgame

import "base:runtime"

import "core:log"

Scene_Id :: enum {
	Main_Menu,
	Overworld,
}

Scene :: struct #all_or_none {
	init_proc: proc(scene_data: rawptr) -> bool,
	deinit_proc: proc(scene_data: rawptr),
	update_proc: proc(delta_time: f32, scene_data: rawptr),
	on_event_proc: proc(event: Event, scene_data: rawptr),
	render_proc: proc(scene_data: rawptr),

	scene_data: rawptr,
	scene_data_allocator: runtime.Allocator,
}

@(private="file")
s_current_scene: Maybe(Scene)

change_scene :: proc(scene_id: Scene_Id, scene_data_allocator := context.allocator) -> (ok := false) {
	scene_deinit()

	switch scene_id {
	case .Main_Menu:
		s_current_scene = Scene {
			init_proc = main_menu_init,
			deinit_proc = main_menu_deinit,
			update_proc = main_menu_update,
			on_event_proc = main_menu_on_event,
			render_proc = main_menu_render,
			scene_data = new(Main_Menu, scene_data_allocator),
			scene_data_allocator = scene_data_allocator,
		}
	case .Overworld:
		s_current_scene = Scene {
			init_proc = overworld_init,
			deinit_proc = overworld_deinit,
			update_proc = overworld_update,
			on_event_proc = overworld_on_event,
			render_proc = overworld_render,
			scene_data = new(Overworld, scene_data_allocator),
			scene_data_allocator = scene_data_allocator,
		}
	case:
		assert(false, "should have never gotten here")
	}

	if !scene_init() do log.panicf("Failed to initialize %v scene.", scene_id)

	ok = true
	return
}

@(private="file")
scene_init :: proc() -> (ok := false) {
	scene := s_current_scene.? or_return
	return scene.init_proc(scene.scene_data)
}

scene_deinit :: proc() -> (ok := false) {
	scene := s_current_scene.? or_return
	scene.deinit_proc(scene.scene_data)
	free(scene.scene_data, scene.scene_data_allocator)
	ok = true
	return
}

scene_update :: proc(delta_time: f32) -> (ok := false) {
	scene := s_current_scene.? or_return
	scene.update_proc(delta_time, scene.scene_data)
	ok = true
	return
}

scene_on_event :: proc(event: Event) -> (ok := false) {
	scene := s_current_scene.? or_return
	scene.on_event_proc(event, scene.scene_data)
	ok = true
	return
}

scene_render :: proc() -> (ok := false) {
	scene := s_current_scene.? or_return
	scene.render_proc(scene.scene_data)
	ok = true
	return
}
