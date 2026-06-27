# SessionPad.py
# Main Ableton Live Remote Script entry point.
#
# Bridges Live session state to the macOS SessionPad Bridge via localhost TCP.
# All Live API access happens on Live's thread (update_display / listeners).

import time

from .Protocol import (
    PROTOCOL_VERSION,
    HEARTBEAT_INTERVAL_MS,
    T_ERROR,
    T_GET_STATE,
    T_STATE_FULL,
    T_DELTA_CLIP,
    T_DELTA_TRACK,
    T_DELTA_SCENE,
    T_DELTA_TRANSPORT,
    T_HEARTBEAT,
    T_ACK,
    T_CMD,
    encode_message,
    decode_message,
    dumps,
    encode_clip_delta,
    encode_track_delta,
    encode_scene_delta,
    encode_transport_delta,
    encode_playpos_delta,
    build_full_state,
    T_DELTA_PLAYPOS,
)
from .CommandHandler import CommandHandler
from .ClipListener import ClipMatrixListener
from .TrackListener import TrackMatrixListener
from .SceneListener import SceneMatrixListener
from .TransportListener import TransportListener
from .transport.LiveBridgeClient import LiveBridgeClient

FLUSH_TICK_INTERVAL = 1
PLAYPOS_TICK_INTERVAL = 2
T_BRIDGE_SESSION = "bridge.session"
SCRIPT_BUILD = "2026-06-27-playpos2"


