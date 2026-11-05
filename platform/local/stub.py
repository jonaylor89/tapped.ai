"""Local stand-in for Google Places (New), Geocoding, OpenAI chat completions, Spotify and Stream Chat.

Stdlib only. Stream Chat is an in-memory fake of the REST + WebSocket surface the iOS SDK and the API's
mail bridge use: connect, query/watch/create channels, send messages, read state. State resets on restart.
"""
import base64
import hashlib
import json
import os
import threading
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PLACES = {
    "local-place-bluebird": ("The Bluebird", "Bluebird Ave, Richmond, VA", 37.5407, -77.4360),
    "local-place-capital": ("Capital Ale House", "E Main St, Richmond, VA", 37.5360, -77.4330),
    "local-place-richmond": ("Richmond", "Richmond, VA", 37.5407, -77.4360),
}


SPOTIFY_ARTISTS = {
    "4Z8W4fKeB5YxbusRsdQVPb": ("Radiohead (Local)", ["alternative rock"], 1000000),
    "0OdUWJ0sBjDrqHygGUXeCF": ("Band of Horses (Local)", ["indie folk"], 250000),
}


def artist(artist_id):
    name, genres, followers = SPOTIFY_ARTISTS[artist_id]
    return {
        "id": artist_id,
        "uri": f"spotify:artist:{artist_id}",
        "name": name,
        "genres": genres,
        "followers": {"total": followers},
        "popularity": 70,
        "images": [],
        "external_urls": {"spotify": f"https://open.spotify.com/artist/{artist_id}"},
    }


def place(place_id):
    name, address, lat, lng = PLACES[place_id]
    return {
        "id": place_id,
        "displayName": {"text": name},
        "shortFormattedAddress": address,
        "location": {"latitude": lat, "longitude": lng},
        "addressComponents": [{"longText": "Richmond", "shortText": "Richmond", "types": ["locality"]}],
        "photos": [],
    }


STREAM_NAMES = {"local-alice": "Alice Local", "local-bluebird": "The Bluebird (Local)", "local-carol": "Carol Local"}
STREAM_LOCK = threading.Lock()
STREAM_USERS = {}
STREAM_CHANNELS = {}
STREAM_SOCKETS = {}
STREAM_CONNECTIONS = {}
SOCKET_LOCKS = {}


def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def stream_user(user_id):
    user = STREAM_USERS.setdefault(user_id, {"id": user_id, "name": STREAM_NAMES.get(user_id, user_id)})
    stamp = "2026-01-01T00:00:00.000000Z"
    return {"role": "user", "created_at": stamp, "updated_at": stamp, "online": user_id in STREAM_SOCKETS,
            "banned": False, "teams": [], "language": "en", **user}


def stream_member(channel, user_id):
    return {"user_id": user_id, "user": stream_user(user_id), "created_at": channel["created_at"],
            "updated_at": channel["created_at"], "role": "member", "channel_role": "channel_member",
            "banned": False, "shadow_banned": False, "notifications_muted": False}


def stream_channel_payload(channel, user_id=None):
    config = {"reactions": True, "typing_events": True, "read_events": True, "connect_events": True,
              "replies": True, "quotes": True, "search": True, "mutes": True, "uploads": True,
              "url_enrichment": False, "custom_events": True, "push_notifications": False,
              "message_retention": "infinite", "max_message_length": 5000, "automod": "disabled",
              "commands": [], "created_at": channel["created_at"], "updated_at": channel["created_at"]}
    members = [stream_member(channel, m) for m in channel["members"]]
    payload = {
        "channel": {"id": channel["id"], "type": "messaging", "cid": f"messaging:{channel['id']}",
                    "created_at": channel["created_at"], "updated_at": channel["created_at"],
                    "last_message_at": channel["messages"][-1]["created_at"] if channel["messages"] else None,
                    "created_by": stream_user(channel["created_by"]), "frozen": channel["frozen"],
                    "disabled": False, "member_count": len(members), "config": config, "own_capabilities":
                    ["send-message", "read-events", "typing-events", "send-reaction", "update-own-message"]},
        "members": members,
        "messages": channel["messages"][-50:],
        "pinned_messages": [],
        "watcher_count": 0,
        "watchers": [],
        "read": [{"user": stream_user(m), "last_read": channel["read"].get(m, channel["created_at"]),
                  "unread_messages": sum(1 for msg in channel["messages"] if msg["user"]["id"] != m
                                         and msg["created_at"] > channel["read"].get(m, ""))}
                 for m in channel["members"]],
    }
    if user_id in channel["members"]:
        payload["membership"] = stream_member(channel, user_id)
    return payload


