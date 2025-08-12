#!/bin/bash

# Batch OCR Image Processing Script
# Usage: ./batch_ocr.sh [options]

# Default values
TARGET_DIR="/home/jungwoo/Pictures/Screenshots/"
OUTPUT_DIR="/home/jungwoo/Pictures/Screenshots/ocr/"
OUTPUT_FORMAT="txt"
TESSERACT_LANG="eng"
RECURSIVE=false
CLEANUP_IMAGES=false
OVERWRITE=false
IMAGE_EXTENSIONS=("jpg" "jpeg" "png" "tiff" "tif" "bmp" "gif" "webp")

# Help function
show_help() {
    cat << EOF
Batch OCR Image Processing Script

Usage: $0 [OPTIONS]

Options:
    -d, --target-dir DIR    Directory containing images to process (default: current directory)
    -o, --output-dir DIR    Output directory for OCR results (default: same as target-dir)
    -f, --format FORMAT     Output format: txt, pdf, hocr, tsv (default: txt)
    -l, --lang LANG         Tesseract language (default: eng)
    -r, --recursive         Process images recursively in subdirectories
    -c, --cleanup           Remove original images after successful OCR
    -w, --overwrite         Overwrite existing OCR output files
    -e, --extensions EXT    Comma-separated list of image extensions (default: jpg,jpeg,png,tiff,tif,bmp,gif,webp)
    -h, --help              Show this help message

Examples:
    $0 -d /path/to/images                      # Process all images in directory
    $0 -d ./screenshots -o ./ocr_results       # Custom input and output directories
    $0 -r -f pdf                               # Recursive processing with PDF output
    $0 -l eng+deu -w                           # Multiple languages, overwrite existing
    $0 -e "png,jpg" -c                         # Only PNG/JPG files, cleanup after

Supported image formats:
    jpg, jpeg, png, tiff, tif, bmp, gif, webp

Dependencies:
    - tesseract-ocr
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
        -f|--format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        -l|--lang)
            TESSERACT_LANG="$2"
            shift 2
            ;;
        -r|--recursive)
            RECURSIVE=true
            shift
            ;;
        -c|--cleanup)
            CLEANUP_IMAGES=true
            shift
            ;;
        -w|--overwrite)
            OVERWRITE=true
            shift
            ;;
        -e|--extensions)
            IFS=',' read -ra IMAGE_EXTENSIONS <<< "$2"
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
TARGET_DIR=$(cd "$TARGET_DIR" && pwd)
OUTPUT_DIR=$(mkdir -p "$OUTPUT_DIR" && cd "$OUTPUT_DIR" && pwd)

# Check dependencies
check_dependencies() {
    if ! command -v tesseract &> /dev/null; then
        echo "Error: tesseract-ocr is not installed"
        echo ""
        echo "Install with:"
        echo "  Ubuntu/Debian: sudo apt install tesseract-ocr"
        echo "  Arch: sudo pacman -S tesseract"
        echo "  macOS: brew install tesseract"
        exit 1
    fi
    
    echo "Tesseract version: $(tesseract --version | head -1)"
}

# Validate directories
validate_directories() {
    if [ ! -d "$TARGET_DIR" ]; then
        echo "Error: Target directory does not exist: $TARGET_DIR"
        exit 1
    fi
    
    # Output directory creation is handled above during path conversion
    echo "Target directory (absolute): $TARGET_DIR"
    echo "Output directory (absolute): $OUTPUT_DIR"
}

# Find images
find_images() {
    local find_cmd="find \"$TARGET_DIR\""
    
    if [ "$RECURSIVE" = false ]; then
        find_cmd="$find_cmd -maxdepth 1"
    fi
    
    find_cmd="$find_cmd -type f"
    
    # Build extension pattern
    local ext_pattern=""
    for ext in "${IMAGE_EXTENSIONS[@]}"; do
        if [ -z "$ext_pattern" ]; then
            ext_pattern="-iname \"*.$ext\""
        else
            ext_pattern="$ext_pattern -o -iname \"*.$ext\""
        fi
    done
    
    find_cmd="$find_cmd \\( $ext_pattern \\)"
    
    eval "$find_cmd" | sort
}

