# -*- coding: utf-8 -*-
# TransportListener.py
# Attaches listeners to Ableton Live song-level transport properties:
# is_playing, record_mode, metronome, overdub, tempo.
# Fires a JSON transport delta whenever any of these changes.

from __future__ import absolute_import, division


class TransportListener(object):
    """Manages all transport property listeners for a song."""

    def __init__(self, song, on_change):
        self._song = song
        self._on_change = on_change  # () -> None (caller reads song state directly)
        self._attach()

    def _attach(self):
        song = self._song
        listeners = [
            'add_is_playing_listener',
            'add_record_mode_listener',
            'add_metronome_listener',
            'add_overdub_listener',
            'add_tempo_listener',
        ]
        for method_name in listeners:
            try:
                getattr(song, method_name)(self._notify)
            except Exception:
                pass

    def _notify(self):
        try:
            self._on_change()
        except Exception:
            pass

    def disconnect(self):
        song = self._song
        removers = [
            'remove_is_playing_listener',
            'remove_record_mode_listener',
            'remove_metronome_listener',
            'remove_overdub_listener',
            'remove_tempo_listener',
        ]
        for method_name in removers:
            try:
                getattr(song, method_name)(self._notify)
            except Exception:
                pass
