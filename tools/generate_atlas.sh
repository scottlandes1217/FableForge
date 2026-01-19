#!/bin/bash
# Wrapper script to run sprite atlas generator with virtual environment

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

# Try to source REPLICATE_API_KEY from common shell config files
# Check .zshrc first (for zsh users)
if [ -f "$HOME/.zshrc" ] && grep -q "^export REPLICATE_API_KEY" "$HOME/.zshrc"; then
    # Extract the export line and evaluate it
    export_line=$(grep "^export REPLICATE_API_KEY" "$HOME/.zshrc" | head -1)
    # Use eval to export the variable (only the export line, not the whole file)
    eval "$export_line"
fi

# Also check .bash_profile and .bashrc for bash users
if [ -z "$REPLICATE_API_KEY" ] && [ -f "$HOME/.bash_profile" ] && grep -q "^export REPLICATE_API_KEY" "$HOME/.bash_profile"; then
    export_line=$(grep "^export REPLICATE_API_KEY" "$HOME/.bash_profile" | head -1)
    eval "$export_line"
fi

if [ -z "$REPLICATE_API_KEY" ] && [ -f "$HOME/.bashrc" ] && grep -q "^export REPLICATE_API_KEY" "$HOME/.bashrc"; then
    export_line=$(grep "^export REPLICATE_API_KEY" "$HOME/.bashrc" | head -1)
    eval "$export_line"
fi

# Activate virtual environment
source "$SCRIPT_DIR/venv/bin/activate"

# Run the script with all arguments
python3 "$SCRIPT_DIR/generate_sprite_atlas.py" "$@"