def stream_find_or_create(channel_id, members, created_by):
    with STREAM_LOCK:
        if channel_id is None:
            channel_id = next((c["id"] for c in STREAM_CHANNELS.values() if sorted(c["members"]) == sorted(members)),
                              "!members-" + uuid.uuid4().hex[:20])
        created = channel_id not in STREAM_CHANNELS
        if created:
            STREAM_CHANNELS[channel_id] = {"id": channel_id, "members": list(dict.fromkeys(members)),
                                           "created_by": created_by, "created_at": now(), "frozen": False,
                                           "messages": [], "read": {}}
        channel = STREAM_CHANNELS[channel_id]
    if created:
        stream_notify(channel, "notification.added_to_channel", skip=created_by)
    return channel


def stream_notify(channel, event_type, skip=None, **extra):
    """`notification.*` events reach members whose client isn't watching the channel yet."""
    for member in channel["members"]:
        if member != skip:
            payload = stream_channel_payload(channel, member)
            ws_send(member, {"type": event_type, "cid": f"messaging:{channel['id']}", "channel_id": channel["id"],
                             "channel_type": "messaging", "channel": payload["channel"], "member":
                             payload.get("membership"), "created_at": now(), **stream_unread(member), **extra})


def ws_frame(text):
    data = text.encode()
    header = bytes([0x81])
    if len(data) < 126:
        header += bytes([len(data)])
    elif len(data) < 65536:
        header += bytes([126]) + len(data).to_bytes(2, "big")
    else:
        header += bytes([127]) + len(data).to_bytes(8, "big")
    return header + data


def ws_send(user_id, event):
    for sock in list(STREAM_SOCKETS.get(user_id, [])):
        try:
            with SOCKET_LOCKS.setdefault(sock, threading.Lock()):
                sock.sendall(ws_frame(json.dumps(event)))
        except OSError:
            STREAM_SOCKETS[user_id].discard(sock)


def ws_read(sock):
    def exact(n):
        buf = b""
        while len(buf) < n:
            chunk = sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError
            buf += chunk
        return buf
    first, second = exact(2)
    length = second & 0x7F
    if length == 126:
        length = int.from_bytes(exact(2), "big")
    elif length == 127:
        length = int.from_bytes(exact(8), "big")
    mask = exact(4) if second & 0x80 else b"\0\0\0\0"
    payload = bytes(b ^ mask[i % 4] for i, b in enumerate(exact(length)))
    return first & 0x0F, payload


def stream_unread(user_id):
    counts = [stream_channel_payload(c)["read"][c["members"].index(user_id)]["unread_messages"]
              for c in STREAM_CHANNELS.values() if user_id in c["members"]]
    return {"total_unread_count": sum(counts), "unread_channels": sum(1 for n in counts if n)}


def stream_broadcast(channel, event):
    for member in channel["members"]:
        ws_send(member, {**event, "cid": f"messaging:{channel['id']}", "channel_id": channel["id"],
                         "channel_type": "messaging", "created_at": now(), **stream_unread(member)})


def stream_add_message(channel, user_id, message):
    msg = {"id": message.get("id") or str(uuid.uuid4()), "type": "regular", "text": message.get("text", ""),
           "html": "", "user": stream_user(user_id), "created_at": now(), "updated_at": now(),
           "attachments": [], "latest_reactions": [], "own_reactions": [], "reaction_counts": {},
           "reaction_scores": {}, "reply_count": 0, "mentioned_users": [], "silent": False, "shadowed": False,
           "pinned": False, "cid": f"messaging:{channel['id']}"}
    with STREAM_LOCK:
        channel["messages"].append(msg)
        channel["read"][user_id] = msg["created_at"]
    stream_broadcast(channel, {"type": "message.new", "message": msg, "user": stream_user(user_id),
                               "watcher_count": 0})
    stream_notify(channel, "notification.message_new", skip=user_id, message=msg)
    return msg


