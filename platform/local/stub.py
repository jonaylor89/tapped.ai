"""Local stand-in for Google Places (New), Geocoding and OpenAI chat completions. Stdlib only."""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

PLACES = {
    "local-place-bluebird": ("The Bluebird", "Bluebird Ave, Richmond, VA", 37.5407, -77.4360),
    "local-place-capital": ("Capital Ale House", "E Main St, Richmond, VA", 37.5360, -77.4330),
    "local-place-richmond": ("Richmond", "Richmond, VA", 37.5407, -77.4360),
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
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
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
        place_id = path.rsplit("/", 1)[-1]
        if "/places/" in path and place_id in PLACES:
            return self.send_json(place(place_id))
        self.send_json({"error": "not found"}, 404)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8090"))
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
