# Portfolio site — state & open work

Working notes. Update as things change.

## How the site is wired

| Hostname | Cloudflare tunnel → | nginx block | Doc root | Branch |
|---|---|---|---|---|
| `matthewjgonzalez.me` | `localhost:80` | `sites-available/default` | `/var/www/html` | `main` |
| `dev.matthewjgonzalez.me` | `localhost:8081` | `sites-available/staging` | `/var/www/staging` | `dev` |

- Media (images, video, PDFs, any attachment) lives in the R2 bucket
  `portfolio-media`, served at `media.matthewjgonzalez.me`.
- The pi runs `/usr/local/bin/site-pull` once a minute per site via root's
  crontab. It only reloads nginx when the branch HEAD actually moves.
- Auth to GitHub is an SSH key (`~/.ssh/id_ed25519_github`). The old
  personal access token was retired Aug 2026.
- `dev.matthewjgonzalez.me` is behind Cloudflare Access — email one-time
  code, `ma110919@ucf.edu` only.

## Deploy commands

Defined in `pi/portfolio.zsh`, sourced from `~/.zshrc`. Always work on `dev`.

```
deploy-dev "message"   # local -> dev.matthewjgonzalez.me
deploy                 # promote dev -> main -> live (confirms first)
deploy-rollback        # revert the last live commit
```

`deploy-dev` refuses to run if `projects.json` is invalid JSON.

## Gotchas that have already bitten

- **Unescaped `"` in a caption** breaks all of `projects.json`, and the
  project page reports it as "Project not found" — which sends you hunting
  in the wrong place. Write `1/2\"` or just say "1/2 inch".
- **Attaching site files to a Claude chat creates hardlinks**, which makes
  TextEdit refuse to save them ("you don't have permission"). Fix:
  `find . -type f -links +1 -not -path "./.git/*"` then replace each with a
  copy of itself. Better: don't attach files, the folder is connected.
- **`#` in a filename silently breaks the URL.** `#` starts the fragment,
  so `.../Test #2.jpeg` is fetched as `.../Test ` and 404s — the image just
  shows as broken with no error anywhere. `scan-projects.sh` now
  percent-encodes filenames, but watch for it if you hand-write a src.
- **`.git/index.lock` left behind** by an interrupted git process blocks all
  git operations. Safe to `rm -f` when nothing is actually running.

## File viewer

`projects/viewer.html` opens in a new tab and renders text-ish
attachments. Reached via `viewer.html?src=<url>&title=<name>&from=<id>`;
`from` is what makes its back link return to the project.

- **code** — highlight.js from cdnjs, line numbers in a separate cell so
  copying gives you the source without numbers glued on. Extension maps to
  language via `LANGS`; `.ino` renders as C++. Unknown extensions still
  render, just unhighlighted.
- **`.md`** — rendered with marked.
- **`.csv` / `.tsv`** — real table, sticky header, row numbers. Parser
  handles quoted fields, embedded commas and newlines, escaped quotes.
- Previews cap at 2 MB (`MAX_BYTES`); above that it's a download prompt.
  Binary content is detected by a NUL byte and refused.
- If a CDN library fails to load it degrades to plain text rather than
  breaking.

Routing lives in `project.html`: `IN_VIEWER` goes to the viewer, `NATIVE`
(PDF, images) opens directly, everything else downloads.

**Depends on R2 CORS** allowing the site origins — see below.

## Open work — deferred

### STL viewer

A three.js STLLoader preview for `.stl`, in the same viewer page. Not
started. STEP / F3D / SLDPRT aren't feasible in a browser — export an STL
alongside, or add a public OnShape link as its own chip.

### Smaller items

- `.see-more-btn` and `.section-label` in `custom.css` / `project.html`
  declare `font-family: 'DM Mono'`, which no page actually loads. They fall
  back to whatever monospace the browser picks, so they render differently
  across devices. Either load DM Mono or switch them to Nanum Gothic
  Coding (which is loaded, and is what the attachment chips use).
- The `download` attribute on non-viewable attachments is ignored because
  media is a different origin. Harmless, but real control over filenames
  would need `Content-Disposition` set on the R2 objects.

## Image delivery

Images are resized on the fly by Cloudflare Transformations rather than
served at full size. `imgURL(src, width)` in `projects/project.html` wraps
each src as `/cdn-cgi/image/width=N,quality=82,format=auto/<src>`.

Sizes: filmstrip 160px, gallery 700px, lightbox 1800px.

**Required Cloudflare setting.** Images → Transformations → Settings →
Sources must allow `media.matthewjgonzalez.me`. "Specified origins" with
only `matthewjgonzalez.me` does NOT cover subdomains — that produces:

```
HTTP/2 403
cf-resized: err=9401
ERROR 9401: Transformation origin is not in allowed origins list
```

Check it with:

```bash
curl -sI "https://matthewjgonzalez.me/cdn-cgi/image/width=160,quality=82,format=auto/https://media.matthewjgonzalez.me/<project>/<file>" \
  | grep -iE "^HTTP|content-type|cf-resized"
```

Want `200` and `image/webp`. Free tier is 5,000 unique transformations a
month; this library uses ~90 and they're edge-cached after the first hit.

Every `<img>` falls back to the untransformed original on error, so a
misconfiguration degrades to "slow" rather than "broken". Setting
`IMG_CDN = false` in `project.html` bypasses the whole thing.

## Video posters — not doing this

`<video>` shows black until it decodes a frame. Cloudflare Media
Transformations (`/cdn-cgi/media/mode=frame`) would fix it with no extra
files, but that endpoint 404s on this zone — it's a separate product from
Image Transformations and enabling one doesn't enable the other. Check
Stream → Transformations if you want to revisit.

The alternative is generating poster JPEGs by hand and uploading them
alongside each video, which adds a step to the media workflow. Decided
against it. Reverted Aug 2026.

## Attachment schema

```json
"documents": [
  { "src": "https://media.matthewjgonzalez.me/<project>/File.pdf",
    "title": "Human readable name" }
]
```

Only `src` is required; a missing `title` falls back to the filename. Omit
the whole `documents` key for projects with no attachments.

Chips are deliberately compact — icon, title, then type and size. Captions
were tried and removed: they turned the row into a block of cards and
buried the file list. Images still have captions (those drive the
lightbox); documents don't.

## scan-projects.sh

`bash scan-projects.sh` diffs `media/` against `projects.json` and prints
only files that aren't listed yet. Projects with nothing new print nothing.
It also flags entries in `projects.json` whose file is missing from
`media/` — usually a rename or deletion that will 404 on the site.

`bash scan-projects.sh --all` prints everything, ignoring what's already
listed. For rebuilding an array from scratch.

Comparison is percent-decoded, so `Lap%202.mov` matches `Lap 2.mov`.
If `projects.json` is missing or unparseable it warns and falls back to
printing everything.

New entries are printed **with trailing commas**, since they're meant to
be inserted into an existing array. If you paste them as the last entries,
delete the comma on the final line.

## Adding an attachment type

1. Add the extension to the right `DOC_EXTS_*` list in `scan-projects.sh`.
2. If it should get a specific icon rather than the generic page, add it to
   the matching `ext` array in `FILE_KINDS` at the top of
   `projects/project.html`.

Kinds: `doc` (cyan), `code` (green), `model` (amber), `data` (violet),
`archive` (slate). Unknown extensions fall back to `doc` and still work.
