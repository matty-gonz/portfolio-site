#!/bin/bash
# ─────────────────────────────────────────────────────────────
# scan-projects.sh
# Scans your local media/ folder and prints the "images" and
# "documents" arrays for each project, ready to paste into
# projects.json.
#
# HOW TO USE:
#   1. Upload files to R2 first (drag into R2 dashboard)
#   2. Open Terminal, cd to your Portfolio Site Files folder [cd /Users/mattyg/Documents/Bootstrap\ Studio/Portfolio\ Site\ Files]
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
# Anything listed here becomes an attachment chip on the project page.
# The site sorts each file into a kind (doc / code / model / data /
# archive) by its extension and picks the matching icon and colour, so
# adding an extension here is usually all that's needed.
#
# If you add a type the site doesn't recognise it still works — it just
# gets the generic document icon. To give it the right icon, add the
# extension to the matching `ext` list in FILE_KINDS in
# projects/project.html.
DOC_EXTS_DOC="pdf doc docx txt md rtf"
DOC_EXTS_CODE="ino py c h cpp hpp js ts java cs m rb go rs sh ipynb json xml yml yaml"
DOC_EXTS_MODEL="step stp stl f3d sldprt sldasm iges igs obj 3mf dxf dwg ipt iam gltf"
DOC_EXTS_DATA="csv tsv xlsx xls numbers mat"
DOC_EXTS_ARCHIVE="zip tar gz rar 7z"

DOC_EXTS="$DOC_EXTS_DOC $DOC_EXTS_CODE $DOC_EXTS_MODEL $DOC_EXTS_DATA $DOC_EXTS_ARCHIVE"

# Match both cases without listing every extension twice.
DOC_EXTS="$DOC_EXTS $(echo "$DOC_EXTS" | tr '[:lower:]' '[:upper:]')"

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
