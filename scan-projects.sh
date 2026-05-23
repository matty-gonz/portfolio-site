#!/bin/bash
# ─────────────────────────────────────────────────────────────
# scan-projects.sh
# Scans assets/images/ and prints the "images" array for each
# project folder — ready to copy-paste into projects.json.
#
# HOW TO RUN:
#   1. Open Terminal
#   2. cd to your Portfolio Site Files folder:
#        cd /Users/mattyg/Documents/Bootstrap\ Studio/Portfolio\ Site\ Files
#   3. Run:
#        bash scan-projects.sh
#   4. Find your project in the output, copy the "images": [...] 
#      block, and paste it into the matching entry in projects.json
# ─────────────────────────────────────────────────────────────

IMAGES_DIR="assets/images"

if [ ! -d "$IMAGES_DIR" ]; then
  echo "Error: '$IMAGES_DIR' folder not found."
  echo "Make sure you're running this from your Portfolio Site Files folder."
  exit 1
fi

echo ""
echo "── Copy the images array for each project into projects.json ──"

for project_folder in "$IMAGES_DIR"/*/; do
  [ -d "$project_folder" ] || continue

  id=$(basename "$project_folder")

  # skip .DS_Store folders
  [[ "$id" == .* ]] && continue

  # collect image files
  images=()
  for img in "$project_folder"*.{jpg,jpeg,png,webp,gif,JPG,JPEG,PNG,WEBP,GIF}; do
    [ -f "$img" ] || continue
    images+=("\"assets/images/$id/$(basename "$img")\"")
  done

  echo ""
  echo "  ── $id ──"

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

echo ""
echo "── End ─────────────────────────────────────────────────────────"
echo ""