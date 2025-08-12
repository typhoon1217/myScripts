#!/usr/bin/env python3
"""
File organizer script that moves files containing specific text to target folders.
Usage: python group.py <directory> <search_text> <target_folder>
Example: python group.py vn신분증 front front
"""

import os
import sys
import shutil
from pathlib import Path

def move_files_with_text(target_dir, search_text, target_folder):
    """
    Move files containing search_text in filename to target_folder within specified directory.
    
    Args:
        target_dir: Specific directory to search in
        search_text: Text to search for in filenames
        target_folder: Target folder name to create/move files to
    """
    dir_path = Path(target_dir)
    
    if not dir_path.exists():
        print(f"❌ Directory {target_dir} does not exist")
        return
    
    if not dir_path.is_dir():
        print(f"❌ {target_dir} is not a directory")
        return
    
    moved_count = 0
    
    print(f"🔍 Processing directory: {dir_path.name}")
    
    # Create target folder if it doesn't exist
    target_path = dir_path / target_folder
    target_path.mkdir(exist_ok=True)
    
    # Find files containing search text
    matching_files = []
    for file_path in dir_path.iterdir():
        if file_path.is_file() and search_text.lower() in file_path.name.lower():
            # Skip if file is already in target folder
            if file_path.parent.name != target_folder:
                matching_files.append(file_path)
    
    # Move matching files
    for file_path in matching_files:
        try:
            dest_path = target_path / file_path.name
            
            # Handle duplicate filenames
            counter = 1
            original_dest = dest_path
            while dest_path.exists():
                stem = original_dest.stem
                suffix = original_dest.suffix
                dest_path = target_path / f"{stem}_{counter}{suffix}"
                counter += 1
            
            shutil.move(str(file_path), str(dest_path))
            print(f"✅ Moved: {file_path.name} → {dir_path.name}/{target_folder}/")
            moved_count += 1
            
        except Exception as e:
            print(f"❌ Error moving {file_path.name}: {e}")
    
    print(f"\n🎯 Total files moved: {moved_count}")

def main():
    if len(sys.argv) != 4:
        print("Usage: python group.py <directory> <search_text> <target_folder>")
        print("Example: python group.py vn신분증 front front")
        sys.exit(1)
    
    directory = sys.argv[1]
    search_text = sys.argv[2]
    target_folder = sys.argv[3]
    
    print(f"📁 Target directory: {directory}")
    print(f"🔎 Search text: '{search_text}'")
    print(f"📂 Target folder: '{target_folder}'")
    print("-" * 50)
    
    move_files_with_text(directory, search_text, target_folder)

if __name__ == "__main__":
    main()