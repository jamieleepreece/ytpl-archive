#!/bin/sh

# Usage:
#   ./dl.sh [--force]                 sync every playlist in playlists.txt
#   ./dl.sh [--force] URL [FOLDER]    sync one playlist
#
# --force ignores the download archive, so any video missing from its
# folder is downloaded again. Files already on disk are kept.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLAYLISTS_FILE="$SCRIPT_DIR/playlists.txt"
DOWNLOADS_DIR="$SCRIPT_DIR/downloads"
STATE_DIR="$DOWNLOADS_DIR/.state"

mkdir -p "$STATE_DIR"

sanitize_filename() {
  printf '%s' "$1" | tr '/\\:*?"<>|' '_'
}

playlist_id() {
  printf '%s' "$1" | sed -n 's/.*[?&]list=\([^&]*\).*/\1/p'
}

# Print the folder name playlists.txt gives this playlist ID, if any.
listed_folder() {
  [ -f "$PLAYLISTS_FILE" ] || return
  grep -v '^[[:space:]]*#' "$PLAYLISTS_FILE" | while read -r url folder; do
    if [ -n "$url" ] && [ "$(playlist_id "$url")" = "$1" ]; then
      printf '%s' "$folder"
      break
    fi
  done
}

sync_playlist() {
  PLAYLIST="$1"
  PLAYLIST_NAME="$2"
  PLAYLIST_ID="$(playlist_id "$PLAYLIST")"

  if [ -z "$PLAYLIST_ID" ]; then
    echo "Skipping, not a playlist URL: $PLAYLIST" >&2
    return 1
  fi

  [ -z "$PLAYLIST_NAME" ] && PLAYLIST_NAME="$(listed_folder "$PLAYLIST_ID")"
  if [ -z "$PLAYLIST_NAME" ]; then
    PLAYLIST_NAME="$(sanitize_filename "$(yt-dlp --flat-playlist --playlist-items 1 --print '%(playlist_title)s' "$PLAYLIST")")"
  fi
  if [ -z "$PLAYLIST_NAME" ]; then
    echo "Skipping, couldn't get a title for: $PLAYLIST" >&2
    return 1
  fi

  DOWNLOAD_DIR="$DOWNLOADS_DIR/$PLAYLIST_NAME"
  mkdir -p "$DOWNLOAD_DIR"
  echo "=== $PLAYLIST_NAME ==="

  # yt-dlp rebuilds the archive as it goes, including files already on disk.
  [ "$FORCE" = 1 ] && rm -f "$STATE_DIR/$PLAYLIST_ID.archive.txt"

  yt-dlp \
    --download-archive "$STATE_DIR/$PLAYLIST_ID.archive.txt" \
    -w \
    --max-filesize 2G \
    -o "$DOWNLOAD_DIR/%(playlist_index)02d - %(title)s [%(id)s].%(ext)s" \
    -f "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720][ext=mp4]" \
    --merge-output-format mp4 \
    "$PLAYLIST"

  TMP_PLAYLIST_LIST="$STATE_DIR/.playlist_order.$$"

  yt-dlp --flat-playlist --print '%(playlist_index)02d\t%(id)s\t%(title)s' \
    "$PLAYLIST" > "$TMP_PLAYLIST_LIST"

  while IFS=$(printf '\t') read -r index id title; do
    [ -z "$index" ] && continue

    for file in "$DOWNLOAD_DIR"/*; do
      [ -f "$file" ] || continue
      case "$(basename "$file")" in
        *"[$id]"*)
          ext="${file##*.}"
          new_name="$(printf '%s - %s [%s].%s' "$index" "$(sanitize_filename "$title")" "$id" "$ext")"
          if [ "$file" != "$DOWNLOAD_DIR/$new_name" ] && [ ! -e "$DOWNLOAD_DIR/$new_name" ]; then
            mv "$file" "$DOWNLOAD_DIR/$new_name"
          fi
          ;;
      esac
    done
  done < "$TMP_PLAYLIST_LIST"

  rm -f "$TMP_PLAYLIST_LIST"

  {
    printf '#EXTM3U\n'
    printf '#PLAYLIST:%s\n' "$PLAYLIST_NAME"
    find "$DOWNLOAD_DIR" -maxdepth 1 -type f \( -name '*.mp4' -o -name '*.mkv' -o -name '*.mov' \) | sed "s#^$DOWNLOAD_DIR/##" | LC_ALL=C sort
  } > "$DOWNLOAD_DIR/$PLAYLIST_NAME.m3u"
}

FORCE=0
for arg in "$@"; do
  shift
  case "$arg" in
    --force) FORCE=1 ;;
    *) set -- "$@" "$arg" ;;
  esac
done

if [ -n "$1" ]; then
  sync_playlist "$1" "$2"
else
  if [ ! -f "$PLAYLISTS_FILE" ]; then
    echo "No $PLAYLISTS_FILE; copy playlists.example.txt or pass a playlist URL." >&2
    exit 1
  fi
  grep -v '^[[:space:]]*#' "$PLAYLISTS_FILE" | while read -r url folder; do
    [ -z "$url" ] && continue
    sync_playlist "$url" "$folder" < /dev/null
  done
fi
