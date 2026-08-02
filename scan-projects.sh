#!/bin/bash
# ─────────────────────────────────────────────────────────────
# scan-projects.sh
# Scans your local media/ folder and prints the "images" and
# "documents" arrays for each project, ready to paste into
# projects.json.
#
# HOW TO USE:
#   1. Upload files to R2 first (drag into R2 dashboard)
#   2. Open Terminal, cd to your Portfolio Site Files folder
#   3. Run: bash scan-projects.sh
#   4. Copy the blocks for your project
#   5. Paste into projects.json, fill in captions / titles
#   6. deploy-dev, check the staging site, then deploy
#
# Images and videos go in "images" (the gallery + lightbox).
# PDFs go in "documents" (the attachment chips below the
# gallery). A project can have either, both, or neither.
# ─────────────────────────────────────────────────────────────

R2_BASE="https://media.matthewjgonzalez.me"
MEDIA_DIR="media"

IMAGE_EXTS="jpg jpeg png webp gif JPG JPEG PNG WEBP GIF mp4 mov MP4 MOV webm"
DOC_EXTS="pdf PDF"

if [ ! -d "$MEDIA_DIR" ]; then
  echo ""
  echo "Error: 'media/' folder not found."
  echo "Make sure you're running this from your Portfolio Site Files folder."
  exit 1
fi

echo ""
echo "── Copy each block into projects.json and fill in the blanks ──"

for project_folder in "$MEDIA_DIR"/*/; do
  [ -d "$project_folder" ] || continue
  id=$(basename "$project_folder")
  [[ "$id" == .* ]] && continue

  images=()
  for ext in $IMAGE_EXTS; do
    for f in "$project_folder"*."$ext"; do
      [ -f "$f" ] || continue
      images+=("    { \"src\": \"$R2_BASE/$id/$(basename "$f")\", \"caption\": \"\" }")
    done
  done

  documents=()
  for ext in $DOC_EXTS; do
    for f in "$project_folder"*."$ext"; do
      [ -f "$f" ] || continue
      name=$(basename "$f")
      # Pre-fill the title with the filename minus extension, so you
      # usually only have to tidy it rather than type it out.
      title="${name%.*}"
      documents+=("    { \"src\": \"$R2_BASE/$id/$name\", \"title\": \"$title\" }")
    done
  done

  echo ""
  echo "  ── $id ──"

  # ---- images ----
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

  # ---- documents ----
  # Omitted entirely when there are none. The renderer treats a missing
  # array the same as an empty one, so don't paste an empty block just
  # for symmetry.
  if [ ${#documents[@]} -eq 0 ]; then
    echo "  (no PDFs found — omit the \"documents\" key for this project)"
  else
    echo "  \"documents\": ["
    for i in "${!documents[@]}"; do
      if [ $i -lt $((${#documents[@]} - 1)) ]; then
        echo "${documents[$i]},"
      else
        echo "${documents[$i]}"
      fi
    done
    echo "  ],"
  fi

done

echo ""
