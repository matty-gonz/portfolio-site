#!/bin/bash
# ─────────────────────────────────────────────────────────────
# scan-projects.sh
# Lists files in your R2 bucket folders and prints the
# "images" array for each project — ready to paste into
# projects.json.
#
# HOW TO USE:
#   1. Open Terminal
#   2. cd to your Portfolio Site Files folder
#   3. Run: bash scan-projects.sh
#   4. Find your project, copy the "images": [...] block,
#      paste it into the matching entry in projects.json
#
# ADDING NEW IMAGES:
#   1. Upload images to R2 → portfolio-media → your-project-id/
#   2. Run this script
#   3. Copy the updated images array into projects.json
#   4. deploy
# ─────────────────────────────────────────────────────────────

R2_BASE="https://media.matthewjgonzalez.me"

# ── Check for rclone (used to list R2 contents) ──────────────
# If you don't have rclone set up, the script falls back to
# listing your local media/ folder instead.

if command -v rclone &> /dev/null && rclone listremotes | grep -q "r2:"; then
  USE_R2=true
  REMOTE="r2:portfolio-media"
else
  USE_R2=false
  MEDIA_DIR="media"
fi

echo ""
echo "── Copy the images array for each project into projects.json ──"

if [ "$USE_R2" = true ]; then
  # ── R2 mode — list objects from bucket ──────────────────────
  for folder in $(rclone lsd "$REMOTE" --format "p" | awk '{print $NF}'); do
    [[ "$folder" == .* ]] && continue
    echo ""
    echo "  ── $folder ──"
    images=()
    while IFS= read -r file; do
      [ -z "$file" ] && continue
      images+=("\"$R2_BASE/$folder/$file\"")
    done < <(rclone ls "$REMOTE/$folder" | awk '{print $NF}')

    if [ ${#images[@]} -eq 0 ]; then
      echo "  \"images\": [],"
    else
      echo "  \"images\": ["
      for i in "${!images[@]}"; do
        if [ $i -lt $((${#images[@]} - 1)) ]; then
          echo "    ${images[$i]},"
        else
          echo "    ${images[$i]}"
        fi
      done
      echo "  ],"
    fi
  done

else
  # ── Local fallback — use media/ folder ──────────────────────
  if [ ! -d "$MEDIA_DIR" ]; then
    echo ""
    echo "Error: No 'media/' folder found and rclone is not configured."
    echo "Upload images to R2 and run this script, or set up rclone."
    exit 1
  fi

  for project_folder in "$MEDIA_DIR"/*/; do
    [ -d "$project_folder" ] || continue
    id=$(basename "$project_folder")
    [[ "$id" == .* ]] && continue

    images=()
    for img in "$project_folder"*.{jpg,jpeg,png,webp,gif,JPG,JPEG,PNG,WEBP,GIF,mp4,mov,MP4,MOV}; do
      [ -f "$img" ] || continue
      images+=("\"$R2_BASE/$id/$(basename "$img")\"")
    done

    echo ""
    echo "  ── $id ──"
    echo "  NOTE: Using local media/ folder. Upload these files to R2 first."

    if [ ${#images[@]} -eq 0 ]; then
      echo "  \"images\": [],"
    else
      echo "  \"images\": ["
      for i in "${!images[@]}"; do
        if [ $i -lt $((${#images[@]} - 1)) ]; then
          echo "    ${images[$i]},"
        else
          echo "    ${images[$i]}"
        fi
      done
      echo "  ],"
    fi
  done
fi

echo ""
echo "── End ─────────────────────────────────────────────────────────"
echo ""
echo "Paste each \"images\": [...] block into the matching entry in projects.json"
echo "then run: deploy"
echo ""
