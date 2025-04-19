#!/bin/bash

# User configuration
SEEDING_DAYS=14
SEARCH_DIR=("/path/to/search/directory/1" "/path/to/search/directory/2" "/path/to/search/directory/3")
ARCHIVE_DIR="/volume1/data/media"
TRANSMISSION="transmission-vpn"
ADDRESS="localhost:9091"
CROSS_SEED_LABEL="cross-seed"
DRY_RUN=false
MIN_SIZE=100
SUMMARY_FILE="/path/to/deletion_summary.txt"

while getopts "d" opt; do
  case $opt in
    d) DRY_RUN=true;;
    *) echo "Usage: $0 [-d]"; exit 1;;
  esac
done

get_all_torrents() {
    docker exec "$TRANSMISSION" transmission-remote "$ADDRESS" -l | awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1}'
}

get_torrent_details() {
    local id="$1"
    docker exec "$TRANSMISSION" transmission-remote "$ADDRESS" -t "$id" -i
}

# Function to get all torrent IDs associated with a file
get_associated_torrents_for_file() {
    local file_basename
    file_basename=$(basename "$1")
    local ids=()

    for id in $(docker exec $TRANSMISSION transmission-remote $ADDRESS -l | awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1}'); do
        if docker exec $TRANSMISSION transmission-remote $ADDRESS -t "$id" -f | grep -q "$file_basename"; then
            ids+=("$id")
        fi
    done

    echo "${ids[@]}"
}

# Function to find the primary torrent among a set of IDs
find_primary_torrent() {
    local ids=("$@")
    for id in "${ids[@]}"; do
        label=$(docker exec $TRANSMISSION transmission-remote $ADDRESS -t "$id" -i | grep "Location:" | awk -F ': ' '{print $2}' | xargs)
        if [[ "$label" == *"TV"* || "$label" == *"Movies"* ]]; then
            echo "$id"
            return
        fi
    done
    # No primary found
    echo ""
}

get_torrent_label() {
    local id="$1"
    get_torrent_details "$id" | grep -E "Label: " | awk -F': ' '{print $2}' | tr -d '\r'
}

get_ratio() {
    local id="$1"
    get_torrent_details "$id" | grep "Ratio:" | awk -F': ' '{print $2}' | awk '{print $1}'
}

has_hardlink_in_archive() {
    local file="$1"
    find "$ARCHIVE_DIR" -type f -samefile "$file" -print -quit | grep -q .
}

# Main processing loop
today_day=$(date +%d)

find "${SEARCH_DIR[@]}" -type f -size +${MIN_SIZE}M | while read -r file; do
    echo "DEBUG: Reviewing '$file'"

    [[ "$DRY_RUN" == true && "$file" =~ \.r[0-9]{2}$|\.rar$ ]] && {
        echo "DEBUG: Skipping archive file '$file'"
        continue
    }

    if has_hardlink_in_archive "$file"; then
        echo "DEBUG: File '$file' has hardlink in archive, skipping."
        continue
    fi

# Get associated torrent IDs
associated_ids=($(get_associated_torrents_for_file "$file"))
if [ ${#associated_ids[@]} -eq 0 ]; then
    echo "DEBUG: No associated torrents found for '$file'. Skipping."
    continue
fi
echo "DEBUG: Found associated torrents: ${associated_ids[*]}"

# Find the primary torrent (TV or Movies)
primary_id=$(find_primary_torrent "${associated_ids[@]}")
if [ -z "$primary_id" ]; then
    echo "DEBUG: No primary torrent found. Skipping '$file'."
    continue
fi

# Calculate seeding duration using added date
added_date=$(docker exec $TRANSMISSION transmission-remote $ADDRESS -t "$primary_id" -i | grep "Date added" | sed -n 's/.*: //p')
if [[ -n "$added_date" ]]; then
    added_day=$(date -d "$added_date" +%s)
    current_day=$(date +%s)
    seeding_duration_seconds=$((current_day - added_day))
    seeding_duration_days=$(($seeding_duration_seconds/86400))
else
    seeding_duration_days=0
fi
echo "DEBUG: Primary seeding duration: $seeding_duration_days days"

# Get ratio
ratio_str=$(docker exec $TRANSMISSION transmission-remote $ADDRESS -t "$primary_id" -i | grep "Ratio:" | awk '{print $2}' | xargs)
ratio_int=$(echo "$ratio_str" | awk -F. '{printf("%d\n", $1)}')
ratio_frac=$(echo "$ratio_str" | awk -F. '{printf("%d\n", $2)}')
ratio_over_one=false
if (( ratio_int > 1 )) || (( ratio_int == 1 && ratio_frac > 0 )); then
    ratio_over_one=true
fi
echo "DEBUG: Primary ratio: $ratio_str"

# Now loop through associated torrents to decide deletion
for torrent_id in "${associated_ids[@]}"; do
    label=$(docker exec $TRANSMISSION transmission-remote $ADDRESS -t "$torrent_id" -i | grep "Location:" | awk -F ': ' '{print $2}' | xargs)

    if [[ "$label" == *"$CROSS_SEED_LABEL"* ]]; then
        echo "DEBUG: Torrent $torrent_id is a cross-seed. Deleting."
        echo "$(date): Torrent $torrent_id - '$file' deleted as cross-seed" >> "$SUMMARY_FILE"
        [ "$DRY_RUN" = false ] && docker exec $TRANSMISSION transmission-remote $ADDRESS -t "$torrent_id" --remove-and-delete
    elif [[ "$seeding_duration_days" -ge "$SEEDING_DAYS" || "$ratio_over_one" = true ]]; then
        echo "DEBUG: Torrent $torrent_id exceeds age or ratio. Deleting."
        echo "$(date): Torrent $torrent_id - '$file' deleted after $seeding_duration_days days or ratio $ratio_str" >> "$SUMMARY_FILE"
        [ "$DRY_RUN" = false ] && docker exec $TRANSMISSION transmission-remote $ADDRESS -t "$torrent_id" --remove-and-delete
    else
        echo "DEBUG: Torrent $torrent_id does not meet deletion criteria. Skipping."
        remains=$((SEEDING_DAYS - seeding_duration_days))
        echo "$(date): Torrent $torrent_id - '$(basename "$file")' will be deleted after $remains more days of seeding" >> "$SUMMARY_FILE"
    fi
done

done

echo "DEBUG: Script completed."
