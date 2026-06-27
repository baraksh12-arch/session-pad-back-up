# live_link_server.py
# Localhost TCP server for the Ableton Remote Script (newline-framed JSON).

from __future__ import annotations

import asyncio
import logging
from typing import Awaitable, Callable, Optional

from .protocol import LIVE_LINK_PORT

log = logging.getLogger(__name__)

OnConnected = Callable[[], Awaitable[None]]
OnDisconnected = Callable[[], Awaitable[None]]
OnReceive = Callable[[str], Awaitable[None]]


class LiveLinkServer:
    """Non-blocking TCP server accepting a single Live connection (newest wins)."""

    def __init__(
        self,
        on_connected: Optional[OnConnected] = None,
        on_disconnected: Optional[OnDisconnected] = None,
        on_receive: Optional[OnReceive] = None,
    ) -> None:
        self._on_connected = on_connected
        self._on_disconnected = on_disconnected
        self._on_receive = on_receive
        self._server: Optional[asyncio.AbstractServer] = None
        self._writer: Optional[asyncio.StreamWriter] = None
        self._reader: Optional[asyncio.StreamReader] = None
        self._recv_buffer = ""
        self._connected = False
        self._read_task: Optional[asyncio.Task[None]] = None

    @property
    def is_connected(self) -> bool:
        return self._connected

    async def start(self, port: int = LIVE_LINK_PORT, host: str = "127.0.0.1") -> None:
        if self._server is not None:
            return
        self._server = await asyncio.start_server(self._handle_client, host, port)
        log.info("Live link listening on %s:%d", host, port)

    async def stop(self) -> None:
        await self._close_connection(notify=False)
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
            self._server = None

    async def send(self, text: str) -> None:
        if not self._connected or self._writer is None:
            return
        try:
            self._writer.write((text + "\n").encode("utf-8"))
            await self._writer.drain()
        except (ConnectionError, OSError) as exc:
            log.error("Live link send failed: %s", exc)
            await self._close_connection()

    async def _handle_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        peer = writer.get_extra_info("peername")
        log.info("Live link client connecting from %s", peer)

        if self._writer is not None:
            log.info("Replacing existing Live connection")
            await self._close_connection(notify=False)

        self._reader = reader
        self._writer = writer
        self._recv_buffer = ""
        self._connected = True

        if self._on_connected:
            await self._on_connected()

        self._read_task = asyncio.create_task(self._read_loop())

    async def _read_loop(self) -> None:
        assert self._reader is not None
        try:
            while self._connected:
                data = await self._reader.read(65536)
                if not data:
                    break
                self._recv_buffer += data.decode("utf-8", errors="replace")
                await self._drain_lines()
        except (ConnectionError, OSError, asyncio.CancelledError):
            pass
        finally:
            await self._close_connection()

    async def _drain_lines(self) -> None:
        while True:
            idx = self._recv_buffer.find("\n")
            if idx < 0:
                break
            line = self._recv_buffer[:idx].strip()
            self._recv_buffer = self._recv_buffer[idx + 1 :]
            if line and self._on_receive:
                await self._on_receive(line)

    async def _close_connection(self, notify: bool = True) -> None:
        was_connected = self._connected
        if self._read_task is not None:
            self._read_task.cancel()
            try:
                await self._read_task
            except asyncio.CancelledError:
                pass
            self._read_task = None

        if self._writer is not None:
            try:
                self._writer.close()
                await self._writer.wait_closed()
            except (ConnectionError, OSError):
                pass

        self._reader = None
        self._writer = None
        self._recv_buffer = ""
        self._connected = False

        if was_connected and notify and self._on_disconnected:
            await self._on_disconnected()
