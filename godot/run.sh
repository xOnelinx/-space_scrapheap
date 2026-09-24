#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
if [[ ! -x "$GODOT" ]]; then
	echo "Godot не найден: $GODOT" >&2
	echo "Скачай Godot 4.7.x (Linux x86_64) и положи бинарник в ~/.local/bin/godot" >&2
	exit 1
fi
exec "$GODOT" --path "$ROOT" "$@"
