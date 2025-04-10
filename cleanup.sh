#!/bin/bash

# Set the threshold for seeding duration (in days)
SEEDING_DAYS=14

# Set the directory to search for files and the target archive directory. If only one search directory just delete extras.
SEARCH_DIR=("/path/to/seed/source/1" "/path/to/seed/source/2" "/path/to/seed/source/3")
ARCHIVE_DIR="/path/to/library/media"
# Define the name of your Transmission container, address:port, and cross-seed label.
TRANSMISSION="transmission-vpn"
ADDRESS="localhost:9091"
CROSS_SEED_LABEL="cross-seed"
# Set the dry-run option (use -d to enable dry run mode). Dry run mode will tell you which seeds would be deleted, but doesn't actually do it.
DRY_RUN=false
# Define the minimum file size to review. If a file is below this size (in MB), then the script will not look to remove associated seeds.
MIN_SIZE=100

# Parse command-line arguments
while getopts "d" opt; do
  case $opt in
    d) DRY_RUN=true;;  # If -d is passed, set DRY_RUN to true
    *) echo "Usage: $0 [-d]"; exit 1;;
  esac
done

# Summary file location
SUMMARY_FILE="./deletion_summary.txt"

# Function to check if a file has a hardlink in the archive directory
has_hardlink_in_archive() {
    local file="$1"
    local file_inode
    file_inode=$(stat --format='%i' "$file")
    # Look for other files with the same inode in the archive dir
    find "$ARCHIVE_DIR" -type f -samefile "$file" -print -quit | grep -q .

    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Function to get the torrent ID for a given file using full file paths
get_torrent_id_for_file() {
    local file=$1
    local basename=$(basename "$file")
    # Loop through all torrents and match basenames
    for torrent_id in $(docker exec transmission-vpn transmission-remote 127.0.0.1:9092 -l | awk '{print $1}'); do
        if docker exec '$TRANSMISSION' transmission-remote '$ADDRESS' -t "$torrent_id" -f | grep -q "$basename"; then
            echo "$torrent_id"
            return 0
        fi
    done
    
    echo "DEBUG: No torrent found for file '$basename'. Skipping."
    return 1
}

# Function to check seeding duration for a torrent
get_seeding_duration() {
    local torrent_id=$1
    # Get seeding time in seconds
    seeding_duration=$(docker exec '$TRANSMISSION' transmission-remote '$ADDRESS' -t $torrent_id -i | grep "Seeding Time" | sed -n 's/.*(\([0-9]\+\) seconds).*/\1/p')
    # Convert seeding duration to seconds (if not already in seconds)
    seeding_duration=$((seeding_duration))
    # Return the valid seeding duration
    echo "$seeding_duration"
}



# Function to check if a torrent is a cross-seed
is_cross_seed() {
    local torrent_id=$1
    docker exec '$TRANSMISSION' transmission-remote '$ADDRESS' -t "$torrent_id" -i | grep -q '$CROSS_SEED_LABEL'
    return $?
}

SEEDING_SECONDS=$(($SEEDING_DAYS * 86400))

# Define archive extensions
ARCHIVE_EXTENSIONS="\.rar$|\.r[0-9]{2}$"


# Loop through files in the SEARCH_DIR
find "${SEARCH_DIR[@]}" -type f -size +'$MIN_SIZE'M| while read -r file; do
    # Skip archive files if in dry-run mode
#    if "$file" =~ $ARCHIVE_EXTENSIONS; then
#        echo "Skipping archive file '$file'."
#        continue
#    fi
    echo "DEBUG: Reviewing file '$file'..."

    # Check if the file has a hardlink in the archive directory
    if ! has_hardlink_in_archive "$file"; then
        echo "DEBUG: File '$file' doesn't have a hardlink in the archive directory."

        # Get associated torrents for this file
        torrent_id=$(get_torrent_id_for_file "$file")
        
        if [ -n "$torrent_id" ]; then
            echo "DEBUG: Found torrent ID '$torrent_id' for file '$file'."

            # Get the seeding duration
            seeding_duration=$(get_seeding_duration "$torrent_id")
            echo "DEBUG: Seeding duration for '$file': $seeding_duration"

            # Check if torrent is cross-seed (skip seeding duration check)
            if is_cross_seed "$torrent_id"; then
                echo "DEBUG: Torrent '$torrent_id' is marked as cross-seed, will be deleted."
                echo "$(date): Torrent '$torrent_id' - '$file' deleted for being cross-seed" >> "$SUMMARY_FILE"
                if [ "$DRY_RUN" = false ]; then
                    docker exec '$TRANSMISSION' transmission-remote '$ADDRESS' -t "$torrent_id" --remove-and-delete
                fi
            elif [ "$seeding_duration" -ge "$SEEDING_SECONDS" ]; then
                # Check if torrent has seeded for more than the configured SEEDING_DAYS
                echo "DEBUG: Torrent '$torrent_id' has seeded for $seeding_duration days, eligible for deletion."
                echo "$(date): Torrent '$torrent_id' - '$file' deleted for being over $SEEDING_DAYS days seeding" >> "$SUMMARY_FILE"
                if [ "$DRY_RUN" = false ]; then
                    docker exec '$TRANSMISSION' transmission-remote '$ADDRESS' -t "$torrent_id" --remove-and-delete
                fi
            else
                echo "DEBUG: Torrent '$torrent_id' hasn't seeded for $SEEDING_DAYS days, skipping."
            fi
        else
            echo "DEBUG: No matching torrent found for file '$file'."
        fi
    #else
        #echo "DEBUG: File '$file' has a hardlink in the archive directory, skipping."
    fi
done

echo "DEBUG: Script completed."
