#!/bin/bash
set -e

CONFIG_DIR="$HOME/.config/ocaptain"

echo "Stopping ocaptain telemetry collector..."

# Stop tailscale serve
tailscale serve --tcp 4318 off 2>/dev/null || true

# Stop otlp2parquet
if [ -f "$CONFIG_DIR/otlp2parquet.pid" ]; then
    kill "$(cat "$CONFIG_DIR/otlp2parquet.pid")" 2>/dev/null || true
    rm "$CONFIG_DIR/otlp2parquet.pid"
fi

echo "Telemetry collector stopped."
