# SceneListener.py
# Attaches Ableton Live API property listeners to scenes.
# Fires JSON delta updates when a scene's name or color changes.
#
# Mirrors the structure of TrackListener.py. The iOS app already decodes
# MSG_SCENE_UPDATE, and the initial full-state dump sends every scene once;
# this keeps scene name/color in sync for changes made after connection.


class SceneRowListener(object):
    """Manages listeners for a single scene's properties."""

    def __init__(self, scene_index, scene, on_change):
        self._scene_index = scene_index
        self._scene = scene
        self._on_change = on_change  # (scene_index, scene) -> None
        self._attach()

    def _attach(self):
        scene = self._scene
        try:
            scene.add_name_listener(self._notify)
        except Exception:
            pass
        try:
            scene.add_color_index_listener(self._notify)
        except Exception:
            pass

    def _notify(self):
        try:
            self._on_change(self._scene_index, self._scene)
        except Exception:
            pass

    def disconnect(self):
        scene = self._scene
        for remover in ['remove_name_listener', 'remove_color_index_listener']:
            try:
                getattr(scene, remover)(self._notify)
            except Exception:
                pass


class SceneMatrixListener(object):
    """Manages scene listeners for all scenes in the session.

    Automatically rebuilds when scenes are added or removed.
    """

    def __init__(self, song, on_scene_change, on_structure_changed=None):
        self._song = song
        self._on_scene_change = on_scene_change  # (scene_index, scene) -> None
        self._on_structure_changed_cb = on_structure_changed
        self._listeners = []
        self._build()
        song.add_scenes_listener(self._on_structure_changed)

    def _build(self):
        self._destroy()
        for s_idx, scene in enumerate(self._song.scenes):
            listener = SceneRowListener(s_idx, scene, self._on_scene_change)
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
            self._song.remove_scenes_listener(self._on_structure_changed)
        except Exception:
            pass
        self._destroy()
