#!/bin/bash

# Usage: ./khinsider_downloader.sh "ALBUM_URL"
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <album_url>"
    exit 1
fi

album_url="$1"
user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

start_script_time=$(date +%s)

echo "Fetching album page: $album_url"
album_html=$(curl -A "$user_agent" -s "$album_url")

# FIXED: Standardized if-statement for title extraction
album_title=$(echo "$album_html" | grep -Po '<title>\K(.*?)(?= - Download)' | head -1)
if [[ -z "$album_title" ]]; then
    album_title="Unknown_Album"
fi

sanitize_filename() {
    local input="$1"
    input=$(echo "$input" | sed "s/[^A-Za-z0-9 ._()'-]/_/g")
    input=$(echo "$input" | tr ' ' '_')
    input=$(echo "$input" | sed 's/__*/_/g' | sed 's/^[._]*//;s/[._]*$//')
    echo "$input"
}

album_title_sanitized=$(sanitize_filename "$album_title")
download_path="./$album_title_sanitized"
mkdir -p "$download_path"

song_links=$(echo "$album_html" | grep -Po '/game-soundtracks/album/[^"]+\.(mp3|flac|m4a)' | sort -u)

if [[ -z "$song_links" ]]; then
    echo "No songs found! Check the URL."
    exit 1
fi

echo "Extracting download links..."
declare -A download_links
while read -r song_link; do
    song_page_url="https://downloads.khinsider.com$song_link"
    song_page_html=$(curl -A "$user_agent" -s "$song_page_url")
    file_urls=$(echo "$song_page_html" | grep -Eo 'https://[^\"]+\.(flac|mp3|m4a)' | sort -u)
    for url in $file_urls; do
        file_name=$(basename "$url")
        base_name_sane=$(sanitize_filename "${file_name%.*}")
        ext=".${file_name##*.}"
        
        # Logic: If FLAC exists, keep it. Otherwise, take what is available.
        if [[ ${download_links[$base_name_sane]+_} ]]; then
            if [[ "$ext" == ".flac" ]]; then
                download_links[$base_name_sane]="$url"
            fi
        else
            download_links[$base_name_sane]="$url"
        fi
    done
done <<< "$song_links"

# --- DOWNLOAD LOOP WITH PROGRESS BAR ---
total_files=${#download_links[@]}
current_idx=0
total_size=0
files_downloaded=0
download_start_time=$(date +%s)

echo "Starting download of $total_files unique tracks..."
echo ""

for base_name in "${!download_links[@]}"; do
    ((current_idx++))
    file_url="${download_links[$base_name]}"
    ext=".${file_url##*.}"
    file_path="$download_path/${base_name}${ext}"

    # Calculate Progress & ETA
    percent=$((current_idx * 100 / total_files))
    completed_bar=$((percent / 2))
    remaining_bar=$((50 - completed_bar))
    
    now=$(date +%s)
    elapsed=$((now - download_start_time))
    
    if [ $current_idx -gt 1 ]; then
        # ETA Calculation: (Time Spent / Files Done) * Files Remaining
        eta_seconds=$(( (elapsed * (total_files - current_idx)) / current_idx ))
        eta_fmt=$(printf "%02dm %02ds" $((eta_seconds/60)) $((eta_seconds%60)))
    else
        eta_fmt="Calculating..."
    fi

    # UI Update: \r moves cursor to the start of the line, allowing the bar to update in place
    printf "\rProgress: [%-50s] %d%% (%d/%d) ETA: %s" \
        "$(printf '#%.0s' $(seq 1 $completed_bar 2>/dev/null))" \
        "$percent" "$current_idx" "$total_files" "$eta_fmt"

    wget --user-agent="$user_agent" -q "$file_url" -O "$file_path"
    
    if [[ -f "$file_path" ]]; then
        file_size=$(stat --format=%s "$file_path")
        total_size=$((total_size + file_size))
        files_downloaded=$((files_downloaded + 1))
    fi
done

echo -e "\n" # Move to new line after completion

# --- SUMMARY SECTION ---
convert_size() {
    local size=$1
    if [ "$size" -ge 1073741824 ]; then
        # Gigabytes
        printf "%d.%02d GB" $((size / 1073741824)) $(((size % 1073741824) * 100 / 1073741824))
    elif [ "$size" -ge 1048576 ]; then
        # Megabytes
        printf "%d.%02d MB" $((size / 1048576)) $(((size % 1048576) * 100 / 1048576))
    elif [ "$size" -ge 1024 ]; then
        # Kilobytes
        printf "%d.%02d KB" $((size / 1024)) $(((size % 1024) * 100 / 1024))
    else
        printf "%d Bytes" "$size"
    fi
}

end_script_time=$(date +%s)
total_time_taken=$((end_script_time - start_script_time))

echo "=== DOWNLOAD SUMMARY ==="
echo "Album: $album_title_sanitized"
echo "Files: $files_downloaded / $total_files"
echo "Size:  $(convert_size $total_size)"
echo "Time:  $((total_time_taken/60)) min $((total_time_taken%60)) sec"
echo "Saved: $download_path"
 
end_script_time=$(date +%s)
total_time_taken=$((end_script_time - start_script_time))

echo "=== DOWNLOAD SUMMARY ==="
echo "Album: $album_title_sanitized"
echo "Files: $files_downloaded / $total_files"
echo "Size:  $(convert_size $total_size)"
echo "Time:  $((total_time_taken/60)) min $((total_time_taken%60)) sec"
echo "Saved: $download_path"
