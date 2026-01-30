package dmon

foreign import dmon "dmon.lib"

Watch_Id :: struct {
	id: u32,
}

Watch_Flags :: bit_set[Watch_Flag; u32]
Watch_Flag :: enum u32 {
	Recursive 	   = 0x1,
	Follow_Symlinks    = 0x2,
	Out_Of_Scope_Links = 0x4,
}

Action :: enum {
	Create = 1,
	Delete,
	Modify,
	Move,
}

Watch_Callback :: #type proc "c" (watch_id: Watch_Id,
				  action: Action,
				  rootdir: cstring,
				  filepath: cstring,
				  oldfilepath: cstring,
				  user: rawptr)

@(default_calling_convention="c", link_prefix="dmon_")
foreign dmon {
	init :: proc() ---
	deinit :: proc() ---
	watch :: proc(rootdir: cstring, watch_cb: Watch_Callback, flags: Watch_Flags, user: rawptr) -> Watch_Id ---
	unwatch :: proc(id: Watch_Id) ---
}