class SessionPad(object):
    """SessionPad Ableton Live Remote Script."""

    def __init__(self, c_instance):
        self._c_instance = c_instance
        self._song = c_instance.song()
        self._tick_count = 0
        self._last_heartbeat = 0.0
        self._seq = 0
        self._snapshot_rev = 0
        self._playpos_log_count = 0

        self._command_handler = CommandHandler(self._song, log=self._log)
        self._pending_outbound = []

        self._bridge = LiveBridgeClient(
            on_connected=self._on_bridge_connected,
            on_disconnected=self._on_bridge_disconnected,
        )

        self._clip_listener = ClipMatrixListener(
            self._song,
            on_clip_change=self._on_clip_changed,
            on_structure_changed=self.refresh_state,
        )
        self._track_listener = TrackMatrixListener(
            self._song,
            on_track_change=self._on_track_changed,
            on_structure_changed=self.refresh_state,
        )
        self._scene_listener = SceneMatrixListener(
            self._song,
            on_scene_change=self._on_scene_changed,
            on_structure_changed=self.refresh_state,
        )
        self._transport_listener = TransportListener(
            self._song,
            on_change=self._on_transport_changed,
        )
        self._log("Remote Script loaded build=%s" % SCRIPT_BUILD)

    def _log(self, message):
        try:
            self._c_instance.log_message("SessionPad: %s" % message)
        except Exception:
            pass

    # ─── Live API Required Interface ──────────────────────────────────────────

    def disconnect(self):
        try:
            self._clip_listener.disconnect()
        except Exception:
            pass
        try:
            self._track_listener.disconnect()
        except Exception:
            pass
        try:
            self._scene_listener.disconnect()
        except Exception:
            pass
        try:
            self._transport_listener.disconnect()
        except Exception:
            pass
        try:
            self._bridge.stop()
        except Exception:
            pass

    def receive_midi(self, midi_bytes):
        pass

    def update_display(self):
        self._tick_count += 1

        self._bridge.tick()

        for text in self._bridge.poll_inbound():
            self._handle_inbound(text)

        if self._tick_count % FLUSH_TICK_INTERVAL == 0:
            self._flush_outbound()

        if self._bridge.is_connected and self._tick_count % PLAYPOS_TICK_INTERVAL == 0:
            self._poll_playing_positions()

        now = time.time()
        if self._bridge.is_connected and now - self._last_heartbeat >= (HEARTBEAT_INTERVAL_MS / 1000.0):
            self._last_heartbeat = now
            self._queue_send(
                encode_message(
                    T_HEARTBEAT,
                    payload={"ts": int(now * 1000)},
                    seq=self._next_seq(),
                )
            )

    def build_midi_map(self, midi_map_handle):
        pass

    def refresh_state(self):
        self._send_full_state()

    def can_lock_to_devices(self):
        return False

    def lock_to_device(self, device):
        pass

    def unlock_from_device(self, device):
        pass

    def set_appointed_device(self, device):
        pass

    def suggest_input_port(self):
        return ""

    def suggest_output_port(self):
        return ""

    # ─── Bridge callbacks ─────────────────────────────────────────────────────

    def _on_bridge_connected(self):
        self._log("bridge connected on localhost:%d" % 17345)
        self._send_bridge_session_info()
        self._send_full_state()

    def _on_bridge_disconnected(self):
        self._log("bridge disconnected")

    def _send_bridge_session_info(self):
        session_name = "Ableton Live"
        try:
            session_name = self._song.name or session_name
        except Exception:
            pass
        self._queue_send(
            encode_message(
                T_BRIDGE_SESSION,
                payload={"sessionName": session_name},
            )
        )

    # ─── Inbound message handling (Live thread) ───────────────────────────────

    def _handle_inbound(self, text):
        msg, err = decode_message(text)
        if err or msg is None:
            return

        msg_type = msg.get("t", "")
        payload = msg.get("payload") or {}
        msg_id = msg.get("id")

        if msg_type == T_GET_STATE:
            self._send_full_state(msg_id=msg_id)
        elif msg_type == T_HEARTBEAT:
            self._send(
                encode_message(
                    T_HEARTBEAT,
                    payload={"ts": int(time.time() * 1000)},
                    seq=self._next_seq(),
                    msg_id=msg_id,
                )
            )
        elif msg_type == T_CMD:
            self._handle_command(payload, msg_id)
        else:
            pass

    def _handle_command(self, payload, msg_id):
        cmd_name = payload.get("name", "")
        cmd_payload = payload.get("data") or {}
        self._log("cmd %s %s" % (cmd_name, cmd_payload))
        ok, error = self._command_handler.execute(cmd_name, cmd_payload)
        self._log("cmd %s ok=%s err=%s" % (cmd_name, ok, error))
        if msg_id:
            ack_payload = {"ok": bool(ok)}
            if error:
                ack_payload["error"] = str(error)
            self._send(
                encode_message(T_ACK, payload=ack_payload, msg_id=msg_id)
            )

    # ─── State change callbacks ───────────────────────────────────────────────

    def _on_clip_changed(self, track_index, scene_index, clip_slot):
        if not self._bridge.is_connected:
            return
        try:
            delta = encode_clip_delta(track_index, scene_index, clip_slot)
            self._queue_send(
                encode_message(T_DELTA_CLIP, payload=delta, seq=self._next_seq())
            )
        except Exception:
            pass

    def _on_track_changed(self, track_index, track):
        if not self._bridge.is_connected:
            return
        try:
            delta = encode_track_delta(track_index, track)
            self._queue_send(
                encode_message(T_DELTA_TRACK, payload=delta, seq=self._next_seq())
            )
        except Exception:
            pass

    def _on_scene_changed(self, scene_index, scene):
        if not self._bridge.is_connected:
            return
        try:
            delta = encode_scene_delta(scene_index, scene)
            self._queue_send(
                encode_message(T_DELTA_SCENE, payload=delta, seq=self._next_seq())
            )
        except Exception:
            pass

    def _on_transport_changed(self):
        if not self._bridge.is_connected:
            return
        try:
            delta = encode_transport_delta(self._song)
            self._queue_send(
                encode_message(T_DELTA_TRANSPORT, payload=delta, seq=self._next_seq())
            )
        except Exception:
            pass

    def _poll_playing_positions(self):
        """Poll playing clip loop positions and send a batched delta."""
        from .Protocol import _clip_loop_fraction

        playing = []
        try:
            tracks = list(self._song.tracks)
            for t_idx, track in enumerate(tracks):
                try:
                    slot_index = track.playing_slot_index
                except (AttributeError, TypeError):
                    continue
                if slot_index is None or slot_index < 0:
                    continue
                try:
                    clip_slot = track.clip_slots[slot_index]
                except (IndexError, AttributeError):
                    continue
                if not clip_slot.has_clip:
                    continue
                clip = clip_slot.clip
                try:
                    if clip.is_recording:
                        continue
                    if not clip.is_playing:
                        continue
                except (AttributeError, TypeError):
                    continue
                fraction, loop_len = _clip_loop_fraction(clip)
                if fraction is None:
                    continue
                playing.append(
                    {
                        "track": t_idx,
                        "scene": int(slot_index),
                        "p": fraction,
                        "lb": loop_len,
                    }
                )
        except Exception:
            return

        if not playing:
            return
        try:
            delta = encode_playpos_delta(playing)
            self._queue_send(
                encode_message(T_DELTA_PLAYPOS, payload=delta, seq=self._next_seq())
            )
            self._playpos_log_count += 1
            if self._playpos_log_count % 20 == 1:
                self._log("playpos sent count=%d clips=%s" % (self._playpos_log_count, delta["clips"]))
        except Exception as exc:
            self._log("playpos send failed: %s" % exc)

    # ─── Outbound queue ───────────────────────────────────────────────────────

    def _next_seq(self):
        self._seq += 1
        return self._seq

    def _queue_send(self, msg):
        self._pending_outbound.append(msg)

    def _flush_outbound(self):
        if not self._pending_outbound or not self._bridge.is_connected:
            return
        messages = self._pending_outbound
        self._pending_outbound = []
        for msg in messages:
            self._send(msg)

    def _send(self, msg):
        try:
            self._bridge.send(dumps(msg))
        except Exception:
            pass

    def _send_full_state(self, msg_id=None):
        try:
            self._snapshot_rev += 1
            state = build_full_state(self._song)
            state["rev"] = self._snapshot_rev
            msg = encode_message(
                T_STATE_FULL,
                payload=state,
                seq=self._next_seq(),
                msg_id=msg_id,
            )
            self._send(msg)
            self._log(
                "state sent rev=%d tracks=%d scenes=%d clips=%d"
                % (
                    self._snapshot_rev,
                    state.get("tracks", 0),
                    state.get("scenes", 0),
                    len(state.get("clips", [])),
                )
            )
        except Exception as exc:
            self._log("state send failed: %s" % exc)


def create_instance(c_instance):
    return SessionPad(c_instance)
