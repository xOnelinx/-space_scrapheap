#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
if [[ ! -x "$GODOT" ]]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT="$(command -v godot)"
	else
		echo "Godot не найден: $GODOT" >&2
		echo "Положи бинарник в ~/.local/bin/godot или задай GODOT" >&2
		exit 1
	fi
fi
shopt -s nullglob
scripts=("$ROOT"/tests/verify_*.gd)
if [[ ${#scripts[@]} -eq 0 ]]; then
	echo "Нет проверок: $ROOT/tests/verify_*.gd" >&2
	exit 1
fi
for script in "${scripts[@]}"; do
	name="$(basename "$script")"
	echo "== $name"
	"$GODOT" --headless --path "$ROOT" -s "res://tests/$name"
done
echo "ok ${#scripts[@]}"
