#!/bin/bash
# ─────────────────────────────────────────────────────────────
# scan-projects.sh
# Compares your local media/ folder against projects.json and prints
# JSON blocks for files that AREN'T LISTED YET — so once you've written
# captions and ordered a gallery, re-running this only shows you what's
# new instead of dumping the whole thing again.
#
# HOW TO USE:
#   1. Upload files to R2 (drag into the R2 dashboard) and drop the same
#      files into media/<project-id>/ locally
#   2. cd "$HOME/Documents/Bootstrap Studio/Portfolio Site Files"
#   3. bash scan-projects.sh
#   4. Paste the new entries into the right arrays in projects.json
#   5. Fill in captions, then deploy-dev → check staging → deploy
#
#   bash scan-projects.sh --all     print everything, ignoring what's
#                                   already listed (for rebuilding from
#                                   scratch)
#
# Images and videos go in "images" (gallery + lightbox).
# Everything else goes in "documents" (attachment chips).
# A project can have either, both, or neither.
# ─────────────────────────────────────────────────────────────

R2_BASE="https://media.matthewjgonzalez.me"
MEDIA_DIR="media"
JSON="projects.json"

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

SHOW_ALL=0
[ "$1" = "--all" ] && SHOW_ALL=1

if [ ! -d "$MEDIA_DIR" ]; then
  echo ""
  echo "Error: 'media/' folder not found."
  echo "Make sure you're running this from your Portfolio Site Files folder."
  exit 1
fi

# ── Collect every src already referenced in projects.json ────────────
# Percent-decoded so "Lap%202.mov" and "Lap 2.mov" count as the same file.
# A missing or unreadable projects.json just means nothing is known yet,
# which degrades to the old print-everything behaviour.
KNOWN_FILE=$(mktemp)
trap 'rm -f "$KNOWN_FILE"' EXIT

if [ -f "$JSON" ] && [ "$SHOW_ALL" -eq 0 ]; then
  python3 - "$JSON" > "$KNOWN_FILE" <<'PY'
import json, sys
from urllib.parse import unquote
try:
    data = json.load(open(sys.argv[1], encoding='utf-8'))
except Exception as e:
    print(f"__JSON_ERROR__{e}")
    raise SystemExit(0)
for p in data:
    for key in ('images', 'documents'):
        for item in p.get(key) or []:
            src = item if isinstance(item, str) else (item or {}).get('src', '')
            if src:
                print(unquote(src))
PY

  if grep -q '^__JSON_ERROR__' "$KNOWN_FILE" 2>/dev/null; then
    echo ""
    echo "Warning: couldn't read $JSON —"
    echo "  $(grep '^__JSON_ERROR__' "$KNOWN_FILE" | sed 's/^__JSON_ERROR__//')"
    echo "  Showing everything instead of only what's new."
    : > "$KNOWN_FILE"
  fi
fi

is_known() {
  [ -s "$KNOWN_FILE" ] || return 1
  grep -Fxq "$1" "$KNOWN_FILE"
}

# Encode only the characters that genuinely break a URL, so projects.json
# stays readable. `#` starts the fragment — ".../Test #2.jpeg" is fetched
# as ".../Test " and 404s. `?` starts the query string. `%` has to go
# first or it would double-encode the escapes added after it.
#
# Spaces, parentheses and brackets are deliberately left alone: browsers
# encode them automatically in a src, and "Completed Build.jpeg" is much
# easier to scan than "Completed%20Build.jpeg" when you're hand-editing.
urlenc() {
  local s="$1"
  s="${s//%/%25}"
  s="${s//#/%23}"
  s="${s//\?/%3F}"
  printf '%s' "$s"
}

