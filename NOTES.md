# Portfolio site — state & open work

Working notes. Update as things change.

## Fonts

All five families load in **one** Google Fonts request, identical in every
page's `<head>`:

```
DM Mono · Kanit 400/600/900 · Nanum Gothic 400/700
Nanum Gothic Coding 400/700 · Syne 400/600/700
```

`DM Mono` and `Syne` drive 18 rules in `custom.css` but weren't loaded at
all until Aug 2026 — the Bootstrap Studio export never included their
`<link>` tags, so they silently fell back to generic `monospace` and
`sans-serif` and rendered differently on every OS. `Acme` was loaded on
all five pages and used by zero rules; it's gone.

**Careful: re-exporting from Bootstrap Studio will overwrite the `<head>`
of these pages** and can undo this. After any export, check that the font
block still says `css2?family=DM+Mono&…` and not four separate `css?`
links.

## Where the JavaScript lives

`assets/js/main.js` is loaded by every page. It holds, in order:

1. the starfield canvas (runs only where `#stars` exists)
2. the mobile nav observer
3. **shared helpers** — `escapeHtml`, `fileExt`, `fileLabel`, `humanSize`,
   `FILE_KINDS`, `kindOf`, `glyphFor`, `fetchWithTimeout`
4. the project card renderer (runs only where `#project-list` exists)

`FILE_KINDS` lives here because `project.html` and `viewer.html` both need
it. They used to hold separate copies that had to be kept identical by
hand — don't reintroduce that.

`fileExt()` returns **lowercase**. Uppercase it where it's displayed. The
`NATIVE` and `IN_VIEWER` lists in `project.html` are lowercase to match.

`viewer.html` has its own `fileNameOf()`, which deliberately differs from
`fileLabel()`: the viewer header shows the full filename with extension,
a chip title drops it.

The file was called `main-4.js` — that number was manual cache-busting,
no longer needed now that nginx sends `Cache-Control: no-cache`.

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

## Writing descriptions in projects.json

Each entry in `description` is one paragraph, rendered through `innerHTML`,
so **HTML works** — links, `<em>`, `<strong>`.

```json
"...through <a href='https://www.nakka-rocketry.net/'>Richard Nakka's website</a>, a space..."
```

Use **single quotes** for HTML attributes. Double quotes end the JSON
string and break the whole file.

Three rules, all the same underlying one — a JSON string can't contain a
raw `"` or a line break:

| You want | Write | Not |
|---|---|---|
| a link | `href='...'` | `href="..."` |
| a quoted word | `the 'brains' of` | `the "brains" of` |
| an inch mark | `1/2\"` or "1/2 inch" | `1/2"` |
| a new paragraph | a new array entry | a line break inside the string |

The last one is sneaky: pasting two paragraphs into one string looks fine
in an editor and is invalid JSON.

**If Claude has edited this file, close and reopen it before you edit.**
A text editor holding the old version in a buffer will overwrite those
changes the moment you save — which has already silently reverted the
escaping fixes above once.

Check before deploying — `deploy-dev` also refuses to run on bad JSON:

```bash
python3 -m json.tool projects.json > /dev/null && echo valid
```

Link styling lives in `.project-desc a` in `custom.css`.

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

- **code** — highlight.js, line numbers in a separate cell so copying gives
  you the source without numbers glued on. Extension maps to language via
  `LANGS`; `.ino` renders as C++. Unknown extensions still render, just
  unhighlighted.
- **`.md`** — rendered with marked.
- **`.csv` / `.tsv`** — table with sticky header and row numbers. Parser
  handles quoted fields, embedded commas and newlines, escaped quotes.
- **`.xlsx` / `.xls` / `.xlsm`** — SheetJS. One tab per sheet (the tab strip
  only appears for multi-sheet workbooks); each sheet uses the same table
  renderer as CSV.
- **`.zip`** — JSZip reads the central directory, so contents are listed
  with sizes and dates **without extracting**. Nothing is written anywhere.
- **`.stl`** — three.js. STL is parsed by hand rather than with three's
  `STLLoader`, because the `examples/` folder isn't reliably CDN-hosted;
  binary STL is a fixed 50-byte record per triangle. Drag-to-rotate and
  scroll-to-zoom are ~40 lines rather than OrbitControls, same reason.
  Handles both binary and ASCII STL. Rotates the mesh, not the camera, so
  lighting stays fixed and the model reads from any angle.

