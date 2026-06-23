package blockgame

import ma "vendor:miniaudio"

import "core:log"
import "core:os"
import "core:strings"
import "core:mem/virtual"
import "core:fmt"

TRACKS_PATH        :: "sound/tracks/"
PLACE_SOUND_PATH   :: "sound/place.mp3"
DESTROY_SOUND_PATH :: "sound/destroy.wav"

INITIAL_MASTER_VOLUME :: 0.15
INITIAL_EFFECT_VOLUME :: 1
INITIAL_MUSIC_VOLUME  :: 0

Sound_System :: struct {
  engine: ma.engine,
  effect_sound_group: ma.sound_group,
  music_sound_group: ma.sound_group,

  tracks: [dynamic]Track,
  current_track_index: int,

  place_sound: Effect_Sound,
  destroy_sound: Effect_Sound,

  arena: virtual.Arena,
}

g_sound_system: Sound_System

EFFECT_SOUND_FLAGS :: ma.sound_flags{ .NO_PITCH, .NO_SPATIALIZATION }
MUSIC_SOUND_FLAGS  :: ma.sound_flags{ .STREAM, .NO_PITCH, .NO_SPATIALIZATION }

init_sound :: proc() -> (ok := false) {
  arena_error := virtual.arena_init_growing(&g_sound_system.arena)
  if arena_error != nil do return
  defer if !ok do virtual.arena_destroy(&g_sound_system.arena)

  if ma.engine_init(nil, &g_sound_system.engine) != .SUCCESS do return
  defer if !ok do ma.engine_uninit(&g_sound_system.engine)

  ma.sound_group_init(&g_sound_system.engine, EFFECT_SOUND_FLAGS, nil, &g_sound_system.effect_sound_group)
  defer if !ok do ma.sound_group_uninit(&g_sound_system.effect_sound_group)

  ma.sound_group_init(&g_sound_system.engine, MUSIC_SOUND_FLAGS, nil, &g_sound_system.music_sound_group)
  defer if !ok do ma.sound_group_uninit(&g_sound_system.music_sound_group)

  sound_set_master_volume(INITIAL_MASTER_VOLUME)
  sound_set_effect_volume(INITIAL_EFFECT_VOLUME)
  sound_set_music_volume(INITIAL_MUSIC_VOLUME)

  sound_init_tracks()
  defer if !ok do sound_deinit_tracks()

  g_sound_system.current_track_index = 0
  sound_play_track(g_sound_system.current_track_index)

  g_sound_system.place_sound, _ = create_effect_sound(PLACE_SOUND_PATH)
  defer if !ok do destroy_effect_sound(g_sound_system.place_sound)

  g_sound_system.destroy_sound, _ = create_effect_sound(DESTROY_SOUND_PATH)
  defer if !ok do destroy_effect_sound(g_sound_system.destroy_sound)

  ok = true
  return
}

deinit_sound :: proc() {
  destroy_effect_sound(g_sound_system.place_sound)
  destroy_effect_sound(g_sound_system.destroy_sound)
  sound_deinit_tracks()
  ma.sound_group_uninit(&g_sound_system.music_sound_group)
  ma.sound_group_uninit(&g_sound_system.effect_sound_group)
  ma.engine_uninit(&g_sound_system.engine)
  virtual.arena_destroy(&g_sound_system.arena)
}

sound_init_tracks :: proc() {
  walker := os.walker_create(TRACKS_PATH)
  defer os.walker_destroy(&walker)

  for file in os.walker_walk(&walker) {
    walker_error_path, walker_error := os.walker_error(&walker)
    if walker_error != nil {
      log.warnf(
        "Error when walking sound tracks directory: %v. Problematic path is `%v`.",
        walker_error,
        walker_error_path
      )
      continue
    }

    if file.type != .Regular do continue
    track := create_track(file.name, file.fullpath) or_continue
    append(&g_sound_system.tracks, track)
  }

  shrink(&g_sound_system.tracks)
}

sound_deinit_tracks :: proc() {
  for track in g_sound_system.tracks do destroy_track(track)
  delete(g_sound_system.tracks)
}

Track :: struct {
  name: string,
  sound: ^ma.sound,
}