# Emit a JSON array block, or a short note when there's nothing new.
# $1 = key name, $2 = count already listed, rest = entries
print_block() {
  local key="$1" existing="$2"; shift 2
  local -a items=("$@")

  if [ ${#items[@]} -eq 0 ]; then
    if [ "$existing" -gt 0 ]; then
      echo "  $key — nothing new ($existing already listed)"
    else
      echo "  $key — none found"
    fi
    return
  fi

  if [ "$existing" -gt 0 ]; then
    echo "  $key — ${#items[@]} new (${existing} already listed):"
  else
    echo "  \"$key\": ["
  fi

  for i in "${!items[@]}"; do
    if [ $i -lt $((${#items[@]} - 1)) ]; then
      echo "${items[$i]},"
    else
      # Trailing comma when appending into an existing array, since these
      # entries will sit above ones that are already there.
      if [ "$existing" -gt 0 ]; then echo "${items[$i]},"; else echo "${items[$i]}"; fi
    fi
  done

  [ "$existing" -gt 0 ] || echo "  ],"
}

echo ""
if [ "$SHOW_ALL" -eq 1 ]; then
  echo "── ALL files (--all) — ignoring what's already in $JSON ──"
else
  echo "── New files only — already-listed entries are hidden ──"
  echo "   (run with --all to print everything)"
fi

TOTAL_NEW=0

for project_folder in "$MEDIA_DIR"/*/; do
  [ -d "$project_folder" ] || continue
  id=$(basename "$project_folder")
  [[ "$id" == .* ]] && continue

  images=();    img_known=0
  documents=(); doc_known=0

  for ext in $IMAGE_EXTS; do
    for f in "$project_folder"*."$ext"; do
      [ -f "$f" ] || continue
      base=$(basename "$f")

      # Compare on the raw form (the known-list is percent-decoded) but
      # emit the encoded form.
      raw="$R2_BASE/$id/$base"
      url="$R2_BASE/$(urlenc "$id")/$(urlenc "$base")"

      if is_known "$raw"; then
        img_known=$((img_known + 1))
      else
        images+=("    { \"src\": \"$url\", \"caption\": \"\" }")
      fi
    done
  done

  for ext in $DOC_EXTS; do
    for f in "$project_folder"*."$ext"; do
      [ -f "$f" ] || continue
      name=$(basename "$f")
      raw="$R2_BASE/$id/$name"
      url="$R2_BASE/$(urlenc "$id")/$(urlenc "$name")"
      if is_known "$raw"; then
        doc_known=$((doc_known + 1))
      else
        documents+=("    { \"src\": \"$url\", \"title\": \"${name%.*}\" }")
      fi
    done
  done

  new_here=$(( ${#images[@]} + ${#documents[@]} ))
  TOTAL_NEW=$(( TOTAL_NEW + new_here ))

  # Stay quiet about projects with nothing new — that's the whole point.
  if [ "$new_here" -eq 0 ] && [ "$SHOW_ALL" -eq 0 ]; then
    continue
  fi

  echo ""
  echo "  ── $id ──"
  print_block "images"    "$img_known" "${images[@]}"
  print_block "documents" "$doc_known" "${documents[@]}"
done

# ── Listed in projects.json but missing from media/ ──────────────────
# Usually means a file was renamed or deleted locally. These will 404 on
# the site if they're also gone from R2.
if [ -s "$KNOWN_FILE" ]; then
  python3 - "$KNOWN_FILE" "$R2_BASE" "$MEDIA_DIR" <<'PY'
import os, sys
known_file, base, media = sys.argv[1], sys.argv[2], sys.argv[3]
missing = []
for line in open(known_file, encoding='utf-8'):
    src = line.strip()
    if not src.startswith(base + '/'):
        continue
    rel = src[len(base) + 1:]
    if not os.path.isfile(os.path.join(media, rel)):
        missing.append(rel)
if missing:
    print("")
    print(f"  ── listed in projects.json but not in {media}/ ──")
    for m in missing:
        print(f"    {m}")
    print("")
    print("    Renamed or deleted locally. If they're gone from R2 too,")
    print("    remove them from projects.json or they'll 404 on the site.")
PY
fi

echo ""
if [ "$TOTAL_NEW" -eq 0 ] && [ "$SHOW_ALL" -eq 0 ]; then
  echo "  Nothing new — projects.json already lists every file in $MEDIA_DIR/."
else
  echo "  $TOTAL_NEW new file(s)."
fi
echo ""
