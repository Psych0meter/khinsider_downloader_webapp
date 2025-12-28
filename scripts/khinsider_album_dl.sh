#!/bin/bash

# Usage: ./khinsider_downloader.sh "ALBUM_URL"
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <album_url>"
    exit 1
fi

album_url="$1"
user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

start_time=$(date +%s)

echo "Fetching album page: $album_url"
album_html=$(curl -A "$user_agent" -s "$album_url")

# Extract album title from <title>... - Download
album_title=$(echo "$album_html" | grep -Po '<title>\K(.*?)(?= - Download)' | head -1)
if [[ -z "$album_title" ]]; then
    album_title="Unknown_Album"
fi

# Sanitize for directory and file names (improved)
sanitize_filename() {
    local input="$1"
    # Only allow ASCII (letters, numbers, space, dot, underscore, dash, parenthesis, apostrophe)
    input=$(echo "$input" | sed "s/[^A-Za-z0-9 ._()'-]/_/g")
    input=$(echo "$input" | tr ' ' '_')
    input=$(echo "$input" | sed 's/__*/_/g')
    input=$(echo "$input" | sed 's/^[._]*//;s/[._]*$//')
    echo "$input"
}

album_title_sanitized=$(sanitize_filename "$album_title")
download_path="./$album_title_sanitized"
mkdir -p "$download_path"
echo "Using album folder: $download_path"

# Find all song page links (.mp3/.flac/.m4a)
song_links=$(echo "$album_html" | grep -Po '/game-soundtracks/album/[^"]+\.(mp3|flac|m4a)' | sort -u)

if [[ -z "$song_links" ]]; then
    echo "No songs found! Check the URL."
    exit 1
fi

echo "Found $(echo "$song_links" | wc -l) unique song pages. Extracting download links..."

# Collect download links (prefer FLAC)
declare -A download_links
while read -r song_link; do
    song_page_url="https://downloads.khinsider.com$song_link"
    echo "Processing: $song_page_url"
    song_page_html=$(curl -A "$user_agent" -s "$song_page_url")
    # Find file download URLs
    file_url=$(echo "$song_page_html" | grep -Eo 'https://[^\"]+\.(flac|mp3|m4a)' | sort -u)
    for url in $file_url; do
        file_name=$(basename "$url")
        base_name="${file_name%.*}"
        ext=".${file_name##*.}"
        base_name_sane=$(sanitize_filename "$base_name")
        # Prefer FLAC
        if [[ ${download_links[$base_name_sane]+_} && "$ext" == ".flac" ]]; then
            download_links[$base_name_sane]="$url"
        elif [[ ! ${download_links[$base_name_sane]+_} ]]; then
            download_links[$base_name_sane]="$url"
        fi
    done
done <<< "$song_links"

echo "Total unique files to download: ${#download_links[@]}"

# Download loop
total_size=0
files_downloaded=0

for base_name in "${!download_links[@]}"; do
    file_url="${download_links[$base_name]}"
    ext=".${file_url##*.}"
    file_path="$download_path/${base_name}${ext}"
    echo "Downloading: $file_url -> $file_path"
    wget --user-agent="$user_agent" -q "$file_url" -O "$file_path"
    if [[ -f "$file_path" ]]; then
        file_size=$(stat --format=%s "$file_path")
        total_size=$((total_size + file_size))
        files_downloaded=$((files_downloaded + 1))
    fi
done

end_time=$(date +%s)
time_taken=$((end_time - start_time))

convert_size() {
    local size=$1
    if [ "$size" -ge $((1<<30)) ]; then
        printf "%.2f GB" "$(echo "$size/1073741824" | bc -l)"
    elif [ "$size" -ge $((1<<20)) ]; then
        printf "%.2f MB" "$(echo "$size/1048576" | bc -l)"
    elif [ "$size" -ge $((1<<10)) ]; then
        printf "%.2f KB" "$(echo "$size/1024" | bc -l)"
    else
        printf "%d Bytes" "$size"
    fi
}

total_size_formatted=$(convert_size $total_size)

echo ""
echo "=== DOWNLOAD SUMMARY ==="
echo "Album: $album_title_sanitized"
echo "Total Files Downloaded: $files_downloaded"
echo "Total Size: $total_size_formatted"
echo "Time Taken: $((time_taken/60)) min $((time_taken%60)) sec"
echo "Files saved in: $download_path"
