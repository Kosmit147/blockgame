package blockgame

import "core:math/linalg"

WHITE       :: Vec4{ 1, 1, 1, 1 }
BLACK       :: Vec4{ 0, 0, 0, 1 }
TRANSPARENT :: Vec4{ 0, 0, 0, 1 }

RED         :: Vec4{ 1, 0, 0, 1 }
GREEN       :: Vec4{ 0, 1, 0, 1 }
BLUE        :: Vec4{ 0, 0, 1, 1 }

normalize_rgba8_color :: proc(rgba: [4]u8) -> Vec4 {
	return linalg.array_cast(rgba, f32) / 255
}
