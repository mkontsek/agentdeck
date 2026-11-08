#!/bin/bash
set -euo pipefail
asset_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$asset_dir/../../.." && pwd)"
frame_dir="$(mktemp -d "${TMPDIR:-/tmp}/agentdeck-social.XXXXXX")"
trap 'rm -rf "$frame_dir"' EXIT
swift "$asset_dir/render.swift" "$frame_dir" "$repo_dir/docs/icon.png"
ffmpeg -hide_banner -loglevel error -y -framerate 30 -i "$frame_dir/%04d.png" \
  -c:v libx264 -preset slow -crf 19 -pix_fmt yuv420p -movflags +faststart \
  -an "$asset_dir/agentdeck-update.mp4"
cp "$frame_dir/0110.png" "$asset_dir/poster.png"
echo "Rendered $asset_dir/agentdeck-update.mp4"
