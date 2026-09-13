#!/usr/bin/env bash
set -euo pipefail

godot_binary="${1:-godot}"
project_directory="$(cd "$(dirname "$0")/.." && pwd)"
build_directory="$project_directory/build/linux"

mkdir -p "$build_directory"
"$godot_binary" \
	--headless \
	--path "$project_directory" \
	--export-pack Linux "$build_directory/Cisterns.pck"
cp "$godot_binary" "$build_directory/Cisterns.x86_64"
chmod 755 "$build_directory/Cisterns.x86_64"

echo "Linux build: $build_directory"
