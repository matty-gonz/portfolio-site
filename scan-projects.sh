#!/bin/bash
# ─────────────────────────────────────────────────────────────
# scan-projects.sh
# Scans your local media/ folder and prints the "images" array
# for each project in the new {src, caption} format —
# ready to paste into projects.json.
#
# HOW TO USE:
#   1. Upload images to R2 first (drag into R2 dashboard)
#   2. Open Terminal, cd to your Portfolio Site Files folder
#   3. Run: bash scan-projects.sh
#   4. Copy the "images": [...] block for your project
#   5. Paste into projects.json, fill in captions
#   6. deploy
# ─────────────────────────────────────────────────────────────

R2_BASE="https://media.matthewjgonzalez.me"
MEDIA_DIR="media"

if [ ! -d "$MEDIA_DIR" ]; then
  echo ""
  echo "Error: 'media/' folder not found."
  echo "Make sure you're running this from your Portfolio Site Files folder."
  exit 1
fi

echo ""
echo "── Copy each images block into projects.json and fill in captions ──"

for project_folder in "$MEDIA_DIR"/*/; do
  [ -d "$project_folder" ] || continue
  id=$(basename "$project_folder")
  [[ "$id" == .* ]] && continue

  images=()
  for img in "$project_folder"*.{jpg,jpeg,png,webp,gif,JPG,JPEG,PNG,WEBP,GIF,mp4,mov,MP4,MOV}; do
    [ -f "$img" ] || continue
    filename=$(basename "$img")
    images+=("    { \"src\": \"$R2_BASE/$id/$filename\", \"caption\": \"\" }")
  done

  echo ""
  echo "  ── $id ──"

  if [ ${#images[@]} -eq 0 ]; then
    echo "  \"images\": [],"
  else
    echo "  \"images\": ["
    for i in "${!images[@]}"; do
      if [ $i -lt $((${#images[@]} - 1)) ]; then
        echo "${images[$i]},"
      else
        echo "${images[$i]}"
      fi
    done
    echo "  ],"
  fi

done

echo ""
echo "── End ──────────────────────────────────────────────────────────────"
echo ""
echo "Fill in the \"caption\" fields, then deploy."
echo ""
