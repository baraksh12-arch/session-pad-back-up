# protocol.py
# SessionPad JSON wire protocol — shared contract with iOS Protocol.swift.

from __future__ import annotations

import json
import time
from typing import Any, Optional

PROTOCOL_VERSION = 1
SUPPORTED_VERSIONS = [1]
SERVICE_TYPE = "_sessionpad._tcp"
HEARTBEAT_INTERVAL_MS = 2000
DEFAULT_CAPABILITIES = ["session", "transport", "clips", "commands"]
DEFAULT_TOPICS = ["session", "transport", "clips"]

LIVE_LINK_PORT = 17345
IOS_WEBSOCKET_PORT = 17346

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
T_BRIDGE_SESSION = "bridge.session"


def encode_message(
    msg_type: str,
    payload: Optional[dict[str, Any]] = None,
    seq: Optional[int] = None,
    msg_id: Optional[str] = None,
    version: int = PROTOCOL_VERSION,
) -> dict[str, Any]:
    msg: dict[str, Any] = {"v": version, "t": msg_type}
    if seq is not None:
        msg["seq"] = int(seq)
    if msg_id is not None:
        msg["id"] = str(msg_id)
    if payload is not None:
        msg["payload"] = payload
    return msg


def dumps(msg: dict[str, Any]) -> str:
    return json.dumps(msg, separators=(",", ":"))


def loads(text: str) -> Optional[dict[str, Any]]:
    try:
        data = json.loads(text)
    except (ValueError, TypeError):
        return None
    if not isinstance(data, dict):
        return None
    if "v" not in data or "t" not in data:
        return None
    return data


def welcome(
    chosen_version: int,
    snapshot_rev: int,
    session_name: str,
    msg_id: Optional[str] = None,
) -> str:
    payload = {
        "chosenVersion": chosen_version,
        "liveVersion": "11/12",
        "capabilities": DEFAULT_CAPABILITIES,
        "heartbeatIntervalMs": HEARTBEAT_INTERVAL_MS,
        "snapshotRev": snapshot_rev,
        "sessionName": session_name,
    }
    return dumps(encode_message(T_WELCOME, payload=payload, msg_id=msg_id))


def ack(ok: bool, msg_id: Optional[str] = None, error: Optional[str] = None) -> str:
    payload: dict[str, Any] = {"ok": ok}
    if error is not None:
        payload["error"] = error
    return dumps(encode_message(T_ACK, payload=payload, msg_id=msg_id))


def error_message(message: str, msg_id: Optional[str] = None) -> str:
    return dumps(encode_message(T_ERROR, payload={"message": message}, msg_id=msg_id))


def heartbeat(msg_id: Optional[str] = None) -> str:
    payload = {"ts": int(time.time() * 1000)}
    return dumps(encode_message(T_HEARTBEAT, payload=payload, msg_id=msg_id))


def get_state(msg_id: Optional[str] = None) -> str:
    return dumps(encode_message(T_GET_STATE, msg_id=msg_id))
