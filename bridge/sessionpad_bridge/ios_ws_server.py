# ios_ws_server.py
# WebSocket server for iOS clients.

from __future__ import annotations

import asyncio
import logging
import uuid
from typing import Awaitable, Callable, Optional

import websockets
from websockets.server import WebSocketServerProtocol

from .protocol import IOS_WEBSOCKET_PORT

log = logging.getLogger(__name__)

OnClientConnected = Callable[[uuid.UUID], Awaitable[None]]
OnClientDisconnected = Callable[[uuid.UUID], Awaitable[None]]
OnClientReceive = Callable[[uuid.UUID, str], Awaitable[None]]


class IOSWebSocketServer:
    """WebSocket server accepting multiple iOS clients."""

    def __init__(
        self,
        on_connected: Optional[OnClientConnected] = None,
        on_disconnected: Optional[OnClientDisconnected] = None,
        on_receive: Optional[OnClientReceive] = None,
    ) -> None:
        self._on_connected = on_connected
        self._on_disconnected = on_disconnected
        self._on_receive = on_receive
        self._connections: dict[uuid.UUID, WebSocketServerProtocol] = {}
        self._server: Optional[websockets.WebSocketServer] = None
        self._advertised_port = IOS_WEBSOCKET_PORT

    @property
    def connected_client_count(self) -> int:
        return len(self._connections)

    @property
    def advertised_port(self) -> int:
        return self._advertised_port

    async def start(self, port: int = IOS_WEBSOCKET_PORT, host: str = "0.0.0.0") -> None:
        if self._server is not None:
            return
        self._advertised_port = port
        self._server = await websockets.serve(
            self._handle_client,
            host,
            port,
            ping_interval=20,
            ping_timeout=20,
        )
        log.info("iOS WebSocket server ready on %s:%d", host, port)

    async def stop(self) -> None:
        for ws in list(self._connections.values()):
            await ws.close()
        self._connections.clear()
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
            self._server = None

    async def send(self, client_id: uuid.UUID, text: str) -> None:
        ws = self._connections.get(client_id)
        if ws is None:
            return
        try:
            await ws.send(text)
        except websockets.ConnectionClosed as exc:
            log.error("WebSocket send failed for %s: %s", client_id, exc)
            await self._remove_client(client_id)

    async def broadcast(self, text: str) -> None:
        for client_id in list(self._connections.keys()):
            await self.send(client_id, text)

    async def _handle_client(self, ws: WebSocketServerProtocol) -> None:
        client_id = uuid.uuid4()
        self._connections[client_id] = ws
        log.info("iOS client connected: %s", client_id)

        if self._on_connected:
            await self._on_connected(client_id)

        try:
            async for message in ws:
                if isinstance(message, str) and self._on_receive:
                    await self._on_receive(client_id, message)
        except websockets.ConnectionClosed:
            pass
        finally:
            await self._remove_client(client_id)

    async def _remove_client(self, client_id: uuid.UUID) -> None:
        ws = self._connections.pop(client_id, None)
        if ws is not None:
            try:
                await ws.close()
            except websockets.ConnectionClosed:
                pass
            if self._on_disconnected:
                await self._on_disconnected(client_id)
