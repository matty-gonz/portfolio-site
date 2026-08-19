# Brief: build me a portfolio site

**How to use this:** paste this whole file into Claude as your first
message. It is written to Claude, not to you. Claude will ask you a few
questions before starting, then build the site with you step by step.

This is a working blueprint, not a theory. It describes a portfolio site
that has been built and is running, adapted for someone with no server
of their own. The gotchas near the end are real ones that cost hours —
they are the most valuable part of this document.

---

## To Claude: what you are building

A fast, static, hand-editable portfolio site for an engineering student.
Deployed on Cloudflare Pages, with media on Cloudflare R2, a staging
site the public cannot see, and privacy-respecting analytics.

Total recurring cost: **$0**. This is a hard requirement, not a
preference. Every component below has a genuinely free tier that does
not expire into a paid one. If you find yourself proposing something
billable, stop and propose an alternative instead.

The person you are working with is an engineering student, **not a
software developer**. They can follow terminal instructions carefully
and edit text files. They cannot debug a build system. Optimise every
decision for "still works and is understandable in a year," not for
what is technically most elegant.

---

## Ask these before you write any code

Do not guess these. Use your question tool if you have one.

1. **Do they own a domain yet?** If not, that is step one — Cloudflare
   Registrar sells at wholesale cost with no markup, though the domain
   itself is the one thing here that is not free (~$10/yr).
2. **What content do they have right now?** Projects with photos?
   Videos? PDFs or CAD files? This determines whether R2 is needed on
   day one or can wait.
3. **How comfortable are they in a terminal?** Adjust how much you
   explain per command.
4. **Do they want a staging site**, or is publishing straight to live
   fine to begin with? Staging is genuinely useful but doubles the
   setup.
5. **Do they already use GitHub?** If not, that account is a
   prerequisite and worth setting up first.

---

## Architecture

| Concern | Use | Why |
|---|---|---|
| Hosting | **Cloudflare Pages** | Free, unlimited bandwidth, deploys on git push, free SSL |
| Source of truth | **GitHub repo** | Pages watches it; also the backup |
| Live site | `main` branch → `theirdomain.com` | |
| Staging | `dev` branch → preview URL or `dev.theirdomain.com` | Pages gives branch previews free |
| Staging privacy | **Cloudflare Access** | Free ≤50 users, email one-time code |
| Large media | **Cloudflare R2** + custom domain | Zero egress fees; keeps the git repo small |
| Image resizing | **Cloudflare Image Transformations** | 5,000 free unique transforms/month |
| Analytics | **Cloudflare Web Analytics** | Free, cookieless, no consent banner needed |

Free-tier limits worth knowing: 500 builds/month, 20,000 files per
site, unlimited bandwidth, unlimited preview deployments.

**Note the deliberate absence of a build step.** No npm, no bundler, no
framework. Plain HTML, CSS and vanilla JS. A static site with no
toolchain still works untouched in five years; a Node build breaks
within one and the person cannot fix it. Do not introduce React,
Tailwind CLI, Vite, or a static site generator unless they explicitly
ask and understand the maintenance cost.

---

## Content architecture — the important idea

**Do not hand-write one HTML file per project.** That is the trap. It
means editing markup to add a photo, and it guarantees the pages drift
apart in style over time.

Instead:

- `projects.json` — an array of project objects. All content lives here.
- `index.html` — reads the JSON, renders cards, handles filter/sort.
- `projects/project.html` — one template. Reads `?id=` from the URL and
  renders that project.

Adding a project becomes editing a JSON file. Non-negotiable — it is
what makes the site maintainable by a non-developer.

Suggested project shape:

```json
{
  "id": "static-fire-rocket-project",
  "title": "Static Fire Rocket Test Stand",
  "subtitle": "Summer 2026",
  "blurb": "One or two sentences for the card.",
  "description": ["Paragraph one.", "Paragraph two."],
  "tags": ["CAD", "Data Acquisition", "Construction"],
  "date": { "season": "Summer", "months": "Jun — Aug", "sort": "2026-06" },
  "thumbnail": "https://media.theirdomain.com/proj/cover.jpg",
  "images": [
    { "src": "https://media.theirdomain.com/proj/1.jpg", "caption": "..." }
  ],
  "documents": [
    { "src": "https://media.theirdomain.com/proj/report.pdf",
      "title": "Test Report" }
  ]
}
```

Build it incrementally. One project rendering end to end beats six
half-built features.

---

## Deployment

Cloudflare Pages connects to the GitHub repo and deploys on push. No
scripts, no servers, no cron.

