#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
morrow_cli_source="${1:-$(pwd)/build/Morrow.app/Contents/MacOS/morrow}"
morrow_cli_source="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$morrow_cli_source")"
if [[ ! -x "$morrow_cli_source" ]]; then
    echo "Build the app first or pass the path to a standalone morrow binary." >&2
    exit 1
fi
mkdir -p "$HOME/.local/bin"
morrow_cli_destination="$HOME/.local/bin/morrow"
if [[ -e "$morrow_cli_destination" || -L "$morrow_cli_destination" ]]; then
    if [[ -L "$morrow_cli_destination" && "$(readlink "$morrow_cli_destination")" == "$morrow_cli_source" ]]; then
        echo "morrow is already linked."
        exit 0
    fi
    echo "A command already exists at $morrow_cli_destination; it has been preserved." >&2
    exit 1
fi
ln -s "$morrow_cli_source" "$morrow_cli_destination"
echo "Linked morrow into $HOME/.local/bin. Add that directory to PATH if needed."
