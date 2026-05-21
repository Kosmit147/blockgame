package blockgame

Main_Menu :: struct {}

MAIN_MENU_TITLE_TEXT             :: "BLOCKGAME"
MAIN_MENU_TITLE_TEXT_SCALE       :: 30
MAIN_MENU_PRESS_ENTER_TEXT       :: "PRESS ENTER"
MAIN_MENU_PRESS_ENTER_TEXT_SCALE :: 6

MAIN_MENU_ENTER_GAME_KEY :: Key.Enter

main_menu_init :: proc(scene_data: rawptr) -> (ok := false) {
	main_menu := cast(^Main_Menu)scene_data
	ok = true
	return
}

main_menu_deinit :: proc(scene_data: rawptr) {
	main_menu := cast(^Main_Menu)scene_data
}

main_menu_on_event :: proc(event: Event, scene_data: rawptr) {
	main_menu := cast(^Main_Menu)scene_data

	#partial switch event in event {
	case Key_Pressed_Event:
		if event.key == MAIN_MENU_ENTER_GAME_KEY do change_scene(.Overworld)
	}
}

main_menu_update :: proc(delta_time: f32, scene_data: rawptr) {
	main_menu := cast(^Main_Menu)scene_data
}

main_menu_render :: proc(scene_data: rawptr) {
	main_menu := cast(^Main_Menu)scene_data

	renderer_begin_2d_frame()
	defer renderer_end_frame()

	window_size := cast(Vec2)window_size()

	{
		text_size := renderer_2d_text_size(MAIN_MENU_TITLE_TEXT, MAIN_MENU_TITLE_TEXT_SCALE)
		text_pos := window_size / 2 - text_size / 2
		renderer_2d_submit_text(MAIN_MENU_TITLE_TEXT, text_pos, scale = MAIN_MENU_TITLE_TEXT_SCALE)
	}

	{
		text_size := renderer_2d_text_size(MAIN_MENU_PRESS_ENTER_TEXT, MAIN_MENU_PRESS_ENTER_TEXT_SCALE)
		text_pos := window_size / 2 - text_size / 2
		text_pos.y += window_size.y / 10
		renderer_2d_submit_text(MAIN_MENU_PRESS_ENTER_TEXT, text_pos, scale = MAIN_MENU_PRESS_ENTER_TEXT_SCALE)
	}
}
