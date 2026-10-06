#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p marketing/launch/renders
swiftc -O -module-cache-path /tmp/typefield-launch-module-cache \
  marketing/launch/render.swift -o marketing/launch/renders/render
marketing/launch/renders/render --audit
marketing/launch/renders/render --stills
marketing/launch/renders/render
ffmpeg -hide_banner -loglevel error -y \
  -i marketing/launch/renders/Typefield-Launch-Master-1080p60-v11.mp4 \
  -vf fps=30 -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
  -an -movflags +faststart marketing/launch/renders/Typefield-Launch-Landscape-v11.mp4
ffmpeg -hide_banner -loglevel error -y -ss 44.5 \
  -i marketing/launch/renders/Typefield-Launch-Landscape-v11.mp4 \
  -frames:v 1 -update 1 marketing/launch/renders/Typefield-Launch-Poster-v11.png
ffmpeg -v error -i marketing/launch/renders/Typefield-Launch-Landscape-v11.mp4 -f null -
ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,nb_frames:format=duration,size \
  -of json marketing/launch/renders/Typefield-Launch-Landscape-v11.mp4
