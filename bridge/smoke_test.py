#!/usr/bin/env python3
"""End-to-end smoke test for SessionPad Python bridge."""

from __future__ import annotations

import asyncio
import json
import uuid

import websockets

from sessionpad_bridge.protocol import (
    T_ACK,
    T_GET_STATE,
    T_HEARTBEAT,
    T_STATE_FULL,
    T_WELCOME,
    dumps,
    encode_message,
)
from sessionpad_bridge.router import BridgeRouter

LIVE_PORT = 27345
WS_PORT = 27346


async def fake_live_client() -> None:
    await asyncio.sleep(0.3)
    reader, writer = await asyncio.open_connection("127.0.0.1", LIVE_PORT)

    # Wait for getState from bridge after connect
    line = await reader.readline()
    msg = json.loads(line.decode())
    assert msg["t"] == T_GET_STATE, f"expected getState, got {msg['t']}"

    state = encode_message(
        T_STATE_FULL,
        payload={
            "rev": 1,
            "tracks": 1,
            "scenes": 1,
            "trackHeaders": [],
            "scenes_meta": [],
            "clips": [],
            "transport": {
                "playing": False,
                "recording": False,
                "metronome": False,
                "overdub": False,
                "bpm": 120.0,
            },
        },
    )
    writer.write((dumps(state) + "\n").encode())
    await writer.drain()
    await asyncio.sleep(0.2)
    writer.close()
    await writer.wait_closed()


async def ios_client_test() -> None:
    uri = f"ws://127.0.0.1:{WS_PORT}/"
    async with websockets.connect(uri) as ws:
        hello = dumps(
            encode_message(
                "hello",
                payload={
                    "protocolVersions": [1],
                    "appVersion": "test",
                    "capabilities": ["session", "transport", "clips", "commands"],
                },
                msg_id="hello-1",
            )
        )
        await ws.send(hello)

        welcome = json.loads(await ws.recv())
        assert welcome["t"] == T_WELCOME, welcome
        assert welcome["payload"]["chosenVersion"] == 1

        state = json.loads(await ws.recv())
        assert state["t"] == T_STATE_FULL, state
        assert state["payload"]["rev"] == 1

        sub = dumps(
            encode_message(
                "subscribe",
                payload={"topics": ["session", "transport", "clips"]},
                msg_id="sub-1",
            )
        )
        await ws.send(sub)
        ack = json.loads(await ws.recv())
        assert ack["t"] == T_ACK and ack["payload"]["ok"] is True, ack

        await ws.send(dumps(encode_message(T_HEARTBEAT, msg_id="hb-1")))
        hb = json.loads(await ws.recv())
        assert hb["t"] == T_HEARTBEAT, hb

    print("smoke test passed")


async def main() -> None:
    router = BridgeRouter()
    await router.start(ws_port=WS_PORT, live_port=LIVE_PORT, mdns=False)

    live_task = asyncio.create_task(fake_live_client())
    try:
        await ios_client_test()
    finally:
        live_task.cancel()
        try:
            await live_task
        except asyncio.CancelledError:
            pass
        await router.stop()


if __name__ == "__main__":
    asyncio.run(main())
