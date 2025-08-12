#!/bin/zsh

# Script to register current directory as a shortcut alias
# Usage: register_shortcut.sh <alias_name>

if [ $# -ne 1 ]; then
    echo "Usage: $0 <alias_name>"
    echo "Example: $0 myproject"
    exit 1
fi

alias_name="$1"
current_dir="$(pwd)"
instant_aliases_file="$HOME/.config/.zsh/aliases/instant.zsh"

# Create the instant.zsh file if it doesn't exist
if [ ! -f "$instant_aliases_file" ]; then
    touch "$instant_aliases_file"
fi

# Check if alias already exists
if grep -q "^alias $alias_name=" "$instant_aliases_file"; then
    echo "Alias '$alias_name' already exists. Updating..."
    # Remove existing alias
    sed -i "/^alias $alias_name=/d" "$instant_aliases_file"
fi

# Add the new alias
echo "alias $alias_name='cd $current_dir'" >> "$instant_aliases_file"

echo "Registered shortcut: $alias_name -> $current_dir"

# Reload the alias file in the current shell
source "/home/jungwoo/.zshrc"
echo "Alias loaded and ready to use!"
