"""Local stand-in for Google Places (New), Geocoding, OpenAI chat completions and Spotify. Stdlib only."""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

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


class Handler(BaseHTTPRequestHandler):
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

    def do_GET(self):
        path = urlparse(self.path).path
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
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
