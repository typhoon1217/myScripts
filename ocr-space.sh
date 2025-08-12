#!/bin/bash
# Fast OCR using OCR.space API
# Usage: ./ocr-space-fast.sh [directory] [api_key]

TARGET_DIR="${1:-/home/jungwoo/Pictures/Screenshots/}"
API_KEY="${2:-K89941822588957}"

# Check if API key is provided
if [ -z "$API_KEY" ]; then
    echo "Usage: $0 [directory] [api_key]"
    echo "Get free API key from: https://ocr.space/ocrapi"
    echo "Example: $0 ~/Screenshots your_api_key_here"
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' does not exist"
    exit 1
fi

echo "Processing PNG files in: $TARGET_DIR"
echo "Using OCR.space API..."

cd "$TARGET_DIR" || exit 1
mkdir -p ocr_results

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Installing jq for JSON parsing..."
    sudo pacman -S jq
fi

# Process files
count=0
total=$(ls *.png 2>/dev/null | wc -l)

if [ "$total" -eq 0 ]; then
    echo "No PNG files found in $TARGET_DIR"
    exit 1
fi

echo "Found $total PNG files to process"

for png_file in *.png; do
    [ ! -f "$png_file" ] && continue
    
    ((count++))
    echo -n "[$count/$total] Processing: $png_file ... "
    
    base_name=$(basename "$png_file" .png)
    output_file="ocr_results/${base_name}.txt"
    
    # Send to OCR.space API
    response=$(curl -s -X POST https://api.ocr.space/parse/image \
        -H "apikey: $API_KEY" \
        -F "file=@$png_file" \
        -F "language=eng" \
        -F "isOverlayRequired=false" \
        -F "detectOrientation=true" \
        -F "scale=true")
    
    # Extract text from JSON response
    if echo "$response" | jq -e '.ParsedResults[0].ParsedText' > /dev/null 2>&1; then
        extracted_text=$(echo "$response" | jq -r '.ParsedResults[0].ParsedText')
        
        if [ "$extracted_text" != "null" ] && [ -n "$extracted_text" ]; then
            echo "File: $png_file" > "$output_file"
            echo "Date: $(date)" >> "$output_file"
            echo "OCR Engine: OCR.space" >> "$output_file"
            echo "---" >> "$output_file"
            echo "$extracted_text" >> "$output_file"
            echo "✓"
        else
            echo "No text found" > "$output_file"
            echo "⚠ No text"
        fi
    else
        echo "API Error" > "$output_file"
        echo "✗ Failed"
    fi
    
    # Small delay to respect API limits
    sleep 0.5
done

echo ""
echo "Processing complete!"
echo "Results saved in: ocr_results/"
echo "Total files processed: $count"
