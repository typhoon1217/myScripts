#!/bin/bash

# Script to process all PNG files in specified directory with Ollama LLaVA
# Usage: ./process-screenshots.sh [target_directory]
# If no directory specified, uses current directory

# Check and set target directory
if [ $# -eq 0 ]; then
    TARGET_DIR="/home/jungwoo/Pictures/Screenshots"
    echo -e "${BLUE}No directory specified, using current directory${NC}"
elif [ $# -eq 1 ]; then
    TARGET_DIR="$1"
    if [ ! -d "$TARGET_DIR" ]; then
        echo -e "${RED}Error: Directory '$TARGET_DIR' does not exist${NC}"
        exit 1
    fi
    echo -e "${BLUE}Using target directory: $TARGET_DIR${NC}"
else
    echo -e "${RED}Usage: $0 [target_directory]${NC}"
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0                    # Process current directory"
    echo "  $0 ~/Screenshots      # Process ~/Screenshots directory"
    echo "  $0 /path/to/images    # Process specific directory"
    exit 1
fi

# Change to target directory
cd "$TARGET_DIR" || {
    echo -e "${RED}Error: Cannot access directory '$TARGET_DIR'${NC}"
    exit 1
}
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Docker is running
if ! docker ps &> /dev/null; then
    echo -e "${RED}Error: Docker is not running or accessible${NC}"
    exit 1
fi

# Check if Ollama container is running
if ! docker ps --format "table {{.Names}}" | grep -q "ollama"; then
    echo -e "${RED}Error: Ollama container is not running${NC}"
    echo "Start it with: docker run -d --name ollama -p 11434:11434 -v ollama:/root/.ollama ollama/ollama"
    exit 1
fi

# Check if LLaVA model is available
echo -e "${BLUE}Checking if LLaVA 7B model is available...${NC}"
if ! docker exec ollama ollama list | grep -q "llava:7b"; then
    echo -e "${YELLOW}LLaVA 7B not found. Checking for other LLaVA versions...${NC}"
    if docker exec ollama ollama list | grep -q "llava"; then
        MODEL=$(docker exec ollama ollama list | grep "llava" | head -1 | awk '{print $1}')
        echo -e "${GREEN}Found model: $MODEL${NC}"
    else
        echo -e "${RED}No LLaVA model found. Please install with:${NC}"
        echo "docker exec -it ollama ollama pull llava:7b"
        exit 1
    fi
else
    MODEL="llava:7b"
    echo -e "${GREEN}Found LLaVA 7B model${NC}"
fi

# Create output directory
OUTPUT_DIR="ocr_results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"

# Find all PNG files in target directory
PNG_FILES=(*.png)

# Check if any PNG files exist
if [ ! -e "${PNG_FILES[0]}" ]; then
    echo -e "${RED}No PNG files found in directory: $TARGET_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}Found ${#PNG_FILES[@]} PNG files to process in: $TARGET_DIR${NC}"
echo -e "${BLUE}Results will be saved in: $OUTPUT_DIR${NC}"
echo

# Process each PNG file
for i in "${!PNG_FILES[@]}"; do
    file="${PNG_FILES[$i]}"
    
    echo -e "${YELLOW}Processing ($((i+1))/${#PNG_FILES[@]}): $file${NC}"
    
    # Create output filename
    base_name=$(basename "$file" .png)
    output_file="$OUTPUT_DIR/${base_name}_ocr.txt"
    
    # Process image with Ollama
    echo "Processing image: $file" > "$output_file"
    echo "Timestamp: $(date)" >> "$output_file"
    echo "Model: $MODEL" >> "$output_file"
    echo "----------------------------------------" >> "$output_file"
    echo >> "$output_file"
    
    # Send image to Ollama and capture output
    echo -e "${BLUE}  Sending to Ollama...${NC}"
    
    # Use docker exec method (more reliable for large images)
    if timeout 300 docker exec -i ollama ollama run "$MODEL" "Please extract all text from this image. Be thorough and maintain formatting where possible. Only return the extracted text, no commentary." < "$file" >> "$output_file" 2>&1; then
        echo -e "${GREEN}  ✓ Completed${NC}"
    else
        echo "Error: Processing failed or timed out" >> "$output_file"
        echo -e "${RED}  ✗ Failed${NC}"
    fi
    
    echo >> "$output_file"
    echo "========================================" >> "$output_file"
    echo
done

echo -e "${GREEN}All files processed!${NC}"
echo -e "${BLUE}Results saved in: $OUTPUT_DIR${NC}"

# Create summary
echo -e "${YELLOW}Creating summary...${NC}"
summary_file="$OUTPUT_DIR/summary.txt"
echo "OCR Processing Summary" > "$summary_file"
echo "=====================" >> "$summary_file"
echo "Date: $(date)" >> "$summary_file"
echo "Target directory: $TARGET_DIR" >> "$summary_file"
echo "Model used: $MODEL" >> "$summary_file"
echo "Files processed: ${#PNG_FILES[@]}" >> "$summary_file"
echo "Output directory: $OUTPUT_DIR" >> "$summary_file"
echo >> "$summary_file"
echo "Processed files:" >> "$summary_file"
for file in "${PNG_FILES[@]}"; do
    echo "- $file" >> "$summary_file"
done

echo -e "${GREEN}Summary saved: $summary_file${NC}"
echo -e "${BLUE}Done!${NC}"
