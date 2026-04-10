package blockgame

import "vendor/imgui"

import "base:intrinsics"

import "core:c"
import "core:fmt"

imgui_drag_double :: proc(label: cstring,
			  v: ^c.double,
			  v_speed := f32(1),
			  v_min := f64(0),
			  v_max := f64(0),
			  format := cstring("%.3f"),
			  flags := imgui.SliderFlags{}) -> bool {
	v_min, v_max := v_min, v_max
	return imgui.DragScalar(label = label,
				data_type = .Double,
				p_data = v,
				v_speed = v_speed,
				p_min = &v_min,
				p_max = &v_max,
				format = format,
				flags = flags)
}

imgui_input_u32 :: proc(label: cstring,
			v: ^u32,
			step: u32 = 1,
			step_fast: u32 = 100,
			flags: imgui.InputTextFlags = {}) -> bool {
	step, step_fast := step, step_fast
	return imgui.InputScalar(label = label,
				 data_type = .U32,
				 p_data = v,
				 p_step = &step,
				 p_step_fast = &step_fast,
				 format = nil,
				 flags = flags)
}

imgui_input_i64 :: proc(label: cstring,
			v: ^i64,
			step: i64 = 1,
			step_fast: i64 = 100,
			flags: imgui.InputTextFlags = {}) -> bool {
	step, step_fast := step, step_fast
	return imgui.InputScalar(label = label,
				 data_type = .S64,
				 p_data = v,
				 p_step = &step,
				 p_step_fast = &step_fast,
				 format = nil,
				 flags = flags)
}

imgui_enum_select :: proc(label: cstring, value: ^$E) -> bool where intrinsics.type_is_enum(E) {
	value_changed := false
	if imgui.BeginCombo(label, fmt.ctprintf("%v", value^)) {
		for enum_value in E {
			is_selected := enum_value == value^
			if imgui.Selectable(fmt.ctprintf("%v", enum_value), is_selected) {
				value^ = enum_value
				value_changed = true
			}
			if is_selected do imgui.SetItemDefaultFocus()
		}
		imgui.EndCombo()
	}
	return value_changed
}

imgui_enum_list_select :: proc(value: ^$E) -> bool where intrinsics.type_is_enum(E) {
	value_changed := false
	for enum_value in E {
		is_selected := enum_value == value^
		if imgui.Selectable(fmt.ctprintf("%v", enum_value), is_selected) {
			value^ = enum_value
			value_changed = true
		}
		if is_selected do imgui.SetItemDefaultFocus()
	}
	return value_changed
}

imgui_slice_list_select :: proc(index: ^int, slice: []$T) -> bool {
	value_changed := false
	for slice_value, i in slice {
		is_selected := i == index^
		if imgui.Selectable(fmt.ctprintf("%v", slice_value), is_selected) {
			index^ = i
			value_changed = true
		}
		if is_selected do imgui.SetItemDefaultFocus()
	}
	return value_changed
}
