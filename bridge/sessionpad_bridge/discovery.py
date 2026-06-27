# discovery.py
# mDNS/Bonjour advertisement for iOS discovery.

from __future__ import annotations

import logging
import socket
from typing import Optional

from zeroconf import IPVersion, ServiceInfo
from zeroconf.asyncio import AsyncZeroconf

from .protocol import (
    DEFAULT_CAPABILITIES,
    IOS_WEBSOCKET_PORT,
    PROTOCOL_VERSION,
    SERVICE_TYPE,
)

log = logging.getLogger(__name__)


def _local_ip() -> str:
    """Best-effort LAN IP for mDNS advertisement."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("8.8.8.8", 80))
            return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def _hostname() -> str:
    try:
        return socket.gethostname().split(".")[0]
    except OSError:
        return "Bridge"


class BridgeDiscovery:
    """Advertises _sessionpad._tcp via zeroconf."""

    def __init__(self) -> None:
        self._zeroconf: Optional[AsyncZeroconf] = None
        self._service_info: Optional[ServiceInfo] = None

    async def start(
        self,
        port: int = IOS_WEBSOCKET_PORT,
        session_name: str = "Ableton Live",
        hostname: Optional[str] = None,
    ) -> None:
        if self._zeroconf is not None:
            return

        host = hostname or _hostname()
        instance_name = f"SessionPad ({host})"
        ip = _local_ip()

        properties = {
            "v": str(PROTOCOL_VERSION),
            "name": session_name[:63],
            "caps": ",".join(DEFAULT_CAPABILITIES),
        }

        self._service_info = ServiceInfo(
            type_=f"{SERVICE_TYPE}.local.",
            name=f"{instance_name}.{SERVICE_TYPE}.local.",
            addresses=[socket.inet_aton(ip)],
            port=port,
            properties=properties,
        )

        self._zeroconf = AsyncZeroconf(ip_version=IPVersion.V4Only)
        await self._zeroconf.async_register_service(self._service_info)
        log.info(
            "mDNS advertising %s on %s:%d (TXT v=%s name=%s)",
            instance_name,
            ip,
            port,
            properties["v"],
            properties["name"],
        )

    async def stop(self) -> None:
        if self._zeroconf is not None and self._service_info is not None:
            await self._zeroconf.async_unregister_service(self._service_info)
            await self._zeroconf.async_close()
        self._zeroconf = None
        self._service_info = None

    def update_session_name(self, name: str) -> None:
        """Session name also flows via welcome payload; TXT is set at start."""
        _ = name
