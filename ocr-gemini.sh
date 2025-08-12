#!/bin/bash
# OCR using Google Gemini Vision API
# Usage: ./gemini-ocr.sh [directory]

TARGET_DIR="${1:-/home/jungwoo/Pictures/Screenshots/}"

# Check if GEMINI_API_KEY environment variable is set
if [ -z "$GEMINI_API_KEY" ]; then
    echo "Error: GEMINI_API_KEY environment variable not set"
    echo "Set it with: export GEMINI_API_KEY='your_api_key_here'"
    echo "Or add to ~/.bashrc: echo 'export GEMINI_API_KEY=\"your_key\"' >> ~/.bashrc"
    exit 1
fi

# Check if directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' does not exist"
    exit 1
fi

echo "Processing PNG files in: $TARGET_DIR"
echo "Using Google Gemini Vision API..."

cd "$TARGET_DIR" || exit 1
mkdir -p gemini_ocr_results

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Installing jq for JSON parsing..."
    sudo pacman -S jq
fi

# Process files
count=0
failed=0
total=$(ls *.png 2>/dev/null | wc -l)

if [ "$total" -eq 0 ]; then
    echo "No PNG files found in $TARGET_DIR"
    exit 1
fi

echo "Found $total PNG files to process"
echo "Starting OCR processing..."

for png_file in *.png; do
    [ ! -f "$png_file" ] && continue
    
    ((count++))
    echo -n "[$count/$total] Processing: $png_file ... "
    
    base_name=$(basename "$png_file" .png)
    output_file="gemini_ocr_results/${base_name}.txt"
    
    # Convert image to base64
    base64_img=$(base64 -w 0 "$png_file")
    
    # Create JSON payload for Gemini
    json_payload=$(cat <<EOF
{
  "contents": [{
    "parts": [
      {
        "text": "Please extract ALL text from this image. This appears to be a screenshot, possibly of terminal/shell output or code. Please:
1. Extract all visible text exactly as it appears
2. Preserve formatting, spacing, and line breaks
3. Include all commands, output, file paths, and any other text
4. Do not add any commentary or explanations
5. Return only the extracted text content
6. If there are multiple columns or sections, preserve their layout
7. Include special characters, symbols, and formatting"
      },
      {
        "inline_data": {
          "mime_type": "image/png",
          "data": "$base64_img"
        }
      }
    ]
  }],
  "generationConfig": {
    "temperature": 0.1,
    "topK": 1,
    "topP": 0.8,
    "maxOutputTokens": 2048
  }
}
EOF
)
    
    # Send to Gemini API
    response=$(curl -s -X POST \
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$GEMINI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$json_payload" \
        --max-time 30)
    
    # Check if we got a valid response
    if [ -z "$response" ]; then
        echo "Network error" > "$output_file"
        echo "✗ Network Error"
        ((failed++))
        continue
    fi
    
    # Extract text from JSON response
    if echo "$response" | jq -e '.candidates[0].content.parts[0].text' > /dev/null 2>&1; then
        extracted_text=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text')
        
        if [ "$extracted_text" != "null" ] && [ -n "$extracted_text" ]; then
            # Save the extracted text (clean, no metadata)
            echo "$extracted_text" > "$output_file"
            echo "✓"
        else
            echo "No text extracted" > "$output_file"
            echo "⚠ No text"
        fi
    else
        # Check for API errors
        error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"')
        echo "API Error: $error_msg" > "$output_file"
        echo "✗ API Error"
        ((failed++))
        
        # Debug: save full response for troubleshooting
        echo "$response" > "gemini_ocr_results/${base_name}_debug.json"
    fi
    
    # Small delay to respect API limits
    sleep 0.3
done

echo ""
echo "=================="
echo "Processing complete!"
echo "Results saved in: $TARGET_DIR/gemini_ocr_results/"
echo "Total files: $total"
echo "Successful: $((total - failed))"
echo "Failed: $failed"

# Show summary of results
if [ $failed -eq 0 ]; then
    echo "🎉 All files processed successfully!"
    echo "📁 Clean text files saved (no metadata, just extracted text)"
else
    echo "⚠️  Some files failed - check individual .txt files for details"
fi

# Show first few results as preview
echo ""
echo "Preview of first result:"
echo "========================"
first_result=$(ls gemini_ocr_results/*.txt 2>/dev/null | head -1)
if [ -n "$first_result" ]; then
    echo "File: $(basename "$first_result")"
    echo "---"
    head -10 "$first_result"
    echo "..."
fi
