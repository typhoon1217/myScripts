#!/bin/bash

# DOCX to Markdown Converter with OCR Support
# Usage: ./docx_to_md.sh [options]

# Default values
TARGET_DIR="."
OUTPUT_DIR=""
RECURSIVE=false
OVERWRITE=false
EXTRACT_IMAGES=true
OCR_IMAGES=false
TESSERACT_LANG="eng"
CLEANUP_TEMP=true
IMAGE_PREFIX="image"

# Help function
show_help() {
    cat << EOF
DOCX to Markdown Converter with OCR Support

Usage: $0 [OPTIONS]

Options#!/bin/bash

# DOCX to Markdown Converter with OCR Support
# Usage: ./docx_to_md.sh [options]

# Default values
TARGET_DIR="."
OUTPUT_DIR=""
RECURSIVE=false
OVERWRITE=false
EXTRACT_IMAGES=true
OCR_IMAGES=false
TESSERACT_LANG="eng"
CLEANUP_TEMP=true
IMAGE_PREFIX="image"

# Help function
show_help() {
    cat << EOF
DOCX to Markdown Converter with OCR Support

Usage: $0 [OPTIONS]

Options:
    -d, --target-dir DIR    Directory containing DOCX files (default: current directory)
    -o, --output-dir DIR    Output directory for MD files (default: same as target-dir)
    -r, --recursive         Process DOCX files recursively in subdirectories
    -w, --overwrite         Overwrite existing output files
    -i, --extract-images    Extract images from DOCX (default: true)
    --ocr, --enable-ocr     Enable OCR processing of extracted images
    -l, --lang LANG         Tesseract language for OCR (default: eng)
    --no-cleanup           Keep temporary files
    --image-prefix PREFIX   Prefix for extracted image files (default: image)
    -h, --help              Show this help message

Examples:
    $0                                      # Convert all DOCX in current directory
    $0 -d /path/to/docs -o /path/to/output  # Custom input/output directories
    $0 -r --ocr                             # Recursive with OCR enabled
    $0 --no-cleanup -l eng+deu              # Keep temp files, multiple languages

Dependencies:
    - pandoc (for DOCX to MD conversion)
    - unzip (for image extraction)
    - tesseract-ocr (optional, for OCR)

The script will:
1. Convert DOCX files to Markdown using pandoc
2. Extract images from DOCX files (if enabled)
3. Optionally perform OCR on images and embed results as comments
4. Maintain directory structure in output
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--target-dir)
            TARGET_DIR="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -r|--recursive)
            RECURSIVE=true
            shift
            ;;
        -w|--overwrite)
            OVERWRITE=true
            shift
            ;;
        -i|--extract-images)
            EXTRACT_IMAGES=true
            shift
            ;;
        --ocr|--enable-ocr)
            OCR_IMAGES=true
            shift
            ;;
        -l|--lang)
            TESSERACT_LANG="$2"
            shift 2
            ;;
        --no-cleanup)
            CLEANUP_TEMP=false
            shift
            ;;
        --image-prefix)
            IMAGE_PREFIX="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Set output directory to target directory if not specified and convert to absolute paths
if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="$TARGET_DIR"
fi

# Convert to absolute paths
TARGET_DIR=$(cd "$TARGET_DIR" 2>/dev/null && pwd) || {
    echo "Error: Target directory does not exist: $TARGET_DIR"
    exit 1
}
OUTPUT_DIR=$(mkdir -p "$OUTPUT_DIR" && cd "$OUTPUT_DIR" && pwd)

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v pandoc &> /dev/null; then
        missing_deps+=("pandoc")
    fi
    
    if ! command -v unzip &> /dev/null; then
        missing_deps+=("unzip")
    fi
    
    if [ "$OCR_IMAGES" = true ] && ! command -v tesseract &> /dev/null; then
        missing_deps+=("tesseract-ocr")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Error: Missing dependencies:"
        printf '%s\n' "${missing_deps[@]}"
        echo ""
        echo "Install with:"
        echo "  Ubuntu/Debian: sudo apt install pandoc unzip tesseract-ocr"
        echo "  Arch: sudo pacman -S pandoc unzip tesseract"
        echo "  macOS: brew install pandoc tesseract"
        exit 1
    fi
    
    echo "Dependencies found:"
    echo "  Pandoc: $(pandoc --version | head -1)"
    if [ "$OCR_IMAGES" = true ]; then
        echo "  Tesseract: $(tesseract --version | head -1)"
    fi
}

