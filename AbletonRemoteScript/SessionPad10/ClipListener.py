# ClipListener.py
# Attaches Ableton Live API property listeners to every clip slot
# in the session. When a clip property changes, the listener fires
# a JSON delta update to the iOS app immediately.

from __future__ import absolute_import, division


def _attach_color_listener(obj, callback):
    """Attach color_index (Live 11+) or color (Live 10) listener."""
    if hasattr(obj, "add_color_index_listener"):
        try:
            obj.add_color_index_listener(callback)
            return "color_index"
        except Exception:
            pass
    if hasattr(obj, "add_color_listener"):
        try:
            obj.add_color_listener(callback)
            return "color"
        except Exception:
            pass
    return None


def _detach_color_listener(obj, callback, kind):
    if kind == "color_index" and hasattr(obj, "remove_color_index_listener"):
        try:
            obj.remove_color_index_listener(callback)
        except Exception:
            pass
    elif kind == "color" and hasattr(obj, "remove_color_listener"):
        try:
            obj.remove_color_listener(callback)
        except Exception:
            pass


class ClipSlotListener(object):
    """Manages all listeners for a single clip slot."""

    def __init__(self, track_index, scene_index, clip_slot, on_change):
        self._track_index = track_index
        self._scene_index = scene_index
        self._clip_slot = clip_slot
        self._on_change = on_change  # Callable: (track_idx, scene_idx, clip_slot) -> None
        self._clip_listeners_active = False
        self._color_listener_kind = None
        self._attach_slot_listeners()

    def _attach_slot_listeners(self):
        """Attach listeners to the slot itself (has_clip changes)."""
        slot = self._clip_slot
        if slot.has_clip_has_listener(self._on_has_clip_changed):
            pass  # Already attached
        else:
            slot.add_has_clip_listener(self._on_has_clip_changed)

        if slot.has_clip:
            self._attach_clip_listeners()

    def _attach_clip_listeners(self):
        """Attach listeners to the clip inside the slot."""
        if self._clip_listeners_active:
            return
        clip = self._clip_slot.clip
        if clip is None:
            return
        try:
            clip.add_playing_status_listener(self._notify)
            clip.add_name_listener(self._notify)
            self._color_listener_kind = _attach_color_listener(clip, self._notify)
            self._clip_listeners_active = True
        except Exception:
            pass

    def _detach_clip_listeners(self):
        """Remove clip listeners when clip is removed from slot."""
        if not self._clip_listeners_active:
            return
        clip = self._clip_slot.clip
        if clip is None:
            self._clip_listeners_active = False
            self._color_listener_kind = None
            return
        try:
            clip.remove_playing_status_listener(self._notify)
            clip.remove_name_listener(self._notify)
            if self._color_listener_kind:
                _detach_color_listener(clip, self._notify, self._color_listener_kind)
        except Exception:
            pass
        self._clip_listeners_active = False
        self._color_listener_kind = None

    def _on_has_clip_changed(self):
        """Called when a clip is added to or removed from the slot."""
        if self._clip_slot.has_clip:
            self._attach_clip_listeners()
        else:
            self._detach_clip_listeners()
        self._notify()

    def _notify(self):
        """Trigger a JSON delta update for this clip slot."""
        try:
            self._on_change(self._track_index, self._scene_index, self._clip_slot)
        except Exception:
            pass

    def disconnect(self):
        """Remove all listeners. Must be called before the script disconnects."""
        try:
            slot = self._clip_slot
            if slot.has_clip_has_listener(self._on_has_clip_changed):
                slot.remove_has_clip_listener(self._on_has_clip_changed)
        except Exception:
            pass
        self._detach_clip_listeners()


class ClipMatrixListener(object):
    """Manages clip slot listeners for the entire session matrix.

    When tracks or scenes are added/removed, this class rebuilds
    the listener matrix automatically.
    """

    def __init__(self, song, on_clip_change, on_structure_changed=None):
        self._song = song
        self._on_clip_change = on_clip_change  # (track_idx, scene_idx, clip_slot) -> None
        self._on_structure_changed_cb = on_structure_changed
        self._slot_listeners = []  # Flat list of ClipSlotListener
        self._build_matrix()

        # Listen for structural changes
        song.add_tracks_listener(self._on_structure_changed)
        song.add_scenes_listener(self._on_structure_changed)

    def _build_matrix(self):
        """Build listeners for every clip slot in the current matrix."""
        self._destroy_all_listeners()
        tracks = list(self._song.tracks)
        scenes = list(self._song.scenes)

        for t_idx, track in enumerate(tracks):
            for s_idx in range(len(scenes)):
                try:
                    clip_slot = track.clip_slots[s_idx]
                    listener = ClipSlotListener(
                        t_idx, s_idx, clip_slot, self._on_clip_change
                    )
                    self._slot_listeners.append(listener)
                except (IndexError, AttributeError):
                    pass

    def _destroy_all_listeners(self):
        """Disconnect and clear all slot listeners."""
        for listener in self._slot_listeners:
            try:
                listener.disconnect()
            except Exception:
                pass
        self._slot_listeners = []

    def _on_structure_changed(self):
        """Called when tracks or scenes are added/removed.

        Rebuilds the entire listener matrix. This is the correct
        approach — partial rebuild would risk missing slots.
        """
        self._build_matrix()
        if self._on_structure_changed_cb:
            self._on_structure_changed_cb()

    def disconnect(self):
        """Full cleanup. Call this in the Remote Script's disconnect()."""
        try:
            self._song.remove_tracks_listener(self._on_structure_changed)
        except Exception:
            pass
        try:
            self._song.remove_scenes_listener(self._on_structure_changed)
        except Exception:
            pass
        self._destroy_all_listeners()
