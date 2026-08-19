#!/usr/bin/env python3
"""
stats-summary — turn GoAccess JSON into a page a human can read.

Install to /usr/local/bin/stats-summary (mode 755).
Called by stats-refresh:  stats-summary <input.json> <output.html>

WHY THIS EXISTS
GoAccess answers "what is my server doing", which is the right question
for a sysadmin and the wrong one for a portfolio. The questions here are
"did anyone visit", "which project did they look at", and "did that
LinkedIn post do anything". This reads the same data and answers those
instead. The full dashboard stays one click away.

DESIGN NOTE
Every lookup is defensive. GoAccess's JSON shape varies a little between
versions and panels vanish entirely when --ignore-panel is used or when
a panel has no data yet. A missing panel should mean one quiet section,
never a traceback that costs you the whole page.
"""

import json
import sys
import html
from datetime import datetime, timedelta

# ── input ────────────────────────────────────────────────────────────

if len(sys.argv) != 3:
    sys.exit("usage: stats-summary <input.json> <output.html>")

SRC, DEST = sys.argv[1], sys.argv[2]

try:
    with open(SRC, encoding="utf-8", errors="replace") as fh:
        D = json.load(fh)
except Exception as exc:                       # noqa: BLE001
    sys.exit(f"could not read {SRC}: {exc}")

if not isinstance(D, dict):
    sys.exit("unexpected JSON: top level is not an object")


def panel(name):
    """Rows of a GoAccess panel, or [] if absent/ignored/empty."""
    node = D.get(name)
    if not isinstance(node, dict):
        return []
    rows = node.get("data")
    return rows if isinstance(rows, list) else []


def count(row, key):
    """GoAccess nests counts as {"count": N, "percent": P}."""
    val = row.get(key)
    if isinstance(val, dict):
        return val.get("count", 0) or 0
    return val or 0


GEN = D.get("general", {}) if isinstance(D.get("general"), dict) else {}

# ── visitors over time ───────────────────────────────────────────────
# The visitors panel is one row per day, "data" holding a date string.
# Format follows --date-spec (default: 18/Aug/2026).

days = []
for row in panel("visitors"):
    raw = str(row.get("data", "")).strip()
    when = None
    for fmt in ("%d/%b/%Y", "%Y-%m-%d", "%d/%b/%Y:%H"):
        try:
            when = datetime.strptime(raw, fmt)
            break
        except ValueError:
            continue
    if when:
        days.append((when, count(row, "visitors"), count(row, "hits")))

days.sort()


def window(n):
    """(visitors, hits) over the last n days, counting from the most
    recent day that has data rather than from today — otherwise a quiet
    week reads as a broken report."""
    if not days:
        return 0, 0
    newest = days[-1][0]
    cutoff = newest - timedelta(days=n - 1)
    sel = [d for d in days if d[0] >= cutoff]
    return sum(d[1] for d in sel), sum(d[2] for d in sel)


v7, h7 = window(7)
v30, h30 = window(30)

total_requests = GEN.get("total_requests", 0) or 0
valid_requests = GEN.get("valid_requests", 0) or 0
unique_visitors = GEN.get("unique_visitors", 0) or 0
not_found = GEN.get("not_found", 0) or 0

# Everything GoAccess discarded was a crawler (--ignore-crawlers plus
# --unknowns-as-crawlers). That difference is the bot share, and it is
# usually the most surprising number on the page.
bot_hits = max(total_requests - valid_requests, 0)
bot_pct = round(bot_hits / total_requests * 100) if total_requests else 0

busiest = max(days, key=lambda d: d[1]) if days else None

# ── pages ────────────────────────────────────────────────────────────

FRIENDLY = {
    "/": "Home",
    "/index.html": "Home",
    "/about.html": "About",
    "/contact.html": "Contact",
    "/projects/": "Projects",
}

# Words that should stay upper-case when a project slug is prettified.
ACRONYMS = {"rc", "sfrp", "cad", "pcb", "uav", "ucf", "rov", "stl",
            "3d", "cnc", "fea", "abs", "pla", "ev", "usa", "nasa"}

SKIP_EXT = (".json", ".css", ".js", ".png", ".jpg", ".jpeg", ".webp",
            ".gif", ".svg", ".ico", ".woff", ".woff2", ".ttf", ".map",
            ".mp4", ".mov", ".webm")