# Get relative path for maintaining directory structure
get_relative_path() {
    local file_path="$1"
    local base_dir="$2"
    echo "${file_path#$base_dir/}"
}

# Process single image
process_image() {
    local image_path="$1"
    local rel_path
    rel_path=$(get_relative_path "$image_path" "$TARGET_DIR")
    
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
    
    local output_base="$output_subdir/$filename_no_ext"
    local output_file="$output_base.$OUTPUT_FORMAT"
    
    # Check if output already exists
    if [ -f "$output_file" ] && [ "$OVERWRITE" = false ]; then
        echo "Skipping $rel_path (output exists: $output_file)"
        return 0
    fi
    
    echo "Processing: $rel_path"
    
    # Run tesseract based on format
    local success=false
    
    case $OUTPUT_FORMAT in
        txt)
            if tesseract "$image_path" "$output_base" -l "$TESSERACT_LANG" 2>/dev/null; then
                success=true
            fi
            ;;
        pdf)
            if tesseract "$image_path" "$output_base" -l "$TESSERACT_LANG" pdf 2>/dev/null; then
                success=true
            fi
            ;;
        hocr)
            if tesseract "$image_path" "$output_base" -l "$TESSERACT_LANG" hocr 2>/dev/null; then
                success=true
            fi
            ;;
        tsv)
            if tesseract "$image_path" "$output_base" -l "$TESSERACT_LANG" tsv 2>/dev/null; then
                success=true
            fi
            ;;
        *)
            echo "Warning: Unknown format $OUTPUT_FORMAT for $rel_path, using txt"
            OUTPUT_FORMAT="txt"
            output_file="$output_base.txt"
            if tesseract "$image_path" "$output_base" -l "$TESSERACT_LANG" 2>/dev/null; then
                success=true
            fi
            ;;
    esac
    
    # Check results
    if [ "$success" = true ]; then
        if [ -f "$output_file" ]; then
            echo "  → Success: $output_file"
            
            # Show word count for txt files
            if [ "$OUTPUT_FORMAT" = "txt" ]; then
                local word_count
                word_count=$(wc -w < "$output_file" 2>/dev/null || echo "0")
                echo "  → Extracted $word_count words"
            fi
            
            # Cleanup original image if requested
            if [ "$CLEANUP_IMAGES" = true ]; then
                rm "$image_path"
                echo "  → Cleaned up original image"
            fi
            
            return 0
        else
            echo "  → Error: Output file not created"
            return 1
        fi
    else
        echo "  → Error: Tesseract failed"
        return 1
    fi
}

# Show statistics
show_statistics() {
    local processed="$1"
    local successful="$2"
    local failed="$3"
    
    echo ""
    echo "=== Processing Summary ==="
    echo "Images found: $processed"
    echo "Successfully processed: $successful"
    echo "Failed: $failed"
    echo "Output directory: $OUTPUT_DIR"
    echo "Output format: $OUTPUT_FORMAT"
    echo "Language: $TESSERACT_LANG"
    echo "=========================="
}

# Main execution
main() {
    echo "Batch OCR Image Processing Script"
    echo "================================="
    echo "Target directory: $TARGET_DIR"
    echo "Output directory: $OUTPUT_DIR"
    echo "Recursive: $RECURSIVE"
    echo "Extensions: ${IMAGE_EXTENSIONS[*]}"
    echo ""
    
    check_dependencies
    validate_directories
    
    # Find all images
    echo "Searching for images..."
    local images
    mapfile -t images < <(find_images)
    
    if [ ${#images[@]} -eq 0 ]; then
        echo "No images found in $TARGET_DIR"
        echo "Supported extensions: ${IMAGE_EXTENSIONS[*]}"
        exit 0
    fi
    
    echo "Found ${#images[@]} images"
    echo ""
    
    # Process each image
    local successful=0
    local failed=0
    
    for image in "${images[@]}"; do
        if process_image "$image"; then
            ((successful++))
        else
            ((failed++))
        fi
    done
    
    show_statistics "${#images[@]}" "$successful" "$failed"
    
    if [ "$failed" -gt 0 ]; then
        exit 1
    fi
}

# Run main function
main "$@"
