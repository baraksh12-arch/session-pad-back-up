# CommandHandler.py
# Executes JSON commands from the iOS app against Ableton Live's API.

import Live


class CommandHandler(object):
    """Executes iOS app commands against the Ableton Live Control Surface API."""

    def __init__(self, song):
        self._song = song

    def execute(self, cmd_name, payload):
        """Run a command. Returns (ok, error_message)."""
        try:
            handler = getattr(self, "_cmd_%s" % cmd_name, None)
            if handler is None:
                return False, "unknown command: %s" % cmd_name
            handler(payload or {})
            return True, None
        except Exception as e:
            return False, str(e)

    def _track_index(self, payload):
        return int(payload.get("track", 0))

    def _scene_index(self, payload):
        return int(payload.get("scene", 0))

    def _cmd_launchClip(self, payload):
        t_idx = self._track_index(payload)
        s_idx = self._scene_index(payload)
        tracks = list(self._song.tracks)
        if t_idx >= len(tracks):
            return
        track = tracks[t_idx]
        if s_idx >= len(track.clip_slots):
            return
        clip_slot = track.clip_slots[s_idx]
        if clip_slot.has_clip:
            clip_slot.clip.fire()
        elif hasattr(track, "arm") and track.arm:
            clip_slot.fire()

    def _cmd_launchScene(self, payload):
        s_idx = self._scene_index(payload)
        scenes = list(self._song.scenes)
        if s_idx < len(scenes):
            scenes[s_idx].fire()

    def _cmd_stopTrack(self, payload):
        t_idx = self._track_index(payload)
        tracks = list(self._song.tracks)
        if t_idx < len(tracks):
            tracks[t_idx].stop_all_clips()

    def _cmd_stopAll(self, payload):
        self._song.stop_all_clips()

    def _cmd_armTrack(self, payload):
        t_idx = self._track_index(payload)
        toggle = payload.get("toggle", True)
        tracks = list(self._song.tracks)
        if t_idx >= len(tracks):
            return
        track = tracks[t_idx]
        if hasattr(track, "arm"):
            track.arm = not track.arm if toggle else bool(payload.get("value", False))

    def _cmd_muteTrack(self, payload):
        t_idx = self._track_index(payload)
        toggle = payload.get("toggle", True)
        tracks = list(self._song.tracks)
        if t_idx >= len(tracks):
            return
        track = tracks[t_idx]
        track.mute = not track.mute if toggle else bool(payload.get("value", False))

    def _cmd_soloTrack(self, payload):
        t_idx = self._track_index(payload)
        toggle = payload.get("toggle", True)
        tracks = list(self._song.tracks)
        if t_idx >= len(tracks):
            return
        track = tracks[t_idx]
        track.solo = not track.solo if toggle else bool(payload.get("value", False))

    def _cmd_transport(self, payload):
        action = payload.get("action", "")
        song = self._song
        if action == "play":
            if not song.is_playing:
                song.start_playing()
        elif action == "stop":
            song.stop_playing()
        elif action == "continue":
            song.continue_playing()
        elif action == "record":
            song.record_mode = not song.record_mode
        elif action == "metronome":
            song.metronome = not song.metronome

    def _cmd_setTempo(self, payload):
        bpm = float(payload.get("bpm", 120.0))
        bpm = max(60.0, min(200.0, bpm))
        self._song.tempo = bpm
