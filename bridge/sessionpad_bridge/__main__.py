# __main__.py
# Entry point for SessionPad Bridge (cross-platform).

from __future__ import annotations

import argparse
import asyncio
import logging
import signal
import sys
import threading
from typing import Optional

from . import __version__
from .protocol import IOS_WEBSOCKET_PORT, LIVE_LINK_PORT
from .router import BridgeRouter, BridgeStatus, StatusCallback

log = logging.getLogger(__name__)


def _status_label(status: BridgeStatus) -> str:
    labels = {
        BridgeStatus.STARTING: "Starting…",
        BridgeStatus.WAITING_FOR_LIVE: "Waiting for Ableton Live",
        BridgeStatus.LIVE_CONNECTED: "Live connected — waiting for iOS",
        BridgeStatus.LIVE_AND_IOS: "Live + iOS connected",
    }
    return labels.get(status, str(status))


def _status_color(status: BridgeStatus) -> str:
    colors = {
        BridgeStatus.STARTING: "\033[90m",  # gray
        BridgeStatus.WAITING_FOR_LIVE: "\033[31m",  # red
        BridgeStatus.LIVE_CONNECTED: "\033[33m",  # yellow
        BridgeStatus.LIVE_AND_IOS: "\033[32m",  # green
    }
    return colors.get(status, "")


def _print_status(
    status: BridgeStatus,
    live_connected: bool,
    ios_count: int,
    session_name: str,
    ws_port: int,
) -> None:
    reset = "\033[0m"
    color = _status_color(status)
    print(
        f"\r{color}●{reset} {_status_label(status)} | "
        f"Live: {'Connected' if live_connected else 'Waiting…'} | "
        f"iOS clients: {ios_count} | "
        f"Session: {session_name} | "
        f"WS port: {ws_port}",
        end="",
        flush=True,
    )


def _make_tray_runner(
    router: BridgeRouter,
    loop: asyncio.AbstractEventLoop,
    existing_callback: Optional[StatusCallback],
) -> Optional[threading.Thread]:
    """Optional system-tray icon (requires pystray + Pillow). Returns tray thread."""
    try:
        import pystray
        from PIL import Image, ImageDraw
    except ImportError:
        log.warning("--tray requested but pystray/Pillow not installed; skipping tray")
        return None

    def make_icon(color: str) -> Image.Image:
        img = Image.new("RGB", (64, 64), color=(30, 30, 30))
        draw = ImageDraw.Draw(img)
        colors = {
            "gray": (128, 128, 128),
            "red": (220, 60, 60),
            "yellow": (220, 200, 60),
            "green": (60, 200, 80),
        }
        draw.ellipse((8, 8, 56, 56), fill=colors.get(color, (128, 128, 128)))
        return img

    status_colors = {
        BridgeStatus.STARTING: "gray",
        BridgeStatus.WAITING_FOR_LIVE: "red",
        BridgeStatus.LIVE_CONNECTED: "yellow",
        BridgeStatus.LIVE_AND_IOS: "green",
    }

    current_color = "gray"
    icon_holder: dict[str, Optional[pystray.Icon]] = {"icon": None}

    def on_tray_status(
        status: BridgeStatus,
        live_connected: bool,
        ios_count: int,
        session_name: str,
    ) -> None:
        nonlocal current_color
        current_color = status_colors.get(status, "gray")
        icon = icon_holder["icon"]
        if icon is not None:
            icon.icon = make_icon(current_color)
            icon.title = (
                f"SessionPad Bridge — {_status_label(status)}\n"
                f"Live: {'Connected' if live_connected else 'Waiting…'}\n"
                f"iOS clients: {ios_count}"
            )

    def combined_status(
        status: BridgeStatus,
        live_connected: bool,
        ios_count: int,
        session_name: str,
    ) -> None:
        if existing_callback:
            existing_callback(status, live_connected, ios_count, session_name)
        on_tray_status(status, live_connected, ios_count, session_name)

    router._on_status_changed = combined_status  # noqa: SLF001

    def on_quit(icon: pystray.Icon, _item: object) -> None:
        icon.stop()
        loop.call_soon_threadsafe(lambda: asyncio.create_task(router.stop()))

    menu = pystray.Menu(
        pystray.MenuItem("Quit", on_quit),
    )

    icon = pystray.Icon(
        "SessionPad Bridge",
        make_icon(current_color),
        "SessionPad Bridge",
        menu,
    )
    icon_holder["icon"] = icon
    tray_thread = threading.Thread(target=icon.run, daemon=True)
    return tray_thread


async def _async_main(args: argparse.Namespace) -> int:
    router = BridgeRouter()

    ws_port = args.port
    live_port = args.live_port
    session_name = args.name

    def on_status(
        status: BridgeStatus,
        live_connected: bool,
        ios_count: int,
        session_name: str,
    ) -> None:
        if not args.tray:
            _print_status(status, live_connected, ios_count, session_name, ws_port)

    router._on_status_changed = on_status  # noqa: SLF001

    await router.start(
        ws_port=ws_port,
        live_port=live_port,
        session_name=session_name,
        mdns=not args.no_mdns,
    )

    if router.start_error:
        print(f"Bridge start failed: {router.start_error}", file=sys.stderr)
        return 1

    if not args.tray:
        print()
        print("SessionPad Bridge running.")
        print(f"  Live link (TCP):  localhost:{live_port}")
        print(f"  iOS WebSocket:    0.0.0.0:{ws_port}")
        if not args.no_mdns:
            print("  mDNS:             _sessionpad._tcp")
        print()
        print("Keep this running while using SessionPad.")
        print("Press Ctrl+C to quit.")
        print()

    stop_event = asyncio.Event()

    def request_stop() -> None:
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, request_stop)
        except NotImplementedError:
            # Windows may not support all signals in asyncio
            signal.signal(sig, lambda _s, _f: request_stop())

    if args.tray:
        tray_thread = _make_tray_runner(router, loop, on_status)
        if tray_thread is not None:
            tray_thread.start()

    await stop_event.wait()
    print("\nShutting down…")
    await router.stop()
    return 0


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="SessionPad Bridge — relay between Ableton Live and iOS clients.",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=IOS_WEBSOCKET_PORT,
        help=f"iOS WebSocket port (default: {IOS_WEBSOCKET_PORT})",
    )
    parser.add_argument(
        "--live-port",
        type=int,
        default=LIVE_LINK_PORT,
        help=f"Ableton Live TCP port (default: {LIVE_LINK_PORT})",
    )
    parser.add_argument(
        "--name",
        default="Ableton Live",
        help="Session name advertised to iOS clients",
    )
    parser.add_argument(
        "--no-mdns",
        action="store_true",
        help="Disable mDNS/Bonjour advertisement",
    )
    parser.add_argument(
        "--tray",
        action="store_true",
        help="Show system-tray icon (requires pystray and Pillow)",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Enable debug logging",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"SessionPad Bridge {__version__}",
    )

    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
    )

    try:
        return asyncio.run(_async_main(args))
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    sys.exit(main())
