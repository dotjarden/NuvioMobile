#!/usr/bin/env bash
# Synthetic live HLS on loopback for testLivePlayerNativeMenuFocus. Requires ffmpeg and Python 3.
set -euo pipefail
media_dir="$(mktemp -d /tmp/nuvio-player-fixture.XXXXXX)"
encoder_pid=""
server_pid=""
cleanup() {
  if [[ -n "$encoder_pid" ]]; then kill "$encoder_pid" 2>/dev/null || true; fi
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; fi
  rm -rf "$media_dir"
}
trap cleanup EXIT INT TERM
cat > "$media_dir/playlist.m3u" <<'PLAYLIST'
#EXTM3U
#EXTINF:-1 group-title="Test",Focus Test One
http://127.0.0.1:8767/live.m3u8
#EXTINF:-1 group-title="Test",Focus Test Two
http://127.0.0.1:8767/live.m3u8?channel=2
PLAYLIST
cat > "$media_dir/subtitles.srt" <<'SUBTITLES'
1
00:00:00,000 --> 00:00:30,000
Native player test subtitle
SUBTITLES
ffmpeg -hide_banner -loglevel error -nostdin -f lavfi -i testsrc2=size=640x360:rate=24 \
  -f lavfi -i sine=frequency=440:sample_rate=48000 -f lavfi -i sine=frequency=660:sample_rate=48000 \
  -i "$media_dir/subtitles.srt" -t 45 -map 0:v -map 1:a -map 2:a -map 3:s \
  -c:v libx264 -preset ultrafast -c:a aac -c:s mov_text -metadata:s:a:0 language=eng \
  -metadata:s:a:1 language=spa -metadata:s:s:0 language=eng -movflags +faststart "$media_dir/movie.mp4"
ffmpeg -hide_banner -loglevel error -nostdin -re -f lavfi -i testsrc2=size=640x360:rate=24 \
  -f lavfi -i sine=frequency=440:sample_rate=48000 -c:v libx264 -preset ultrafast \
  -g 48 -sc_threshold 0 -c:a aac -f hls -hls_time 2 -hls_list_size 6 \
  -hls_flags delete_segments+temp_file "$media_dir/live.m3u8" &
encoder_pid=$!
python3 -m http.server 8767 --bind 127.0.0.1 --directory "$media_dir" &
server_pid=$!
wait "$server_pid"
