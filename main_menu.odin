package blockgame

import "core:math/linalg"

Main_Menu :: struct {}

@(private="file") TITLE_TEXT :: "BLOCKGAME"
@(private="file") TITLE_TEXT_SCALE :: 30
@(private="file") PRESS_ENTER_TEXT :: "PRESS ENTER"
@(private="file") PRESS_ENTER_TEXT_SCALE :: 6

ENTER_GAME_KEY :: Key.Enter

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
		if event.key == ENTER_GAME_KEY do change_scene(.Overworld)
	}
}

main_menu_update :: proc(delta_time: f32, scene_data: rawptr) {
	main_menu := cast(^Main_Menu)scene_data
}

main_menu_render :: proc(scene_data: rawptr) {
	main_menu := cast(^Main_Menu)scene_data

	renderer_begin_2d_frame()
	defer renderer_end_frame()

	window_size := linalg.array_cast(window_size(), f32)

	{
		text_size := renderer_2d_text_size(TITLE_TEXT, TITLE_TEXT_SCALE)
		text_pos := window_size / 2 - text_size / 2
		renderer_2d_submit_text(TITLE_TEXT, text_pos, scale = TITLE_TEXT_SCALE)
	}

	{
		text_size := renderer_2d_text_size(PRESS_ENTER_TEXT, PRESS_ENTER_TEXT_SCALE)
		text_pos := window_size / 2 - text_size / 2
		text_pos.y += window_size.y / 10
		renderer_2d_submit_text(PRESS_ENTER_TEXT, text_pos, scale = PRESS_ENTER_TEXT_SCALE)
	}
}