def prettify(path):
    """Turn a request path into something worth reading."""
    clean = path.split("#", 1)[0]
    base = clean.split("?", 1)[0]

    if base in FRIENDLY:
        return FRIENDLY[base]

    # /projects/project.html?id=static-fire-rocket-project
    if "id=" in clean:
        slug = clean.split("id=", 1)[1].split("&", 1)[0]
        name = slug.replace("-", " ").replace("_", " ").strip()
        if name:
            # Title-case, but don't mangle acronyms — "rc-derby-car"
            # should read RC Derby Car, not Rc Derby Car. Add to
            # ACRONYMS as you add projects.
            pretty = " ".join(
                w.upper() if w.lower() in ACRONYMS else w.capitalize()
                for w in name.split()
            )
            if "viewer.html" in base:
                return f"{pretty} (file viewer)"
            return pretty

    if base.endswith("viewer.html"):
        return "File viewer"
    return base


def is_page(path):
    base = path.split("?", 1)[0].lower()
    return not base.endswith(SKIP_EXT)


pages, seen = [], {}
for row in panel("requests"):
    path = str(row.get("data", "")).strip()
    if not path or not is_page(path):
        continue
    label = prettify(path)
    # Several raw paths can collapse to one friendly name (/ and
    # /index.html both become Home), so merge rather than list twice.
    seen[label] = seen.get(label, 0) + count(row, "visitors")
pages = sorted(seen.items(), key=lambda kv: kv[1], reverse=True)[:8]

# ── referrers ────────────────────────────────────────────────────────

refs = []
for row in panel("referring_sites") or panel("referrers"):
    site = str(row.get("data", "")).strip()
    if not site or "matthewjgonzalez.me" in site:
        continue                      # our own pages linking to each other
    refs.append((site, count(row, "visitors")))
refs = sorted(refs, key=lambda kv: kv[1], reverse=True)[:6]

# ── places ───────────────────────────────────────────────────────────

places = []
for row in panel("geolocation"):
    label = str(row.get("data", "")).strip()
    kids = row.get("items")
    if isinstance(kids, list) and kids:          # continent -> countries
        for kid in kids:
            name = str(kid.get("data", "")).strip()
            if name:
                places.append((name, count(kid, "visitors")))
    elif label:
        places.append((label, count(row, "visitors")))
places = sorted(places, key=lambda kv: kv[1], reverse=True)[:6]

# ── headline sentence ────────────────────────────────────────────────

def plural(n, one, many=None):
    return one if n == 1 else (many or one + "s")


if v7:
    lead = f"{v7} {plural(v7, 'person', 'people')} visited in the last 7 days."
elif unique_visitors:
    lead = "No visits in the last 7 days."
else:
    lead = "No visits recorded yet."

bits = []
if refs:
    bits.append(f"Most arrivals came from {html.escape(refs[0][0])}.")
if pages:
    bits.append(f"{html.escape(pages[0][0])} was the most viewed page.")
lead_extra = " ".join(bits)

E = html.escape
generated = datetime.now().strftime("%A %d %B %Y, %H:%M")


def rows_html(items, empty):
    if not items:
        return f'<p class="empty">{E(empty)}</p>'
    top = max(v for _, v in items) or 1
    out = []
    for name, val in items:
        pct = max(round(val / top * 100), 2)
        out.append(
            f'<li><span class="bar" style="width:{pct}%"></span>'
            f'<span class="lbl">{E(str(name))}</span>'
            f'<span class="val">{val}</span></li>'
        )
    return '<ul class="rank">' + "".join(out) + "</ul>"