create_track :: proc(name: string, filepath: string) -> (track: Track, ok := false) {
  arena_allocator := virtual.arena_allocator(&g_sound_system.arena)
  track.name = strings.clone(name, arena_allocator)
  track.sound = new(ma.sound, arena_allocator)
  cstring_path := strings.clone_to_cstring(filepath, context.temp_allocator)
  if ma.sound_init_from_file(
    pEngine = &g_sound_system.engine,
    pFilePath = cstring_path,
    flags = MUSIC_SOUND_FLAGS,
    pGroup = &g_sound_system.music_sound_group,
    pDoneFence = nil,
    pSound = track.sound,
  ) != .SUCCESS {
    log.errorf("Failed to initialize track from file `%v`.", cstring_path)
    return
  }

  ok = true
  return
}

destroy_track :: proc(track: Track) {
  ma.sound_uninit(track.sound)
}

track_formatter :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
  track := cast(^Track)arg.data
  if verb == 'v' {
    fmt.wprintf(fi.writer, "%v", track.name)
    return true
  }
  return false
}

Effect_Sound :: struct {
  sound: ^ma.sound,
}

create_effect_sound :: proc(filepath: string) -> (sound: Effect_Sound, ok := false) {
  arena_allocator := virtual.arena_allocator(&g_sound_system.arena)
  sound.sound = new(ma.sound, arena_allocator)
  cstring_path := strings.clone_to_cstring(filepath, context.temp_allocator)
  if ma.sound_init_from_file(
    pEngine = &g_sound_system.engine,
    pFilePath = cstring_path,
    flags = EFFECT_SOUND_FLAGS,
    pGroup = &g_sound_system.effect_sound_group,
    pDoneFence = nil,
    pSound = sound.sound,
  ) != .SUCCESS {
    log.errorf("Failed to initialize sound from file `%v`.", cstring_path)
    return
  }

  ok = true
  return
}

destroy_effect_sound :: proc(sound: Effect_Sound) {
  ma.sound_uninit(sound.sound)
}

sound_update :: proc() {
  if len(g_sound_system.tracks) == 0 do return
  current_track_index := g_sound_system.current_track_index
  current_track := g_sound_system.tracks[current_track_index]
  if !ma.sound_is_playing(current_track.sound) {
    next_track_index := (current_track_index + 1) % len(g_sound_system.tracks)
    sound_play_track(next_track_index)
  }
}

sound_play_track :: proc(track_index: int) -> bool {
  if track_index >= len(g_sound_system.tracks) {
    log.warnf(
      "Requested to play track at index %v, but there are only %v tracks loaded.",
      track_index,
      len(g_sound_system.tracks),
    )
    return false
  }

  current_track := g_sound_system.tracks[g_sound_system.current_track_index]
  ma.sound_stop(current_track.sound)
  ma.sound_seek_to_pcm_frame(current_track.sound, 0)

  requested_track := g_sound_system.tracks[track_index]
  ma.sound_seek_to_pcm_frame(requested_track.sound, 0)
  ma.sound_start(requested_track.sound)

  g_sound_system.current_track_index = track_index
  return true
}

sound_current_track_index :: proc() -> int {
  return g_sound_system.current_track_index
}

sound_current_track :: proc() -> Track {
  return g_sound_system.tracks[g_sound_system.current_track_index]
}

sound_tracks :: proc() -> []Track {
  return g_sound_system.tracks[:]
}

sound_play_place_sound :: proc() {
  ma.sound_seek_to_pcm_frame(g_sound_system.place_sound.sound, 0)
  ma.sound_start(g_sound_system.place_sound.sound)
}

sound_play_destroy_sound :: proc() {
  ma.sound_seek_to_pcm_frame(g_sound_system.destroy_sound.sound, 0)
  ma.sound_start(g_sound_system.destroy_sound.sound)
}

sound_master_volume :: proc() -> f32 {
  return ma.engine_get_volume(&g_sound_system.engine)
}

sound_set_master_volume :: proc(volume: f32) {
  ma.engine_set_volume(&g_sound_system.engine, volume)
}

sound_effect_volume :: proc() -> f32 {
  return ma.sound_group_get_volume(&g_sound_system.effect_sound_group)
}

sound_set_effect_volume :: proc(volume: f32) {
  ma.sound_group_set_volume(&g_sound_system.effect_sound_group, volume)
}

sound_music_volume :: proc() -> f32 {
  return ma.sound_group_get_volume(&g_sound_system.music_sound_group)
}

sound_set_music_volume :: proc(volume: f32) {
  ma.sound_group_set_volume(&g_sound_system.music_sound_group, volume)
}