# Find DOCX files
find_docx_files() {
    local find_cmd="find \"$TARGET_DIR\""
    
    if [ "$RECURSIVE" = false ]; then
        find_cmd="$find_cmd -maxdepth 1"
    fi
    
    find_cmd="$find_cmd -type f -iname \"*.docx\""
    
    eval "$find_cmd" | sort
}

# Get relative path
get_relative_path() {
    local file_path="$1"
    local base_dir="$2"
    echo "${file_path#$base_dir/}"
}

# Extract images from DOCX
extract_images() {
    local docx_file="$1"
    local output_dir="$2"
    local base_name="$3"
    
    local temp_dir=$(mktemp -d)
    local images_found=0
    
    # Extract DOCX (it's a ZIP file)
    if unzip -q "$docx_file" -d "$temp_dir" 2>/dev/null; then
        # Look for images in word/media directory
        local media_dir="$temp_dir/word/media"
        if [ -d "$media_dir" ]; then
            local counter=1
            for img in "$media_dir"/*; do
                if [ -f "$img" ]; then
                    local ext="${img##*.}"
                    local img_name="${IMAGE_PREFIX}_${base_name}_$(printf "%03d" $counter).$ext"
                    cp "$img" "$output_dir/$img_name"
                    echo "$img_name"
                    ((counter++))
                    ((images_found++))
                fi
            done
        fi
    fi
    
    # Cleanup temp directory
    if [ "$CLEANUP_TEMP" = true ]; then
        rm -rf "$temp_dir"
    fi
    
    return $images_found
}

# Perform OCR on image
ocr_image() {
    local image_path="$1"
    local temp_file=$(mktemp)
    
    if tesseract "$image_path" "$temp_file" -l "$TESSERACT_LANG" 2>/dev/null; then
        if [ -f "$temp_file.txt" ]; then
            cat "$temp_file.txt"
            rm -f "$temp_file.txt"
        fi
    fi
    
    rm -f "$temp_file"
}

# Process single DOCX file
process_docx() {
    local docx_path="$1"
    local rel_path
    rel_path=$(get_relative_path "$docx_path" "$TARGET_DIR")
    
    # Get filename without extension
    local basename
    basename=$(basename "$rel_path")
    local filename_no_ext="${basename%.*}"
    
    # Get directory part of relative path
    local rel_dir
    rel_dir=$(dirname "$rel_path")
    
    # Create output directory structure
    local output_subdir="$OUTPUT_DIR"
    if [ "$rel_dir" != "." ]; then
        output_subdir="$OUTPUT_DIR/$rel_dir"
        mkdir -p "$output_subdir"
    fi
    
    local output_file="$output_subdir/$filename_no_ext.md"
    
    # Check if output already exists
    if [ -f "$output_file" ] && [ "$OVERWRITE" = false ]; then
        echo "Skipping $rel_path (output exists)"
        return 0
    fi
    
    echo "Processing: $rel_path"
    
    # Convert DOCX to Markdown using pandoc
    if pandoc "$docx_path" -t markdown -o "$output_file" 2>/dev/null; then
        echo "  → Converted to: $output_file"
        
        # Extract images if enabled
        if [ "$EXTRACT_IMAGES" = true ]; then
            local images_dir="$output_subdir/${filename_no_ext}_images"
            mkdir -p "$images_dir"
            
            echo "  → Extracting images..."
            local extracted_images=()
            while IFS= read -r -d '' img_name; do
                extracted_images+=("$img_name")
            done < <(extract_images "$docx_path" "$images_dir" "$filename_no_ext" | tr '\n' '\0')
            
            if [ ${#extracted_images[@]} -gt 0 ]; then
                echo "  → Extracted ${#extracted_images[@]} images"
                
                # Add image references and OCR to markdown file
                {
                    echo ""
                    echo "## Extracted Images"
                    echo ""
                    
                    for img_name in "${extracted_images[@]}"; do
                        local img_path="$images_dir/$img_name"
                        echo "### $img_name"
                        echo ""
                        echo "![${img_name%.*}](./${filename_no_ext}_images/$img_name)"
                        echo ""
                        
                        # OCR processing (commented out by default)
                        if [ "$OCR_IMAGES" = true ]; then
                            echo "<!-- OCR Content for $img_name:"
                            local ocr_text
                            ocr_text=$(ocr_image "$img_path")
                            if [ -n "$ocr_text" ]; then
                                echo "$ocr_text"
                            else
                                echo "No text detected"
                            fi
                            echo "-->"
                        else
                            echo "<!-- OCR disabled. To enable OCR for this image, run:"
                            echo "     tesseract \"./${filename_no_ext}_images/$img_name\" - -l $TESSERACT_LANG"
                            echo "-->"
                        fi
                        echo ""
                    done
                } >> "$output_file"
            else
                echo "  → No images found"
                rmdir "$images_dir" 2>/dev/null
            fi
        fi
        
        # Add metadata to the markdown file
        {
            echo ""
            echo "---"
            echo ""
            echo "<!-- Document conversion metadata -->"
            echo "<!-- Source: $rel_path -->"
            echo "<!-- Converted: $(date) -->"
            echo "<!-- Images extracted: $EXTRACT_IMAGES -->"
            echo "<!-- OCR enabled: $OCR_IMAGES -->"
            if [ "$OCR_IMAGES" = true ]; then
                echo "<!-- OCR language: $TESSERACT_LANG -->"
            fi
            echo "<!-- Use grep to search this file for content -->"
            echo ""
        } >> "$output_file"
        
        return 0
    else
        echo "  → Error: Pandoc conversion failed"
        return 1
    fi
}

# Show statistics
show_statistics() {
    local processed="$1"
    local successful="$2"
    local failed="$3"
    
    echo ""
    echo "=== Conversion Summary ==="
    echo "DOCX files found: $processed"
    echo "Successfully converted: $successful"
    echo "Failed: $failed"
    echo "Target directory: $TARGET_DIR"
    echo "Output directory: $OUTPUT_DIR"
    echo "Images extracted: $EXTRACT_IMAGES"
    echo "OCR enabled: $OCR_IMAGES"
    if [ "$OCR_IMAGES" = true ]; then
        echo "OCR language: $TESSERACT_LANG"
    fi
    echo "=========================="
}

# Main execution
main() {
    echo "DOCX to Markdown Converter with OCR Support"
    echo "==========================================="
    echo "Target directory: $TARGET_DIR"
    echo "Output directory: $OUTPUT_DIR"
    echo "Recursive: $RECURSIVE"
    echo "Extract images: $EXTRACT_IMAGES"
    echo "OCR enabled: $OCR_IMAGES"
    echo ""
    
    check_dependencies
    
    # Find all DOCX files
    echo "Searching for DOCX files..."
    local docx_files
    mapfile -t docx_files < <(find_docx_files)
    
    if [ ${#docx_files[@]} -eq 0 ]; then
        echo "No DOCX files found in $TARGET_DIR"
        exit 0
    fi
    
    echo "Found ${#docx_files[@]} DOCX files"
    echo ""
    
    # Process each DOCX file
    local successful=0
    local failed=0
    
    for docx_file in "${docx_files[@]}"; do
        if process_docx "$docx_file"; then
            ((successful++))
        else
            ((failed++))
        fi
    done
    
    show_statistics "${#docx_files[@]}" "$successful" "$failed"
    
    if [ "$failed" -gt 0 ]; then
        exit 1
    fi
}

# Run main function
main "$@":