class StreamMixin:
    """Handlers for the Stream Chat routes. The caller is the `user_id` claim of the (unverified) user JWT,
    else its WebSocket connection, else explicit ids (server-side calls from the API)."""

    def stream_user_id(self, query, body):
        token_user = None
        try:
            claims = self.headers.get("Authorization", "").split(".")[1]
            token_user = json.loads(base64.urlsafe_b64decode(claims + "=" * (-len(claims) % 4))).get("user_id")
        except (IndexError, ValueError):
            pass
        return (token_user or STREAM_CONNECTIONS.get((query.get("connection_id") or [None])[0])
                or (query.get("user_id") or [None])[0] or body.get("user_id")
                or body.get("data", {}).get("created_by_id"))

    def stream_connect(self, query):
        payload = json.loads((query.get("json") or ["{}"])[0])
        user_id = payload.get("user_id") or payload.get("user_details", {}).get("id")
        details = payload.get("user_details", {})
        STREAM_USERS[user_id] = {**STREAM_USERS.get(user_id, {}), **{k: v for k, v in details.items()
                                 if k in ("id", "name", "image")}}
        STREAM_USERS[user_id].setdefault("name", STREAM_NAMES.get(user_id, user_id))
        key = base64.b64encode(hashlib.sha1((self.headers["Sec-WebSocket-Key"] +
                               "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        self.wfile.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                          f"Sec-WebSocket-Accept: {key}\r\n\r\n").encode())
        self.wfile.flush()
        sock = self.connection
        sock.settimeout(None)
        connection_id = str(uuid.uuid4())
        STREAM_CONNECTIONS[connection_id] = user_id
        lock = SOCKET_LOCKS.setdefault(sock, threading.Lock())
        STREAM_SOCKETS.setdefault(user_id, set()).add(sock)
        unread = stream_unread(user_id)["total_unread_count"]
        me = {**stream_user(user_id), "devices": [], "mutes": [], "channel_mutes": [], "total_unread_count": unread,
              "unread_channels": 0, "unread_count": unread, "unread_threads": 0, "online": True}
        health = {"type": "health.check", "connection_id": connection_id, "cid": "*", "me": me, "created_at": now()}
        with lock:
            sock.sendall(ws_frame(json.dumps(health)))
        try:
            while True:
                opcode, data = ws_read(sock)
                if opcode == 0x8:
                    break
                with lock:
                    if opcode == 0x9:
                        sock.sendall(bytes([0x8A, len(data)]) + data)
                    if opcode in (0x1, 0x9):
                        # The SDK counts a health.check event (not a pong frame) as its keep-alive answer.
                        sock.sendall(ws_frame(json.dumps({**health, "me": None, "created_at": now()})))
        except (ConnectionError, OSError):
            pass
        finally:
            STREAM_SOCKETS.get(user_id, set()).discard(sock)
            STREAM_CONNECTIONS.pop(connection_id, None)
            SOCKET_LOCKS.pop(sock, None)
        self.close_connection = True

    def stream_route(self, method, path, query, body):
        parts = path.strip("/").split("/")
        user_id = self.stream_user_id(query, body)
        if parts == ["channels"]:
            mine = [c for c in STREAM_CHANNELS.values() if user_id in c["members"]]
            mine.sort(key=lambda c: c["messages"][-1]["created_at"] if c["messages"] else c["created_at"], reverse=True)
            return {"channels": [stream_channel_payload(c, user_id) for c in mine], "duration": "0.1ms"}
        if len(parts) >= 3 and parts[0] == "channels" and parts[1] == "messaging":
            tail = parts[2:]
            if tail == ["query"] or (len(tail) == 2 and tail[1] == "query"):
                data = body.get("data", {})
                members = [m if isinstance(m, str) else m.get("user_id") for m in data.get("members", [])]
                if tail != ["query"] and tail[0] in STREAM_CHANNELS:
                    channel = STREAM_CHANNELS[tail[0]]
                else:
                    channel = stream_find_or_create(None if tail == ["query"] else tail[0],
                                                    members or [user_id], data.get("created_by_id") or user_id)
                return {**stream_channel_payload(channel, user_id), "duration": "0.1ms"}
            channel = STREAM_CHANNELS.get(tail[0])
            if channel is None:
                return None
            if tail[1:] == ["message"]:
                message = body.get("message", {})
                msg = stream_add_message(channel, message.get("user_id") or user_id, message)
                return {"message": msg, "duration": "0.1ms"}
            if tail[1:] == ["read"]:
                with STREAM_LOCK:
                    channel["read"][user_id] = now()
                stream_broadcast(channel, {"type": "message.read", "user": stream_user(user_id)})
                return {"event": {"type": "message.read", "created_at": now()}, "duration": "0.1ms"}
            if tail[1:] == ["event"]:
                event = body.get("event", {})
                stream_broadcast(channel, {**event, "user": stream_user(user_id)})
                return {"event": {**event, "created_at": now()}, "duration": "0.1ms"}
            if tail[1:] == [] and method == "PATCH":
                channel["frozen"] = bool(body.get("set", {}).get("frozen", channel["frozen"]))
                return {**stream_channel_payload(channel, user_id), "duration": "0.1ms"}
        if parts[:1] in (["devices"], ["users"], ["sync"], ["channels"], ["drafts"], ["threads"], ["reminders"]):
            return {"duration": "0.1ms", "users": {}, "events": [], "drafts": [], "threads": [], "reminders": []}
        return None


class Handler(StreamMixin, BaseHTTPRequestHandler):
    def send_json(self, body, status=200):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        path = urlparse(self.path).path
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if path.endswith("/api/token"):
            return self.send_json({"access_token": "local-spotify-token", "token_type": "Bearer", "expires_in": 3600})
        if self.is_stream(path):
            return self.stream_respond("POST", path, raw)
        body = json.loads(raw or b"{}")
        if path.endswith("/places:autocomplete"):
            query = body.get("input", "").lower()
            matches = [i for i, p in PLACES.items() if query in p[0].lower() or query in p[1].lower()]
            return self.send_json({"suggestions": [{"placePrediction": {
                "placeId": i,
                "text": {"text": f"{PLACES[i][0]}, {PLACES[i][1]}"},
                "structuredFormat": {"mainText": {"text": PLACES[i][0]}, "secondaryText": {"text": PLACES[i][1]}},
            }} for i in matches]})
        if path.endswith("/chat/completions"):
            return self.send_json({"choices": [{"message": {"role": "assistant", "content":
                "Hi there,\n\nThis is a local stub email from Tapped.\n\nThanks!"}}]})
        self.send_json({"error": "not stubbed"}, 404)

    def is_stream(self, path):
        return path.strip("/").split("/")[0] in ("api", "connect", "channels", "devices", "users", "sync", "drafts",
                                                  "threads", "reminders", "messages", "moderation")

    def stream_respond(self, method, path, raw):
        body = json.loads(raw or b"{}") if raw else {}
        response = self.stream_route(method, path, parse_qs(urlparse(self.path).query), body)
        if response is None:
            return self.send_json({"code": 16, "message": f"stub: {method} {path} not handled",
                                   "StatusCode": 404, "duration": "0.1ms", "more_info": "", "details": [],
                                   "exception_fields": {}}, 404)
        self.send_json(response)

    def do_PATCH(self):
        path = urlparse(self.path).path
        self.stream_respond("PATCH", path, self.rfile.read(int(self.headers.get("Content-Length", 0))))

    def do_DELETE(self):
        self.stream_respond("DELETE", urlparse(self.path).path, b"")

    def do_GET(self):
        path = urlparse(self.path).path
        if path.strip("/") == "connect":
            return self.stream_connect(parse_qs(urlparse(self.path).query))
        if self.is_stream(path):
            return self.stream_respond("GET", path, b"")
        if path.endswith("/media"):
            return self.send_json({"photoUri": None})
        if path.endswith("/geocode/json"):
            return self.send_json({"results": [{"place_id": "local-place-richmond"}]})
        parts = path.strip("/").split("/")
        if "artists" in parts:
            artist_id = parts[parts.index("artists") + 1]
            if artist_id not in SPOTIFY_ARTISTS:
                return self.send_json({"error": {"status": 404, "message": "Resource not found"}}, 404)
            if parts[-1] == "top-tracks":
                return self.send_json({"tracks": [{
                    "id": f"{artist_id}-track-{n}",
                    "name": f"Local Track {n}",
                    "uri": f"spotify:track:{artist_id}-track-{n}",
                    "duration_ms": 200000,
                    "preview_url": None,
                    "album": {"name": "Local Album", "images": []},
                    "artists": [{"id": artist_id, "name": SPOTIFY_ARTISTS[artist_id][0]}],
                } for n in (1, 2, 3)]})
            return self.send_json(artist(artist_id))
        place_id = path.rsplit("/", 1)[-1]
        if "/places/" in path and place_id in PLACES:
            return self.send_json(place(place_id))
        self.send_json({"error": "not found"}, 404)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8090"))
    cert, key = os.environ.get("STUB_TLS_CERT"), os.environ.get("STUB_TLS_KEY")
    if cert and key and os.path.exists(cert):
        # The Stream iOS SDK only speaks https/wss, so it gets a TLS listener (see stream-cert.sh).
        import ssl
        tls = ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("TLS_PORT", "8443"))), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        tls.socket = context.wrap_socket(tls.socket, server_side=True)
        threading.Thread(target=tls.serve_forever, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
