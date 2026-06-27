# router.py
# Relays messages between Ableton Live (TCP) and iOS clients (WebSocket).

from __future__ import annotations

import asyncio
import logging
import uuid
from enum import Enum
from typing import Callable, Optional

from . import protocol as proto
from .discovery import BridgeDiscovery
from .ios_ws_server import IOSWebSocketServer
from .live_link_server import LiveLinkServer

log = logging.getLogger(__name__)


class BridgeStatus(str, Enum):
    STARTING = "starting"
    WAITING_FOR_LIVE = "waitingForLive"
    LIVE_CONNECTED = "liveConnected"
    LIVE_AND_IOS = "liveAndIOS"


StatusCallback = Callable[[BridgeStatus, bool, int, str], None]


class BridgeRouter:
    """Central relay between Live TCP and iOS WebSocket clients."""

    def __init__(
        self,
        on_status_changed: Optional[StatusCallback] = None,
    ) -> None:
        self._on_status_changed = on_status_changed
        self.status = BridgeStatus.STARTING
        self.session_name = "Ableton Live"
        self.ios_client_count = 0
        self.live_connected = False
        self.start_error: Optional[str] = None

        self._is_running = False
        self._snapshot_rev = 0
        self._cached_full_state_text: Optional[str] = None
        self._subscribed_clients: set[uuid.UUID] = set()
        self._pending_cmd_clients: dict[str, uuid.UUID] = {}
        self._heartbeat_task: Optional[asyncio.Task[None]] = None

        self._live_link = LiveLinkServer(
            on_connected=self._live_connected_cb,
            on_disconnected=self._live_disconnected_cb,
            on_receive=self._handle_live_message,
        )
        self._ios_server = IOSWebSocketServer(
            on_connected=self._ios_connected_cb,
            on_disconnected=self._ios_disconnected_cb,
            on_receive=self._handle_ios_message,
        )
        self._discovery = BridgeDiscovery()

        self._ws_port = proto.IOS_WEBSOCKET_PORT
        self._live_port = proto.LIVE_LINK_PORT
        self._mdns_enabled = True

    async def start(
        self,
        ws_port: int = proto.IOS_WEBSOCKET_PORT,
        live_port: int = proto.LIVE_LINK_PORT,
        session_name: str = "Ableton Live",
        mdns: bool = True,
    ) -> None:
        if self._is_running:
            return

        self._ws_port = ws_port
        self._live_port = live_port
        self.session_name = session_name
        self._mdns_enabled = mdns

        try:
            await self._live_link.start(port=live_port)
            await self._ios_server.start(port=ws_port)
            if mdns:
                await self._discovery.start(port=ws_port, session_name=session_name)
            self._is_running = True
            self.start_error = None
            self.status = BridgeStatus.WAITING_FOR_LIVE
            self._start_heartbeat_task()
            log.info(
                "Bridge started: live link :%d, iOS WS :%d",
                live_port,
                ws_port,
            )
            self._notify_status()
        except Exception as exc:
            self.start_error = str(exc)
            log.error("Bridge start failed: %s", exc)
            await self.stop()

    async def stop(self) -> None:
        if self._heartbeat_task is not None:
            self._heartbeat_task.cancel()
            try:
                await self._heartbeat_task
            except asyncio.CancelledError:
                pass
            self._heartbeat_task = None

        await self._discovery.stop()
        await self._ios_server.stop()
        await self._live_link.stop()

        self._subscribed_clients.clear()
        self._pending_cmd_clients.clear()
        self._cached_full_state_text = None
        self._snapshot_rev = 0
        self.live_connected = False
        self.ios_client_count = 0
        self._is_running = False
        self.status = BridgeStatus.STARTING
        self._notify_status()

    # MARK: - iOS message handling

    async def _handle_ios_message(self, client_id: uuid.UUID, text: str) -> None:
        message = proto.loads(text)
        if message is None:
            return

        msg_type = message.get("t")
        msg_id = message.get("id")

        if msg_type == proto.T_HELLO:
            await self._handle_hello(message, client_id)
        elif msg_type == proto.T_SUBSCRIBE:
            self._subscribed_clients.add(client_id)
            await self._send_ack(ok=True, client_id=client_id, msg_id=msg_id)
        elif msg_type == proto.T_GET_STATE:
            await self._request_full_state_from_live(msg_id=msg_id)
        elif msg_type == proto.T_HEARTBEAT:
            await self._respond_heartbeat(client_id, msg_id)
        elif msg_type == proto.T_CMD:
            if msg_id is not None:
                self._pending_cmd_clients[str(msg_id)] = client_id
            await self._forward_to_live(text)
        else:
            await self._send_error(
                f"unknown message type: {msg_type}", client_id, msg_id
            )

    async def _handle_hello(self, message: dict, client_id: uuid.UUID) -> None:
        payload = message.get("payload") or {}
        protocol_versions = payload.get("protocolVersions") or []
        msg_id = message.get("id")

        chosen = next(
            (v for v in proto.SUPPORTED_VERSIONS if v in protocol_versions),
            proto.PROTOCOL_VERSION,
        )

        self._subscribed_clients.add(client_id)

        welcome_text = proto.welcome(
            chosen_version=chosen,
            snapshot_rev=self._snapshot_rev,
            session_name=self.session_name,
            msg_id=msg_id,
        )
        await self._ios_server.send(client_id, welcome_text)

        if self._cached_full_state_text:
            await self._ios_server.send(client_id, self._cached_full_state_text)
        elif self.live_connected:
            await self._request_full_state_from_live(msg_id=None)

    async def _request_full_state_from_live(self, msg_id: Optional[str]) -> None:
        if not self.live_connected:
            return
        await self._live_link.send(proto.get_state(msg_id=msg_id))

    async def _respond_heartbeat(
        self, client_id: uuid.UUID, msg_id: Optional[str]
    ) -> None:
        await self._ios_server.send(client_id, proto.heartbeat(msg_id=msg_id))

    async def _send_ack(
        self, ok: bool, client_id: uuid.UUID, msg_id: Optional[str]
    ) -> None:
        if msg_id is None:
            return
        await self._ios_server.send(client_id, proto.ack(ok=ok, msg_id=msg_id))

    async def _send_error(
        self, message: str, client_id: uuid.UUID, msg_id: Optional[str]
    ) -> None:
        await self._ios_server.send(
            client_id, proto.error_message(message, msg_id=msg_id)
        )

    async def _forward_to_live(self, text: str) -> None:
        if not self.live_connected:
            message = proto.loads(text)
            if message and message.get("id"):
                msg_id = str(message["id"])
                for client_id in self._subscribed_clients:
                    await self._ios_server.send(
                        client_id,
                        proto.ack(
                            ok=False,
                            error="Ableton Live not connected",
                            msg_id=msg_id,
                        ),
                    )
            return
        await self._live_link.send(text)

    # MARK: - Live message handling

    async def _handle_live_message(self, text: str) -> None:
        message = proto.loads(text)
        if message is None:
            return

        msg_type = message.get("t")

        if msg_type == proto.T_STATE_FULL:
            payload = message.get("payload") or {}
            rev = payload.get("rev")
            if rev is not None:
                self._snapshot_rev = int(rev)
            self._cached_full_state_text = text
            await self._ios_server.broadcast(text)
            self._update_status()

        elif msg_type == proto.T_BRIDGE_SESSION:
            payload = message.get("payload") or {}
            name = payload.get("sessionName")
            if name:
                self.session_name = str(name)

        elif msg_type in (
            proto.T_DELTA_CLIP,
            proto.T_DELTA_TRACK,
            proto.T_DELTA_SCENE,
            proto.T_DELTA_TRANSPORT,
            proto.T_DELTA_PLAYPOS,
            proto.T_ERROR,
            proto.T_HEARTBEAT,
        ):
            await self._ios_server.broadcast(text)

        elif msg_type == proto.T_ACK:
            msg_id = message.get("id")
            if msg_id is not None:
                client_id = self._pending_cmd_clients.pop(str(msg_id), None)
                if client_id is not None:
                    await self._ios_server.send(client_id, text)
                else:
                    await self._ios_server.broadcast(text)
            else:
                await self._ios_server.broadcast(text)

    def _update_status(self) -> None:
        if self.live_connected and self.ios_client_count > 0:
            self.status = BridgeStatus.LIVE_AND_IOS
        elif self.live_connected:
            self.status = BridgeStatus.LIVE_CONNECTED
        else:
            self.status = BridgeStatus.WAITING_FOR_LIVE
        self._notify_status()

    def _notify_status(self) -> None:
        if self._on_status_changed:
            self._on_status_changed(
                self.status,
                self.live_connected,
                self.ios_client_count,
                self.session_name,
            )

    def _start_heartbeat_task(self) -> None:
        if self._heartbeat_task is not None:
            self._heartbeat_task.cancel()

        async def heartbeat_loop() -> None:
            interval = proto.HEARTBEAT_INTERVAL_MS / 1000.0
            while True:
                await asyncio.sleep(interval)
                if not self.live_connected and self.ios_client_count == 0:
                    continue
                try:
                    text = proto.heartbeat()
                    if self.ios_client_count > 0:
                        await self._ios_server.broadcast(text)
                except Exception:
                    pass

        self._heartbeat_task = asyncio.create_task(heartbeat_loop())

    # MARK: - Connection callbacks

    async def _live_connected_cb(self) -> None:
        self.live_connected = True
        self._cached_full_state_text = None
        self.status = BridgeStatus.LIVE_CONNECTED
        self._notify_status()
        await self._request_full_state_from_live(msg_id=None)

    async def _live_disconnected_cb(self) -> None:
        self.live_connected = False
        self._cached_full_state_text = None
        self._update_status()

    async def _ios_connected_cb(self, client_id: uuid.UUID) -> None:
        _ = client_id
        self.ios_client_count = self._ios_server.connected_client_count
        self._update_status()

    async def _ios_disconnected_cb(self, client_id: uuid.UUID) -> None:
        self._subscribed_clients.discard(client_id)
        self.ios_client_count = self._ios_server.connected_client_count
        self._update_status()