Caps: 2 MB for text (`MAX_TEXT`), 25 MB for binary (`MAX_BINARY`) — parsing
a mesh is cheaper than highlighting, and STLs are legitimately large. Over
the cap you get a download prompt. Binary content in a text file is caught
by a NUL byte and refused.

Libraries load only when that file type is opened, so nothing here slows a
project page. If a CDN fetch fails, each renderer degrades to a download
prompt instead of a blank screen.

**PDFs deliberately stay native.** The browser's own viewer has search,
print, thumbnails and page navigation; PDF.js would be ~1 MB to build
something worse.

Routing lives in `project.html`: `IN_VIEWER` goes to the viewer, `NATIVE`
(PDF, images) opens directly, everything else downloads.

**Depends on R2 CORS** allowing the site origins — see below.

## Open work — deferred

### Formats with no browser reader

**STEP / STP** would need a CAD kernel compiled to WebAssembly — several
megabytes and slow. **F3D / SLDPRT** are proprietary with no browser-side
reader at all. Export an STL alongside (which the viewer handles), or add a
public OnShape link as its own chip.

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

## Tags (the `skills` array)

Tags drive the filter row on the index page, so a tag used by only one
project can't actually filter anything. Prefer reusing an existing tag, and
when adding a new one, consider whether it should be applied retroactively.

**In use as of Aug 2026** — 11 tags per project.

Shared by all three — `Electrical Systems`, `Project Management`,
`Prototyping`, `Sketching`, `Soldering`

Shared by two — `CAD`, `3D Printing`, `Team Leadership`

Static fire only — `Arduino`, `Construction`, `Data Acquisition`,
`Data Analysis`, `Rocketry`, `Solid Fuel Propulsion`

RC Derby only — `Chassis Design`, `Servo Mechanisms`, `Vehicle Steering`

Submarine only — `Hull Design`, `Waterproofing`, `Fluid Propulsion`

Note the deliberate parallel between `Fluid Propulsion` and
`Solid Fuel Propulsion` — keep that pattern for future propulsion work.

`Construction` is a candidate for retroactive application to the other two
builds, which would make it filterable.

Watch for empty strings in the array (`""`), which render as blank tag
buttons in the filter row.

## Animated card thumbnails

Two independent fields, handled by `cardHTML` in `assets/js/main-4.js`:

```json
"thumbnail":       "https://media.matthewjgonzalez.me/<project>/Completed Car.JPG",
"thumbnail_hover": "https://media.matthewjgonzalez.me/<project>/car-loop.mov"
```

- `thumbnail` alone, an image → plain `<img>`, exactly as before.
- `thumbnail` image + `thumbnail_hover` clip → the clip crossfades in over
  the still on hover. `preload="none"`, so it isn't downloaded until
  someone actually hovers.
- `thumbnail` pointing at a *video* → shows its frame at 1s and plays on
  hover, no separate file needed.
- `thumbnail_hover` missing, blank, or not a video extension → ignored.

The hover clip is **not** listed in `images`, so it never appears in the
gallery. `scan-projects.sh` reads `thumbnail` and `thumbnail_hover` when
building its known-file list, so it won't report those as new every run.

A clip that 404s or won't play removes itself and leaves the still. Honours
`prefers-reduced-motion` — the still shows and nothing ever animates.

**Making one, no extra tools:** open the clip in QuickTime, Edit → Trim
(Cmd+T) down to 3–5 seconds, then File → Export As → 480p. Keep the `.mov`
— the site already plays `.mov` in the gallery. Expect 200–500 KB. Match
the still's aspect ratio where you can; the clip is `object-fit: cover`, so
a very different shape gets cropped.

Don't use a real `.gif`: 256 colours and almost no interframe compression
means the same clip lands around 9 MB, heavier than every photo on the page
combined. Animated WebP works in an `<img>` with no code change at all, but
is still roughly 7x a video and needs a converter to produce.

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

---

## Analytics — how it actually works

Two independent data sources, combined into one page. Knowing which is
which explains every number on the stats site.

### 1. Server logs — what was requested

nginx writes a line per request to `/var/log/nginx/portfolio.access.log`.
Sees everything, including bots. Cannot see anything that happens
*inside* a page.

- IPs are truncated to `/24` **before writing** (`pi/nginx-log-anon.conf`,
  installed to `/etc/nginx/conf.d/log-anon.conf`). Full addresses never
  touch the SD card, so there is nothing sensitive to lose.
- `access_log ... anonymized;` in `sites-available/default` selects that
  format. Without the `anonymized` keyword it silently logs full IPs.
