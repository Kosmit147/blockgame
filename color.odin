package blockgame

import "core:math/linalg"

WHITE       :: Vec4{ 1, 1, 1, 1 }
BLACK       :: Vec4{ 0, 0, 0, 1 }
TRANSPARENT :: Vec4{ 0, 0, 0, 1 }

RED         :: Vec4{ 1, 0, 0, 1 }
GREEN       :: Vec4{ 0, 1, 0, 1 }
BLUE        :: Vec4{ 0, 0, 1, 1 }

MAGENTA     :: Vec4{ 1, 0, 1, 1 }

normalize_rgba8_color :: proc(rgba: [4]u8) -> Vec4 {
	return linalg.array_cast(rgba, f32) / 255
}

gamma_brighten :: proc(color: Vec4, gamma: f32) -> Vec4 {
	color := color
	color.rgb = linalg.pow(color.rgb, 1 / gamma)
	return color
}

gamma_darken :: proc(color: Vec4, gamma: f32) -> Vec4 {
	color := color
	color.rgb = linalg.pow(color.rgb, gamma)
	return color
}
