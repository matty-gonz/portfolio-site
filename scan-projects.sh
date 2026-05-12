#!/bin/bash
# ─────────────────────────────────────────────────────────────
# scan-projects.sh
# Run this whenever you add a new project image folder.
# It scans assets/images/ and prints a ready-to-paste
# projects.json entry for each folder it finds.
#
# HOW TO RUN:
#   1. Open Terminal
#   2. cd to your Portfolio Site Files folder:
#        cd ~/Users/mattyg/Documents/Bootstrap\ Studio/Portfolio\ Site\ Files
#   3. Run:
#        bash scan-projects.sh
#   4. Copy the output and paste it into projects.json
# ─────────────────────────────────────────────────────────────

IMAGES_DIR="assets/images"

if [ ! -d "$IMAGES_DIR" ]; then
  echo "Error: '$IMAGES_DIR' folder not found."
  echo "Make sure you're running this from your Portfolio Site Files folder."
  exit 1
fi

echo ""
echo "── Paste these blocks into projects.json ──────────────────"
echo ""

for project_folder in "$IMAGES_DIR"/*/; do
  # get just the folder name (e.g. "rc-derby")
  id=$(basename "$project_folder")

  # collect image files (jpg, jpeg, png, webp, gif)
  images=()
  for img in "$project_folder"*.{jpg,jpeg,png,webp,gif}; do
    [ -f "$img" ] || continue
    images+=("\"assets/images/$id/$(basename "$img")\"")
  done

  # build images array string
  if [ ${#images[@]} -eq 0 ]; then
    images_str="[]"
  else
    images_str="[\n      $(IFS=",\n      "; echo "${images[*]}")\n    ]"
  fi

  # print the JSON block
  echo "  {"
  echo "    \"id\": \"$id\","
  echo "    \"title\": \"YOUR TITLE\","
  echo "    \"subtitle\": \"YOUR SUBTITLE\","
  echo "    \"blurb\": \"Short description for the project card.\","
  echo "    \"description\": ["
  echo "      \"Paragraph 1.\","
  echo "      \"Paragraph 2.\","
  echo "      \"Paragraph 3.\""
  echo "    ],"
  printf "    \"images\": $images_str,\n"
  echo "    \"skills\": [\"Skill 1\", \"Skill 2\", \"Skill 3\"]"
  echo "  },"
  echo ""
done

echo "── End of output ───────────────────────────────────────────"
echo ""
echo "Remember: remove the trailing comma from the last entry in projects.json"
echo ""
