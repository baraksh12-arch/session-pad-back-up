# -*- coding: utf-8 -*-
# TrackListener.py
# Attaches Ableton Live API property listeners to track headers.
# Fires JSON delta updates when track name, color, mute, solo, or arm changes.

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


class TrackHeaderListener(object):
    """Manages listeners for a single track's header properties."""

    def __init__(self, track_index, track, on_change):
        self._track_index = track_index
        self._track = track
        self._on_change = on_change  # (track_index, track) -> None
        self._color_listener_kind = None
        self._attach()

    def _attach(self):
        track = self._track
        try:
            track.add_name_listener(self._notify)
        except Exception:
            pass
        self._color_listener_kind = _attach_color_listener(track, self._notify)
        try:
            track.add_mute_listener(self._notify)
        except Exception:
            pass
        try:
            track.add_solo_listener(self._notify)
        except Exception:
            pass
        # arm is only available on AudioTrack and MidiTrack, not on GroupTrack/ReturnTrack
        try:
            if hasattr(track, "arm"):
                track.add_arm_listener(self._notify)
        except Exception:
            pass

    def _notify(self):
        try:
            self._on_change(self._track_index, self._track)
        except Exception:
            pass

    def disconnect(self):
        track = self._track
        for remover in [
            "remove_name_listener",
            "remove_mute_listener",
            "remove_solo_listener",
        ]:
            try:
                getattr(track, remover)(self._notify)
            except Exception:
                pass
        if self._color_listener_kind:
            _detach_color_listener(track, self._notify, self._color_listener_kind)
        try:
            if hasattr(track, "arm"):
                track.remove_arm_listener(self._notify)
        except Exception:
            pass


class TrackMatrixListener(object):
    """Manages track header listeners for all tracks in the session.

    Automatically rebuilds when tracks are added or removed.
    """

    def __init__(self, song, on_track_change, on_structure_changed=None):
        self._song = song
        self._on_track_change = on_track_change  # (track_index, track) -> None
        self._on_structure_changed_cb = on_structure_changed
        self._listeners = []
        self._build()
        song.add_tracks_listener(self._on_structure_changed)

    def _build(self):
        self._destroy()
        for t_idx, track in enumerate(self._song.tracks):
            listener = TrackHeaderListener(t_idx, track, self._on_track_change)
            self._listeners.append(listener)

    def _destroy(self):
        for listener in self._listeners:
            try:
                listener.disconnect()
            except Exception:
                pass
        self._listeners = []

    def _on_structure_changed(self):
        self._build()
        if self._on_structure_changed_cb:
            self._on_structure_changed_cb()

    def disconnect(self):
        try:
            self._song.remove_tracks_listener(self._on_structure_changed)
        except Exception:
            pass
        self._destroy()
