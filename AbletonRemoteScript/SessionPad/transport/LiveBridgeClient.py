# transport/LiveBridgeClient.py
# TCP client connecting the Ableton Remote Script to the macOS SessionPad Bridge.

import select
import socket

BRIDGE_HOST = "127.0.0.1"
BRIDGE_PORT = 17345
RECONNECT_INTERVAL_TICKS = 10
CONNECT_TIMEOUT_SEC = 0.5


class LiveBridgeClient(object):
    """Non-blocking TCP client with newline-framed JSON messages."""

    def __init__(self, on_connected=None, on_disconnected=None):
        self._sock = None
        self._connected = False
        self._recv_buffer = ""
        self._inbound_queue = []
        self._on_connected = on_connected
        self._on_disconnected = on_disconnected
        self._ticks_since_connect = RECONNECT_INTERVAL_TICKS

    @property
    def is_connected(self):
        return self._connected

    def tick(self):
        """Called from update_display — maintain connection and read data."""
        if self._sock is None:
            self._ticks_since_connect += 1
            if self._ticks_since_connect >= RECONNECT_INTERVAL_TICKS:
                self._ticks_since_connect = 0
                self._try_connect()
            return

        self._read_available()

    def send(self, text):
        """Send a JSON line to the bridge."""
        if not self._connected or self._sock is None:
            return False
        try:
            payload = (text + "\n").encode("utf-8")
            self._sock.sendall(payload)
            return True
        except (socket.error, OSError):
            self._disconnect()
            return False

    def poll_inbound(self, max_items=64):
        """Drain queued inbound messages (Live thread only)."""
        items = self._inbound_queue[:max_items]
        del self._inbound_queue[:max_items]
        return items

    def _try_connect(self):
        sock = None
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            # Short blocking connect — reliable on localhost and only attempted
            # periodically while disconnected.
            sock.settimeout(CONNECT_TIMEOUT_SEC)
            sock.connect((BRIDGE_HOST, BRIDGE_PORT))
            sock.setblocking(False)
            try:
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            except Exception:
                pass

            self._sock = sock
            self._connected = True
            self._recv_buffer = ""
            if self._on_connected:
                self._on_connected()
        except Exception:
            if sock:
                try:
                    sock.close()
                except Exception:
                    pass

    def _read_available(self):
        if self._sock is None:
            return
        try:
            while True:
                readable, _, errored = select.select([self._sock], [], [self._sock], 0)
                if errored:
                    self._disconnect()
                    return
                if not readable:
                    break
                chunk = self._sock.recv(65536)
                if not chunk:
                    self._disconnect()
                    return
                self._recv_buffer += chunk.decode("utf-8", errors="replace")
                self._drain_lines()
        except (socket.error, OSError):
            self._disconnect()

    def _drain_lines(self):
        while True:
            idx = self._recv_buffer.find("\n")
            if idx < 0:
                break
            line = self._recv_buffer[:idx].strip()
            self._recv_buffer = self._recv_buffer[idx + 1:]
            if line:
                self._inbound_queue.append(line)

    def _disconnect(self):
        was_connected = self._connected
        if self._sock:
            try:
                self._sock.close()
            except Exception:
                pass
        self._sock = None
        self._connected = False
        self._recv_buffer = ""
        if was_connected and self._on_disconnected:
            self._on_disconnected()

    def stop(self):
        self._disconnect()
