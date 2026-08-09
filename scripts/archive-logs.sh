#!/bin/bash
# Archive docker json logs older than current (json-file with max-size already rotates)
# This is optional — docker log-rotation handles it. This script just shows log sizes.
set -e
echo "Docker log sizes:"
for c in $(docker ps -a --format "{{.Names}}" 2>&1 | head -20); do
  log=$(docker inspect $c --format "{{.LogPath}}" 2>&1 | head -1)
  if [ -f "$log" ]; then
    sz=$(du -h "$log" 2>&1 | cut -f1)
    echo "  $c: $sz ($log)"
  fi
done
echo "All logs capped at 10m*3=30m per container via compose logging opts"