HTML = f"""<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow, noarchive">
<title>Site summary — matthewjgonzalez.me</title>
<style>
  :root {{
    --bg:#07090f; --surface:rgba(255,255,255,0.025);
    --surface-2:rgba(255,255,255,0.04); --border:rgba(255,255,255,0.07);
    --text:#d8dce8; --muted:rgba(255,255,255,0.45);
    --dim:rgba(216,220,232,0.2); --accent:#16c1ff;
    --accent-dim:rgba(126,200,227,0.1);
  }}
  * {{ box-sizing:border-box; }}
  body {{
    margin:0; padding:2.5rem 1.5rem 4rem; background:var(--bg); color:var(--text);
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;
    line-height:1.7; -webkit-font-smoothing:antialiased;
  }}
  .wrap {{ max-width:860px; margin:0 auto; }}
  .eyebrow {{
    font-family:ui-monospace,SFMono-Regular,Menlo,monospace;
    font-size:0.6rem; letter-spacing:0.28em; text-transform:uppercase;
    color:var(--dim); display:flex; align-items:center; gap:1rem;
  }}
  .eyebrow::after {{ content:''; flex:1; height:1px; background:var(--border); }}
  h1 {{ font-size:1.6rem; font-weight:600; margin:1.1rem 0 0.3rem; line-height:1.3; }}
  .sub {{ color:var(--muted); font-size:0.92rem; margin:0 0 2.4rem; }}

  .cards {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr));
            gap:0.8rem; margin-bottom:2.6rem; }}
  .card {{ background:var(--surface); border:1px solid var(--border);
           border-radius:5px; padding:1.05rem 1.15rem; }}
  .card .n {{ font-size:1.85rem; font-weight:600; line-height:1.1; }}
  .card .k {{ font-family:ui-monospace,SFMono-Regular,Menlo,monospace;
              font-size:0.55rem; letter-spacing:0.2em; text-transform:uppercase;
              color:var(--muted); margin-top:0.45rem; }}
  .card .note {{ font-size:0.72rem; color:var(--dim); margin-top:0.3rem; }}

  h2 {{ font-size:0.62rem; font-family:ui-monospace,SFMono-Regular,Menlo,monospace;
        letter-spacing:0.24em; text-transform:uppercase; color:var(--muted);
        margin:2.4rem 0 0.9rem; }}
  .rank {{ list-style:none; margin:0; padding:0; }}
  .rank li {{ position:relative; display:flex; align-items:center;
              padding:0.5rem 0.85rem; margin-bottom:3px; border-radius:3px;
              background:var(--surface); overflow:hidden; font-size:0.87rem; }}
  .bar {{ position:absolute; inset:0 auto 0 0; background:var(--accent-dim); }}
  .lbl {{ position:relative; flex:1; min-width:0; overflow:hidden;
          text-overflow:ellipsis; white-space:nowrap; }}
  .val {{ position:relative; font-family:ui-monospace,SFMono-Regular,Menlo,monospace;
          font-size:0.78rem; color:var(--accent); padding-left:1rem; }}
  .empty {{ color:var(--dim); font-size:0.85rem; font-style:italic; margin:0; }}

  .foot {{ margin-top:3rem; padding-top:1.3rem; border-top:1px solid var(--border);
           display:flex; flex-wrap:wrap; gap:1rem; align-items:center;
           justify-content:space-between; }}
  .foot p {{ margin:0; font-size:0.72rem; color:var(--dim); }}
  a.btn {{ font-family:ui-monospace,SFMono-Regular,Menlo,monospace;
           font-size:0.62rem; letter-spacing:0.16em; text-transform:uppercase;
           color:var(--accent); background:var(--accent-dim);
           border:1px solid rgba(126,200,227,0.18); border-radius:3px;
           padding:9px 18px; text-decoration:none; white-space:nowrap; }}
  a.btn:hover {{ background:rgba(126,200,227,0.18);
                 border-color:rgba(126,200,227,0.4); }}
</style></head>
<body><div class="wrap">

  <div class="eyebrow"><span>Site summary</span></div>
  <h1>{E(lead)}</h1>
  <p class="sub">{lead_extra or "Referrer and page data will appear as visits accumulate."}</p>

  <div class="cards">
    <div class="card"><div class="n">{v7}</div><div class="k">Last 7 days</div>
      <div class="note">{h7} page views</div></div>
    <div class="card"><div class="n">{v30}</div><div class="k">Last 30 days</div>
      <div class="note">{h30} page views</div></div>
    <div class="card"><div class="n">{unique_visitors}</div><div class="k">All time</div>
      <div class="note">{valid_requests} page views</div></div>
    <div class="card"><div class="n">{bot_pct}%</div><div class="k">Was bots</div>
      <div class="note">{bot_hits} of {total_requests} hits, excluded</div></div>
  </div>

  <h2>Most viewed pages</h2>
  {rows_html(pages, "No page views recorded yet.")}

  <h2>Where visitors came from</h2>
  {rows_html(refs, "No external referrers yet — visits so far were direct.")}

  <h2>Countries</h2>
  {rows_html(places, "No location data. Add the GeoLite2 database to enable this.")}

  <div class="foot">
    <p>Generated {E(generated)}{f" &middot; busiest day {busiest[0].strftime('%d %b %Y')} with {busiest[1]} visitors" if busiest else ""}
       &middot; IP addresses are truncated before storage.</p>
    <a class="btn" href="dashboard.html">Full dashboard</a>
  </div>

</div></body></html>
"""

try:
    with open(DEST, "w", encoding="utf-8") as fh:
        fh.write(HTML)
except Exception as exc:                       # noqa: BLE001
    sys.exit(f"could not write {DEST}: {exc}")

print(f"summary written: {len(pages)} pages, {len(refs)} referrers, "
      f"{len(places)} places, {len(days)} days of data")
