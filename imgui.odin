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

imgui_select_enum :: proc(label: cstring, value: ^$E) -> bool where intrinsics.type_is_enum(E) {
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