- GoAccess parses it into both HTML and JSON in one pass.

### 2. Beacon events — what people did

`assets/js/analytics.js` runs on every page and pings `/e`. nginx logs
those to `/var/log/nginx/events.log` via `location = /e` in
`pi/harden.conf`. **No server process, no database** — nginx receiving a
request and writing a line is the whole mechanism.

Tab-separated, 11 fields:

```
time  host  ip  type  path  referrer  session  depth  dwell  label  user-agent
```

- `type` is `view`, `end`, or `click`. `end` fires on tab hide and
  carries scroll depth (%) and dwell (seconds).
- `label` carries the campaign tag on `view` events and the click target
  on `click` events.
- Values are URL-encoded. Empty fields log as `-`.
- Session id lives in `sessionStorage`, so it dies with the tab.

**Key property:** events only exist if a browser ran JavaScript, and
almost no crawler does. So events are humans by construction, which is
why the headline numbers come from here and GoAccess totals are demoted
to a footnote.

### The pipeline

```
cron (*/5)  ->  stats-refresh  ->  goaccess  ->  HTML + JSON
                                -> stats-summary(JSON, events.log)
                                -> /var/www/stats/index.html    (summary)
                                   /var/www/stats/dashboard.html (GoAccess)
```

Served on `127.0.0.1:8082` — **loopback only**, so the only route in is
the Cloudflare tunnel, behind Access. Even with the Access policy
deleted, nothing on the LAN can reach it.

`stats-refresh` exits immediately if neither log changed since the last
successful run, which is what makes a 5-minute interval cheap. Use
`--force` to override.

### Retention

`rotate 260` (weeks) in `/etc/logrotate.d/nginx` = 5 years, and that one
number *is* the report window — the report is rebuilt from whatever logs
still exist, so they cannot drift apart. `--keep-last` in
`stats-refresh.sh` is a safety net that should be set to match.

### Campaign tags

Put `?from=resume` on the link in the resume, `?from=linkedin` on the
profile, `?from=card` on a QR code. The tag is stored for the whole
session (so a download on page three is still credited to the resume)
and stripped from the address bar so visitors never see it.

Most real visits arrive with **no referrer at all** — texts, QR codes,
PDFs and many apps strip it — so tagging is the only reliable way to
know which channel works.

### Leaving yourself out

Visit `/?me=1` once per browser. Everything that browser sends is then
prefixed `x-` on the session id and discarded by the parser. `/?me=0`
undoes it.

Do **not** use `stats-exclude me` (the IP-based tool) from the
apartment: Velocity NATs the whole building behind one address, and
`/24` exclusion would silently delete any neighbour who visits. Same
reasoning applies on campus wifi, harder.

### Gotchas found the hard way

- GoAccess JSON dates are `20260818`, **not** the `18/Aug/2026` shown in
  the HTML. Getting this wrong is silent: totals stay right while every
  per-day number reads zero.
- GoAccess picks output format from the **file extension**. A temp file
  named `.tmp.1234` fails with "Invalid filename extension".
- The Referrers panel is **off by default**; it needs
  `--enable-panel=REFERRERS`.
- Cities live on the **hosts** panel, not the geolocation panel, which
  only ever goes down to country.
- `access_log` inside `location = /e` **replaces** the inherited one.
  Without that line every beacon would also count as a page view.
- Chrome copies `sessionStorage` into a tab opened from a link, so one
  session can legitimately show two `view` events with no `end` between.

### Files

| File | Installs to |
|---|---|
| `pi/harden.conf` | `/etc/nginx/snippets/harden.conf` |
| `pi/nginx-log-anon.conf` | `/etc/nginx/conf.d/log-anon.conf` |
| `pi/nginx-stats.conf` | `/etc/nginx/sites-available/stats` |
| `pi/logrotate-nginx` | `/etc/logrotate.d/nginx` |
| `pi/stats-refresh.sh` | `/usr/local/bin/stats-refresh` |
| `pi/stats-summary.py` | `/usr/local/bin/stats-summary` |
| `pi/stats-exclude.sh` | `/usr/local/bin/stats-exclude` |
| `assets/js/analytics.js` | served from the site |

Full setup steps: `pi/STATS-SETUP.md`.

### Backups

`backup-logs` (in `pi/portfolio.zsh`) pulls the logs to
`~/Documents/portfolio-logs`. Pull rather than push, so the pi holds no
credentials and a compromised pi cannot reach the backups. The logs are
the only thing on the pi that git cannot restore.
