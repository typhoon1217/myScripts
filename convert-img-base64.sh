#!/bin/bash

# Image to Base64 converter script
# Usage: ./convert_images.sh [directory_path]
# If no directory is specified, uses current directory

# Set target directory (use argument or current directory)
TARGET_DIR="${1:-.}"

# Check if directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' does not exist."
    exit 1
fi

echo "Converting images in directory: $TARGET_DIR"
echo "----------------------------------------"

# Counter for processed files
processed=0
skipped=0

# Loop through common image file extensions
for img_file in "$TARGET_DIR"/*.{jpg,jpeg,png,gif,bmp,tiff,tif,webp,JPG,JPEG,PNG,GIF,BMP,TIFF,TIF,WEBP}; do
    # Skip if no files match the pattern
    [ ! -f "$img_file" ] && continue
    
    # Get filename without path
    filename=$(basename "$img_file")
    
    # Get filename without extension and the extension
    name_without_ext="${filename%.*}"
    extension="${filename##*.}"
   
    mkdir -p "$TARGET_DIR/base64"
    
    # Create output filename: originalname+originalformat.txt
    output_file="$TARGET_DIR/base64/${name_without_ext}+${extension}.txt"
    
    # Check if output file already exists
    if [ -f "$output_file" ]; then
        echo "SKIP: $output_file already exists"
        ((skipped++))
        continue
    fi
    
    # Convert image to base64 and save to text file
    if base64 "$img_file" > "$output_file"; then
        echo "DONE: $filename -> ${name_without_ext}+${extension}.txt"
        ((processed++))
    else
        echo "ERROR: Failed to convert $filename"
    fi
done

echo "----------------------------------------"
echo "Conversion complete!"
echo "Processed: $processed files"
echo "Skipped: $skipped files"