```
edit locally  →  git push origin dev   →  staging updates
                 merge dev → main      →  live updates
```

Give them two shell aliases so they never type raw git:

- `deploy-dev` — commit everything, push to `dev`
- `deploy` — fast-forward merge `dev` into `main`, push

**Put a validation guard in `deploy-dev`.** Before committing, verify
`projects.json` parses:

```bash
if ! python3 -m json.tool projects.json > /dev/null 2>&1; then
  echo "projects.json is not valid JSON — NOTHING was deployed."
  return 1
fi
```

This one check prevents the single most common way this site breaks.
Also check that `git add` actually succeeded — a deploy that reports
success while shipping nothing is worse than a loud failure.

---

## Gotchas — read before building

Every one of these was hit for real.

**1. JSON is unforgiving and the error is invisible.**
A raw `"` or a literal newline inside a string breaks the entire file,
and the site shows "project not found" — which sends you hunting in the
wrong place entirely. Teach the substitutions early:

| Want | Write |
|---|---|
| `1/2"` | `1/2 inch` or `1/2\"` |
| line break | `\n`, or use separate array items |
| a link | `<a href='...'>` — single quotes inside JSON strings |

**2. `#` in a filename silently truncates the URL.**
`Test #2.jpg` is fetched as `Test ` and 404s, because `#` starts a
fragment. Percent-encode `#`, `?` and `%` in media URLs. Leave spaces
alone — browsers handle those, and readable filenames matter more.

**3. Browsers will serve stale CSS for days.**
Without an explicit `Cache-Control`, browsers invent a lifetime of
roughly 10% of the file's age. A year-old stylesheet gets cached for
weeks, and edits appear not to work. On Pages, add a `_headers` file:

```
/*
  Cache-Control: no-cache

/assets/img/*
  Cache-Control: public, max-age=604800
```

`no-cache` does not mean "don't cache" — it means "revalidate first",
so unchanged files return 304 and cost almost nothing.

Warn them: after fixing this, existing stale copies still need one hard
refresh (Cmd+Shift+R). The header only governs responses fetched after
it goes live.

**4. Load the font weights actually used.**
Requesting `Kanit:wght@400` while the CSS asks for `font-weight: 900`
makes the browser fake the bold. It looks fine until the real weight is
loaded and everything abruptly gets heavier. Audit which weights the
CSS uses and request exactly those.

**5. Media belongs in R2, not git.**
Git stores every version of every binary forever. One accidental commit
of a photo folder permanently bloats the repo. Add `media/` to
`.gitignore` on day one — and **do not let `.gitignore` list itself**,
or it stays untracked and a fresh clone has no ignore rules at all.

**6. Full-size images in a thumbnail strip are the usual cause of
"the site feels slow."** Use Cloudflare Image Transformations:
`/cdn-cgi/image/width=400,quality=82,format=auto/<url>`. Request the
size actually displayed.

**7. Analytics: use the beacon, not the request counter.**
Cloudflare's main dashboard counts every request — images, fonts, bots.
One human visit can be 50+ requests, and most traffic on any public
site is crawlers. Cloudflare **Web Analytics** is a separate free
product that counts real page views in real browsers. Turn that on
instead and explain the difference, or the numbers are meaningless.

**8. Write privacy behaviour down.** A short note on the contact page
covering what is collected and for how long. Cheap, honest, correct.

---

## Working style

- **One section at a time, verified before moving on.** Each step should
  end with a check and a statement of what a correct result looks like.
- **Explain in plain language.** Say what a thing does and why it was
  chosen, not just the command to run.
- **Say when you are unsure.** A wrong confident answer sends them
  debugging the wrong thing for an hour.
- **Keep a `NOTES.md` in the repo** recording decisions, the deploy
  commands, and gotchas as you hit them. In six months this is the only
  reason any of it is still editable.
- **Never commit secrets.** If the repo is public — and for a portfolio
  it usually should be — remember git history keeps a leaked token
  forever, even after the line is deleted.

---

## Suggested order

1. GitHub account + repo, domain on Cloudflare
2. One static page deployed on Pages, custom domain working
3. `projects.json` + `index.html` rendering cards
4. `project.html` detail template
5. `_headers` caching, font audit
6. R2 bucket + custom domain, move media out of git
7. Image Transformations on thumbnails
8. `dev` branch + Pages preview + Access on staging
9. `deploy-dev` / `deploy` aliases with the JSON guard
10. Cloudflare Web Analytics + privacy note

Stop after step 4 and let them add a real project before continuing.
Nothing exposes a bad content model faster than actual content.
