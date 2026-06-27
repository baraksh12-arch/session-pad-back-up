# Protocol.py
# SessionPad JSON wire protocol — shared contract with iOS Protocol.swift.
#
# Envelope: { "v": int, "t": str, "seq": int?, "id": str?, "payload": object? }

import json

PROTOCOL_VERSION = 1
SUPPORTED_VERSIONS = [1]

SERVICE_TYPE = "_sessionpad._tcp.local."
HEARTBEAT_INTERVAL_MS = 2000

# Capability strings
CAP_SESSION = "session"
CAP_TRANSPORT = "transport"
CAP_CLIPS = "clips"
CAP_COMMANDS = "commands"
CAP_METERS = "meters"
DEFAULT_CAPS = [CAP_SESSION, CAP_TRANSPORT, CAP_CLIPS, CAP_COMMANDS]

# Topic strings (subscription model)
TOPIC_SESSION = "session"
TOPIC_TRANSPORT = "transport"
TOPIC_CLIPS = "clips"
TOPIC_METERS = "meters"
DEFAULT_TOPICS = [TOPIC_SESSION, TOPIC_TRANSPORT, TOPIC_CLIPS]

# Message type strings
T_HELLO = "hello"
T_WELCOME = "welcome"
T_ERROR = "error"
T_SUBSCRIBE = "subscribe"
T_GET_STATE = "getState"
T_STATE_FULL = "state.full"
T_DELTA_CLIP = "delta.clip"
T_DELTA_TRACK = "delta.track"
T_DELTA_SCENE = "delta.scene"
T_DELTA_TRANSPORT = "delta.transport"
T_DELTA_PLAYPOS = "delta.playpos"
T_HEARTBEAT = "heartbeat"
T_ACK = "ack"
T_CMD = "cmd"

# Clip states — must match iOS ClipState
CLIP_EMPTY = "empty"
CLIP_STOPPED = "stopped"
CLIP_PLAYING = "playing"
CLIP_RECORDING = "recording"
CLIP_QUEUED = "queued"
CLIP_REC_QUEUED = "recQueued"


def encode_message(msg_type, payload=None, seq=None, msg_id=None, version=PROTOCOL_VERSION):
    """Build a JSON-serializable message dict."""
    msg = {"v": version, "t": msg_type}
    if seq is not None:
        msg["seq"] = int(seq)
    if msg_id is not None:
        msg["id"] = str(msg_id)
    if payload is not None:
        msg["payload"] = payload
    return msg


def decode_message(text):
    """Parse a JSON text frame. Returns (msg_dict, error_string)."""
    try:
        data = json.loads(text)
    except (ValueError, TypeError):
        return None, "invalid JSON"
    if not isinstance(data, dict):
        return None, "message must be an object"
    if "v" not in data or "t" not in data:
        return None, "missing v or t"
    return data, None


def dumps(msg):
    return json.dumps(msg, separators=(",", ":"))


def _color_index(obj):
    """Live 12 may return color_index=None when no custom color is set."""
    c = getattr(obj, "color_index", None)
    try:
        return int(c) if c is not None else 0
    except (TypeError, ValueError):
        return 0


def get_clip_state(clip_slot):
    """Map a Live clip slot to a protocol clip-state string."""
    if not clip_slot.has_clip:
        return CLIP_EMPTY
    clip = clip_slot.clip
    if clip.is_recording:
        return CLIP_RECORDING
    if clip.is_playing:
        return CLIP_PLAYING
    if clip.is_triggered:
        if clip.will_record_on_start:
            return CLIP_REC_QUEUED
        return CLIP_QUEUED
    return CLIP_STOPPED


def encode_clip_delta(track_index, scene_index, clip_slot):
    if clip_slot.has_clip:
        color = _color_index(clip_slot.clip)
        name = clip_slot.clip.name or ""
    else:
        color = 0
        name = ""
    return {
        "track": int(track_index),
        "scene": int(scene_index),
        "state": get_clip_state(clip_slot),
        "color": color,
        "name": name,
    }


def encode_track_delta(track_index, track):
    return {
        "track": int(track_index),
        "name": track.name or "",
        "color": _color_index(track),
        "muted": bool(track.mute),
        "solo": bool(track.solo),
        "armed": bool(hasattr(track, "arm") and track.arm),
    }


def encode_scene_delta(scene_index, scene):
    return {
        "scene": int(scene_index),
        "name": scene.name or "",
        "color": _color_index(scene),
    }


def encode_transport_delta(song):
    return {
        "playing": bool(song.is_playing),
        "recording": bool(song.record_mode),
        "metronome": bool(song.metronome),
        "overdub": bool(song.overdub),
        "bpm": round(float(song.tempo), 1),
    }


def _clip_loop_fraction(clip):
    """Normalized loop progress [0, 1) and loop length in beats."""
    try:
        loop_start = float(clip.loop_start)
        loop_end = float(clip.loop_end)
        position = float(clip.playing_position)
    except (TypeError, ValueError, AttributeError):
        return None, 0.0
    loop_len = loop_end - loop_start
    if loop_len <= 0.0:
        return None, 0.0
    fraction = (position - loop_start) / loop_len
    if fraction < 0.0:
        fraction = 0.0
    elif fraction >= 1.0:
        fraction = fraction % 1.0
    return fraction, loop_len


def encode_playpos_delta(playing):
    """Build a delta.playpos payload from a list of playing clip entries."""
    clips = []
    for entry in playing:
        clips.append(
            {
                "track": int(entry["track"]),
                "scene": int(entry["scene"]),
                "p": round(float(entry["p"]), 4),
                "lb": round(float(entry["lb"]), 4),
            }
        )
    return {"clips": clips}


def build_full_state(song):
    """Build a state.full payload from the current Live song."""
    tracks = list(song.tracks)
    scenes = list(song.scenes)
    clip_rows = []
    for s_idx, _scene in enumerate(scenes):
        for t_idx, track in enumerate(tracks):
            try:
                clip_rows.append(encode_clip_delta(t_idx, s_idx, track.clip_slots[s_idx]))
            except (IndexError, AttributeError):
                pass
    track_headers = []
    for i, track in enumerate(tracks):
        try:
            track_headers.append(encode_track_delta(i, track))
        except Exception:
            pass

    scenes_meta = []
    for i, scene in enumerate(scenes):
        try:
            scenes_meta.append(encode_scene_delta(i, scene))
        except Exception:
            pass

    return {
        "tracks": len(tracks),
        "scenes": len(scenes),
        "trackHeaders": track_headers,
        "scenes_meta": scenes_meta,
        "clips": clip_rows,
        "transport": encode_transport_delta(song),
    }
