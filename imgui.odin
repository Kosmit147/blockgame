package blockgame

import "vendor/imgui"

import "core:c"

imgui_drag_double :: proc(label: cstring,
			  v: ^c.double,
			  v_speed := f32(1),
			  v_min := f32(0),
			  v_max := f32(0),
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
