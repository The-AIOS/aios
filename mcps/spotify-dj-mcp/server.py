"""Spotify DJ MCP — control Spotify playback via the Web API."""
import os
import sys
from pathlib import Path

from mcp.server.fastmcp import FastMCP

try:
    import spotipy
    from spotipy.oauth2 import SpotifyOAuth
except ImportError:
    print("ERROR: spotipy not installed. Run: pip install spotipy mcp", file=sys.stderr)
    sys.exit(1)

for v in ("SPOTIFY_CLIENT_ID", "SPOTIFY_CLIENT_SECRET"):
    if not os.environ.get(v):
        print(f"ERROR: {v} not set. See mcps/spotify-dj-mcp/README.md", file=sys.stderr)
        sys.exit(1)

SCOPES = [
    "user-read-playback-state",
    "user-modify-playback-state",
    "user-read-currently-playing",
    "playlist-read-private",
    "playlist-read-collaborative",
]
CACHE_PATH = str(Path.home() / ".claude" / "spotify-cache.json")

mcp = FastMCP("spotify-dj")
sp = spotipy.Spotify(auth_manager=SpotifyOAuth(
    client_id=os.environ["SPOTIFY_CLIENT_ID"],
    client_secret=os.environ["SPOTIFY_CLIENT_SECRET"],
    redirect_uri=os.environ.get("SPOTIFY_REDIRECT_URI", "http://127.0.0.1:8888/callback"),
    scope=" ".join(SCOPES),
    cache_path=CACHE_PATH,
    open_browser=True,
))


def _device_id() -> str | None:
    devices = sp.devices().get("devices", [])
    active = [d for d in devices if d.get("is_active")]
    return (active or devices or [{}])[0].get("id")


@mcp.tool()
def current() -> dict:
    """What's playing right now? Returns track, artist, album, progress, device."""
    playback = sp.current_playback()
    if not playback or not playback.get("item"):
        return {"playing": False}
    item = playback["item"]
    return {
        "playing": playback.get("is_playing", False),
        "track": item["name"],
        "artist": ", ".join(a["name"] for a in item["artists"]),
        "album": item["album"]["name"],
        "progress_ms": playback.get("progress_ms"),
        "duration_ms": item.get("duration_ms"),
        "device": playback.get("device", {}).get("name"),
    }


@mcp.tool()
def play_track(query: str) -> dict:
    """Search and play a track. Query can be 'artist track', 'song name', etc."""
    results = sp.search(q=query, type="track", limit=1)
    items = results.get("tracks", {}).get("items", [])
    if not items:
        return {"error": f"no track found for: {query}"}
    uri = items[0]["uri"]
    sp.start_playback(device_id=_device_id(), uris=[uri])
    return {"playing": items[0]["name"], "artist": items[0]["artists"][0]["name"], "uri": uri}


@mcp.tool()
def play_playlist(name: str) -> dict:
    """Find and play a playlist by name. Searches your library and public playlists."""
    results = sp.search(q=name, type="playlist", limit=1)
    items = results.get("playlists", {}).get("items", [])
    if not items:
        return {"error": f"no playlist found for: {name}"}
    uri = items[0]["uri"]
    sp.start_playback(device_id=_device_id(), context_uri=uri)
    return {"playing_playlist": items[0]["name"], "uri": uri}


@mcp.tool()
def pause() -> dict:
    """Pause playback."""
    sp.pause_playback(device_id=_device_id())
    return {"status": "paused"}


@mcp.tool()
def resume() -> dict:
    """Resume playback."""
    sp.start_playback(device_id=_device_id())
    return {"status": "playing"}


@mcp.tool()
def next_track() -> dict:
    """Skip to next track."""
    sp.next_track(device_id=_device_id())
    return current()


@mcp.tool()
def previous_track() -> dict:
    """Go back to previous track."""
    sp.previous_track(device_id=_device_id())
    return current()


@mcp.tool()
def volume(level: int) -> dict:
    """Set playback volume (0-100)."""
    level = max(0, min(100, int(level)))
    sp.volume(level, device_id=_device_id())
    return {"volume": level}


@mcp.tool()
def search(query: str, type: str = "track", limit: int = 5) -> dict:
    """Search Spotify. type = track | album | artist | playlist. Returns top results."""
    results = sp.search(q=query, type=type, limit=limit)
    key = f"{type}s"
    items = results.get(key, {}).get("items", [])
    return {
        "type": type,
        "query": query,
        "results": [
            {"name": i["name"], "uri": i["uri"], "artist": ", ".join(a["name"] for a in i.get("artists", []))}
            for i in items
        ],
    }


if __name__ == "__main__":
    mcp.run()
