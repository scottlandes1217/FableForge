#!/bin/bash
# Wrapper script to run sprite atlas generator with virtual environment

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

# Activate virtual environment
source "$SCRIPT_DIR/venv/bin/activate"

# Run the script with all arguments
python3 "$SCRIPT_DIR/generate_sprite_atlas.py" "$@"
