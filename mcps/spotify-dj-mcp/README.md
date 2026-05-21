# Spotify DJ MCP

Bundled MCP for controlling Spotify playback from Claude sessions. Replaces the claude.ai-hosted Spotify connector.

## What it does

- `play_track(query)` — search and play a specific track
- `play_playlist(name)` — play a playlist by name
- `current()` — what's playing right now (track, artist, album, progress)
- `pause()` / `resume()` / `next()` / `previous()`
- `volume(level)` — 0-100
- `search(query, type)` — search tracks, albums, artists, playlists

Works with Spotify Premium (the Web API's playback endpoints require Premium).

## Setup

### 1. Create a Spotify Developer app (one-time, ~3 minutes)

1. Visit https://developer.spotify.com/dashboard
2. Log in with your Spotify account → "Create app"
3. Name: "Claude DJ" (anything)
4. Redirect URI: `http://127.0.0.1:8888/callback` — **must be loopback IP, not `localhost`**. Spotify rejects `http://localhost` as insecure (deprecated Apr 2025); only HTTPS or loopback IP (`127.0.0.1`) are accepted.
5. Which API/SDKs: check "Web API"
6. Save. Copy **Client ID** and **Client Secret** from the app settings.

### 2. Install

```bash
# Installed via mcps/setup.sh — or manually:
cd mcps/spotify-dj-mcp
python3 -m venv .venv
.venv/bin/pip install spotipy mcp
```

### 3. Auth

Add to `~/.zshrc`:
```bash
export SPOTIFY_CLIENT_ID="your_client_id"
export SPOTIFY_CLIENT_SECRET="your_client_secret"
export SPOTIFY_REDIRECT_URI="http://127.0.0.1:8888/callback"
```

First run opens a browser for OAuth. Token cached at `~/.claude/spotify-cache.json` — subsequent runs are silent.

## Register with Claude Code

```bash
claude mcp add spotify-dj -- ~/obsidian/mcps/spotify-dj-mcp/.venv/bin/python ~/obsidian/mcps/spotify-dj-mcp/server.py
```

Tools appear as `mcp__spotify-dj__*`.

## Example usage

Ask Claude naturally — it picks the right tool:

```
"DJ, put on Radiohead Kid A"
"Play some builder-mode instrumental music"
"Play my 'Deep Work' playlist"
"What's playing?"
"Pause"
"Skip this, next track"
"Volume 40"
"Search for recent albums by a given artist and play the top one"
```
