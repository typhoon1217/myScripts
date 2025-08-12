#!/bin/zsh

# Script to register current directory as a project shortcut with backend/frontend bindings
# Usage: regprj.sh <project_name>

if [ $# -ne 1 ]; then
    echo "Usage: $0 <project_name>"
    echo "Example: $0 myapp"
    exit 1
fi

project_name="$1"
current_dir="$(pwd)"
instant_aliases_file="$HOME/.config/.zsh/aliases/instant.zsh"

# Create the instant.zsh file if it doesn't exist
if [ ! -f "$instant_aliases_file" ]; then
    touch "$instant_aliases_file"
fi

# Remove existing aliases if they exist
sed -i "/^alias $project_name=/d" "$instant_aliases_file"
sed -i "/^alias ${project_name}b=/d" "$instant_aliases_file"
sed -i "/^alias ${project_name}f=/d" "$instant_aliases_file"

# Add the main project alias
echo "alias $project_name='cd $current_dir'" >> "$instant_aliases_file"

# Add backend alias if ./backend exists
if [ -d "$current_dir/backend" ]; then
    echo "alias ${project_name}b='cd $current_dir/backend'" >> "$instant_aliases_file"
    echo "Registered: ${project_name}b -> $current_dir/backend"
fi

# Add frontend alias if ./frontend exists
if [ -d "$current_dir/frontend" ]; then
    echo "alias ${project_name}f='cd $current_dir/frontend'" >> "$instant_aliases_file"
    echo "Registered: ${project_name}f -> $current_dir/frontend"
fi

echo "Registered project: $project_name -> $current_dir"

# Reload the alias file in the current shell
source "/home/jungwoo/.zshrc"
echo "Aliases loaded and ready to use!"
