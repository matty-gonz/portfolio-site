#!/usr/bin/env python3
"""
stats-summary — turn GoAccess JSON into a page a human can read.

Install to /usr/local/bin/stats-summary (mode 755).
Called by stats-refresh:
    stats-summary <input.json> <output.html> [dashboard.html]

The optional third argument is the GoAccess dashboard, which gets a
"back to summary" link injected into it. GoAccess has no idea our
summary page exists, so without this the dashboard is a dead end you
can only leave with the browser back button.

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
import os
import sys
import html
from datetime import datetime, timedelta

# ── input ────────────────────────────────────────────────────────────

if len(sys.argv) not in (3, 4, 5):
    sys.exit("usage: stats-summary <input.json> <output.html> "
             "[dashboard.html] [events.log]")

SRC, DEST = sys.argv[1], sys.argv[2]
DASH = sys.argv[3] if len(sys.argv) >= 4 else None
EVENTS = sys.argv[5 - 1] if len(sys.argv) == 5 else "/var/log/nginx/events.log"

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

# Defined once, here, because both the event windows and the heatmap
# need it — and they need the SAME value. Two calls to now() straddling
# midnight would put them in different days.
_now = datetime.now().astimezone()

# ── visitors over time ───────────────────────────────────────────────
# The visitors panel is one row per day, "data" holding a date string.
# Format follows --date-spec (default: 18/Aug/2026).

days = []
for row in panel("visitors"):
    raw = str(row.get("data", "")).strip()
    when = None
    # The JSON output uses GoAccess's internal date key (20260818),
    # NOT the 18/Aug/2026 form shown in the HTML dashboard. Getting this
    # wrong is silent: general totals stay correct while every per-day
    # number reads zero. %Y%m%d must therefore come first.
    for fmt in ("%Y%m%d", "%Y%m%d%H", "%Y%m%d%H%M",
                "%d/%b/%Y", "%d/%b/%Y:%H", "%Y-%m-%d"):
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

# ── cities ───────────────────────────────────────────────────────────
# GoAccess only ever breaks the Geo Location panel down to country.
# City lives on each row of the HOSTS panel instead, so we aggregate it
# back up ourselves.
#
# Key names have moved between GoAccess versions, so try the likely
# ones rather than assuming. If none are present the section simply
# doesn't render — no city database, no section, no error.

CITY_KEYS = ("city", "geolocation", "location", "country")
JUNK = {"", "-", "n/a", "na", "unknown", "not found",
        "localhost", "private ip", "reserved"}

def tidy_place(label):
    """'Madrid, Madrid' -> 'Madrid'; 'US United States' -> 'United States'."""
    for sep in ("->", " | "):
        if sep in label:
            label = label.split(sep)[-1].strip()
    # GoAccess prefixes countries with the ISO code: "US United States".
    parts = label.split(None, 1)
    if len(parts) == 2 and len(parts[0]) == 2 and parts[0].isupper():
        label = parts[1]
    # City and region are often identical ("Madrid, Madrid").
    chunks = [c.strip() for c in label.split(",") if c.strip()]
    if len(chunks) == 2 and chunks[0].lower() == chunks[1].lower():
        label = chunks[0]
    return label


def collect_cities(metric):
    out = {}
    for row in panel("hosts"):
        label = ""
        for key in CITY_KEYS:
            val = row.get(key)
            if isinstance(val, str) and val.strip().lower() not in JUNK:
                label = val.strip()
                break
        if not label:
            continue
        out[tidy_place(label)] = out.get(tidy_place(label), 0) + count(row, metric)
    return out


# Hosts can legitimately report 0 visitors while still having hits — a
# crawler that was filtered out of the visitor count, for instance. If
# every city comes back zero, rank by hits instead so the section still
# says something true rather than a column of noughts.
cities = collect_cities("visitors")
if cities and not any(cities.values()):
    cities = collect_cities("hits")

cities = sorted(cities.items(), key=lambda kv: kv[1], reverse=True)[:6]

# Countries come from the geolocation panel and carry the same ISO
# prefix, so tidy those too.
places = [(tidy_place(str(name)), val) for name, val in places]

# ── behaviour events ─────────────────────────────────────────────────
# events.log is written by nginx from the /e beacon (assets/js/analytics.js).
#
# The important property: these events only exist if a browser ran
# JavaScript. Almost no crawler does. So where the access log needs
# guesswork to separate people from bots, this file is people by
# construction — which is why the headline numbers below come from here
# and not from GoAccess.

EV_FIELDS = 11


def unq(v):
    if v in ("", "-", None):
        return ""
    try:
        from urllib.parse import unquote
        return unquote(v)
    except Exception:                          # noqa: BLE001
        return v


def parse_ts(raw):
    try:
        return datetime.fromisoformat(raw)
    except ValueError:
        for fmt in ("%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%dT%H:%M:%S"):
            try:
                return datetime.strptime(raw, fmt)
            except ValueError:
                continue
    return None


sessions = {}
ev_count = 0
excluded_events = 0

if EVENTS and os.path.exists(EVENTS):
    try:
        with open(EVENTS, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < EV_FIELDS:
                    continue
                ts, host, ip, typ, path_, ref_, sid, dep, dwl, lab, ua = parts[:EV_FIELDS]

                # Staging traffic is your own testing. Counting it would
                # mean every experiment inflates your real numbers.
                if host.startswith("dev.") or host.startswith("staging."):
                    continue

                when = parse_ts(ts)
                if not when or not sid or sid == "-":
                    continue

                # Self-excluded browser (visited /?me=1). Marked on the
                # session id rather than by IP, because IP exclusion on
                # shared apartment wifi would take out the neighbours too.
                if sid.startswith("x-"):
                    excluded_events += 1
                    continue

                ev_count += 1
                s = sessions.setdefault(sid, {
                    "first": when, "last": when, "pages": {},
                    "clicks": [], "campaign": "", "ref": "", "ua": ua,
                })
                s["first"] = min(s["first"], when)
                s["last"] = max(s["last"], when)

                p = unq(path_) or "/"
                lab = unq(lab)

                if typ == "view":
                    s["pages"].setdefault(p, {"depth": 0, "dwell": 0})
                    if ref_ not in ("", "-"):
                        s["ref"] = s["ref"] or unq(ref_)
                    if lab.startswith("from:"):
                        s["campaign"] = s["campaign"] or lab[5:]
                elif typ == "end":
                    rec = s["pages"].setdefault(p, {"depth": 0, "dwell": 0})
                    try:
                        rec["depth"] = max(rec["depth"], int(dep))
                    except (TypeError, ValueError):
                        pass
                    try:
                        rec["dwell"] = max(rec["dwell"], int(dwl))
                    except (TypeError, ValueError):
                        pass
                elif typ == "click" and lab:
                    s["clicks"].append(lab)
    except Exception as exc:                   # noqa: BLE001
        print(f"warning: could not read {EVENTS}: {exc}", file=sys.stderr)


def sess_in(days_back, span=7):
    """Sessions whose visit started in a window `days_back` weeks ago."""
    if not sessions:
        return []
    end = _now - timedelta(days=days_back)
    start = end - timedelta(days=span)
    return [s for s in sessions.values() if start < s["first"] <= end]


this_week = sess_in(0)
last_week = sess_in(7)

# "Engaged" = got past a glance. Either read something for 10+ seconds
# or scrolled at least halfway down a page. Deliberately generous: the
# point is to separate real reading from an accidental click, not to
# set a high bar.
def engaged(s):
    return any(p["dwell"] >= 10 or p["depth"] >= 50 for p in s["pages"].values())


eng_week = [s for s in this_week if engaged(s)]

# ── funnel ───────────────────────────────────────────────────────────
# The question underneath your whole site: do people get past the
# front page, and does anyone end up trying to contact you.
def opened_project(s):
    return any("project.html" in p for p in s["pages"]) or \
           any(c.startswith("project:") for c in s["clicks"])


def reached_out(s):
    return any(c in ("email", "linkedin", "github") or c.startswith("download:")
               for c in s["clicks"]) or any("contact" in p for p in s["pages"])


all_sess = list(sessions.values())
funnel = [
    ("Arrived",              len(all_sess)),
    ("Read something",       sum(1 for s in all_sess if engaged(s))),
    ("Opened a project",     sum(1 for s in all_sess if opened_project(s))),
    ("Clicked contact/file", sum(1 for s in all_sess if reached_out(s))),
]

# ── per-page engagement ──────────────────────────────────────────────
page_eng = {}
for s in all_sess:
    for p, rec in s["pages"].items():
        e = page_eng.setdefault(prettify(p), {"n": 0, "dwell": [], "depth": []})
        e["n"] += 1
        if rec["dwell"]:
            e["dwell"].append(rec["dwell"])
        if rec["depth"]:
            e["depth"].append(rec["depth"])

# ── clicks, campaigns, real referrers ────────────────────────────────
clicks, downloads, campaigns, ev_refs = {}, {}, {}, {}
for s in all_sess:
    for c in s["clicks"]:
        if c.startswith("download:"):
            downloads[c[9:]] = downloads.get(c[9:], 0) + 1
        elif c.startswith("project:"):
            continue                            # already in page stats
        else:
            clicks[c] = clicks.get(c, 0) + 1
    if s["campaign"]:
        campaigns[s["campaign"]] = campaigns.get(s["campaign"], 0) + 1
    if s["ref"]:
        ev_refs[s["ref"]] = ev_refs.get(s["ref"], 0) + 1

HAS_EVENTS = bool(sessions)


# ── headline sentence ────────────────────────────────────────────────

def plural(n, one, many=None):
    return one if n == 1 else (many or one + "s")


if HAS_EVENTS:
    n = len(this_week)
    lead = (f"{n} {plural(n, 'person', 'people')} visited this week."
            if n else "Nobody visited this week.")
    bits = []
    prev = len(last_week)
    if prev or n:
        if prev == 0:
            bits.append("Nothing to compare against last week yet.")
        else:
            change = round((n - prev) / prev * 100)
            word = "up" if change > 0 else ("down" if change < 0 else "level")
            bits.append(f"That's {word}"
                        + (f" {abs(change)}%" if change else "")
                        + f" on last week's {prev}.")
    if eng_week:
        bits.append(f"{len(eng_week)} of them actually read something.")
elif v7:
    lead = f"{v7} {plural(v7, 'person', 'people')} visited in the last 7 days."
    bits = []
else:
    lead = "No visits recorded yet."
    bits = []

if not HAS_EVENTS:
    if refs:
        bits.append(f"Most arrivals came from {html.escape(refs[0][0])}.")
    if pages:
        bits.append(f"{html.escape(pages[0][0])} was the most viewed page.")
lead_extra = " ".join(bits)

E = html.escape

# 12-hour clock with the zone name. astimezone() picks up the pi's
# configured timezone (set to America/New_York in step 3), so %Z prints
# EDT or EST correctly and follows daylight saving without help.
# %-I / %-d strip leading zeros — glibc extensions, fine on the pi.
try:
    generated = _now.strftime("%A %-d %B %Y at %-I:%M %p %Z").strip()
except ValueError:                     # non-glibc strftime
    generated = _now.strftime("%A %d %B %Y at %I:%M %p %Z").strip()


# ── daily heatmap ────────────────────────────────────────────────────
# A calendar grid, one square per day, darker to brighter with more
# visitors. Reads at a glance in a way a table of numbers doesn't:
# quiet stretches, the spike after you post something, weekly rhythm.

def heatmap_html(day_rows, min_weeks=13, max_weeks=53):
    if not day_rows:
        return '<p class="empty">No data yet — this fills in a square per day.</p>'

    by_date = {d.date(): v for d, v, _ in day_rows}
    peak = max(by_date.values()) if by_date else 0

    last = max(max(by_date), _now.date())
    # Extend to the end of the current week so the grid ends on a full
    # column (weeks run Sunday..Saturday; weekday() has Saturday == 5).
    last += timedelta(days=(5 - last.weekday()) % 7)

    span_weeks = ((last - min(by_date)).days // 7) + 2
    weeks = max(min_weeks, min(span_weeks, max_weeks))
    first = last - timedelta(days=weeks * 7 - 1)

    def level(n):
        if not n:
            return 0
        if not peak:
            return 1
        return min(4, int(n / peak * 4) + 1)

    cells = []
    day = first
    while day <= last:
        n = by_date.get(day, 0)
        # Future days in the current week get no tile at all, so the
        # grid doesn't imply we measured days that haven't happened.
        if day > _now.date():
            cells.append('<i class="c blank"></i>')
        else:
            label = f"{day.strftime('%a %-d %b %Y')}: {n} visitor{'' if n == 1 else 's'}"
            cells.append(f'<i class="c l{level(n)}" title="{E(label)}"></i>')
        day += timedelta(days=1)

    legend = "".join(f'<i class="c l{i}"></i>' for i in range(5))
    return (
        f'<div class="hm" style="grid-template-columns:repeat({weeks},11px)">'
        + "".join(cells) +
        '</div>'
        f'<div class="hm-foot"><span>{E(first.strftime("%-d %b %Y"))}</span>'
        f'<span class="hm-key">less {legend} more</span>'
        f'<span>{E(last.strftime("%-d %b %Y"))}</span></div>'
    )


# ── time of day ──────────────────────────────────────────────────────

def hours_html():
    rows = panel("visit_times")
    if not rows:
        return ""
    buckets = {}
    for row in rows:
        raw = str(row.get("data", "")).strip()
        digits = "".join(ch for ch in raw if ch.isdigit())[:2]
        if digits:
            buckets[int(digits)] = buckets.get(int(digits), 0) + count(row, "visitors")
    if not buckets:
        return ""
    top = max(buckets.values()) or 1
    bars = []
    for hr in range(24):
        n = buckets.get(hr, 0)
        pct = max(round(n / top * 100), 3) if n else 2
        ampm = "12a" if hr == 0 else ("12p" if hr == 12 else
                                      (f"{hr}a" if hr < 12 else f"{hr - 12}p"))
        tick = ampm if hr % 6 == 0 else ""
        bars.append(
            f'<div class="hb" title="{ampm} — {n} visitor{"" if n == 1 else "s"}">'
            f'<span style="height:{pct}%"></span><b>{tick}</b></div>'
        )
    return ('<h2>Time of day</h2><div class="hours">' + "".join(bars) + '</div>')


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


# ── engagement blocks (only when beacon data exists) ─────────────────

def funnel_html():
    if not HAS_EVENTS or not funnel[0][1]:
        return ""
    top = funnel[0][1] or 1
    rows = []
    for i, (label, n) in enumerate(funnel):
        pct = round(n / top * 100)
        drop = ""
        if i:
            prev_n = funnel[i - 1][1]
            if prev_n:
                drop = f"{round(n / prev_n * 100)}% of previous step"
        rows.append(
            f'<li><span class="bar" style="width:{max(pct, 2)}%"></span>'
            f'<span class="lbl">{E(label)}</span>'
            f'<span class="pct">{drop}</span>'
            f'<span class="val">{n}</span></li>'
        )
    return ('<h2>What visitors actually did</h2>'
            '<ul class="rank funnel">' + "".join(rows) + '</ul>'
            '<p class="hint">Every visit that ran the page script. '
            '"Read something" means 10+ seconds on a page or scrolled at '
            'least halfway.</p>')


def pages_engagement_html():
    if not HAS_EVENTS or not page_eng:
        return ""
    ranked = sorted(page_eng.items(), key=lambda kv: kv[1]["n"], reverse=True)[:8]
    top = ranked[0][1]["n"] or 1
    rows = []
    for name, e in ranked:
        avg_d = round(sum(e["dwell"]) / len(e["dwell"])) if e["dwell"] else 0
        avg_s = round(sum(e["depth"]) / len(e["depth"])) if e["depth"] else 0
        detail = []
        if avg_d:
            detail.append(f"{avg_d}s avg")
        if avg_s:
            detail.append(f"{avg_s}% scrolled")
        rows.append(
            f'<li><span class="bar" style="width:{max(round(e["n"]/top*100), 2)}%"></span>'
            f'<span class="lbl">{E(name)}</span>'
            f'<span class="pct">{E(" · ".join(detail))}</span>'
            f'<span class="val">{e["n"]}</span></li>'
        )
    return ('<h2>Pages — visits, time spent, how far down</h2>'
            '<ul class="rank">' + "".join(rows) + '</ul>')


def signal_html():
    if not HAS_EVENTS:
        return ""
    items = []
    NICE = {"email": "Clicked your email", "linkedin": "Clicked LinkedIn",
            "github": "Clicked GitHub", "viewer": "Opened a file in the viewer"}
    for k, v in sorted(clicks.items(), key=lambda kv: kv[1], reverse=True):
        items.append((NICE.get(k, k), v))
    for k, v in sorted(downloads.items(), key=lambda kv: kv[1], reverse=True):
        items.append((f"Downloaded {k}", v))
    if not items:
        return ('<h2>High-signal actions</h2>'
                '<p class="empty">No downloads or contact clicks yet. '
                'One of these is worth more than fifty home page views.</p>')
    return '<h2>High-signal actions</h2>' + rows_html(items, "")


CAMPAIGN_NICE = {
    "resume":           "Resume",
    "resume-projects":  "Resume — projects line",
    "linkedin":         "LinkedIn profile",
    "linkedin-post":    "LinkedIn post",
    "github":           "GitHub profile",
    "card":             "Business card / QR",
    "email":            "Email signature",
    "handshake":        "Handshake",
}


def nice_campaign(tag):
    """Known tags get a proper label; anything else is made readable.
    So `linkedin-post-sfrp` still renders as 'LinkedIn post — sfrp'
    rather than being dropped or shown raw."""
    if tag in CAMPAIGN_NICE:
        return CAMPAIGN_NICE[tag]
    for known in sorted(CAMPAIGN_NICE, key=len, reverse=True):
        if tag.startswith(known + "-"):
            return f"{CAMPAIGN_NICE[known]} — {tag[len(known) + 1:]}"
    return tag.replace("-", " ").replace("_", " ").capitalize()


def campaign_html():
    if not HAS_EVENTS:
        return ""
    if not campaigns:
        return ('<h2>Tagged links</h2><p class="hint">Add <code>?from=resume</code> '
                'to the link on your resume, <code>?from=linkedin</code> to your '
                'profile, <code>?from=card</code> to a QR code. Most visits arrive '
                'with no referrer at all, so tagging is the only reliable way to '
                'know which channel works.</p>')
    ranked = sorted(campaigns.items(), key=lambda kv: kv[1], reverse=True)[:8]
    return '<h2>Tagged links</h2>' + rows_html(
        [(nice_campaign(k), v) for k, v in ranked], "")


ENGAGE_HTML = (funnel_html() + pages_engagement_html()
               + signal_html() + campaign_html())

# When the beacon is live it supersedes the log-derived page list, which
# counts bots and can't measure anything that happens inside a page.
PAGES_HTML = "" if (HAS_EVENTS and page_eng) else (
    "<h2>Most viewed pages</h2>" + rows_html(pages, "No page views recorded yet."))

REF_SOURCE = sorted(ev_refs.items(), key=lambda kv: kv[1], reverse=True)[:6] \
    if (HAS_EVENTS and ev_refs) else refs

BOT_NOTE = ""
if HAS_EVENTS and total_requests:
    real = len(all_sess)
    BOT_NOTE = (f'<p class="hint">GoAccess logged {total_requests:,} requests and '
                f'{valid_requests:,} after stripping self-identified crawlers. '
                f'The beacon counted {real} real {plural(real, "visit")} — only a '
                f'browser running JavaScript can produce those, which is why this '
                f'number is the trustworthy one.</p>')

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
  .hint {{ color:var(--dim); font-size:0.72rem; line-height:1.6; margin:0.6rem 0 0; }}
  .hint code {{ font-family:ui-monospace,SFMono-Regular,Menlo,monospace;
                color:var(--accent); font-size:0.92em; }}
  .pct {{ position:relative; font-family:ui-monospace,SFMono-Regular,Menlo,monospace;
          font-size:0.62rem; color:var(--dim); padding-left:0.9rem;
          white-space:nowrap; }}
  .funnel li {{ font-size:0.9rem; }}

  /* Calendar heatmap. grid-auto-flow:column fills top-to-bottom then
     left-to-right, so each column is one Sun..Sat week. */
  .hm {{ display:grid; grid-auto-flow:column; grid-template-rows:repeat(7,11px);
         gap:3px; overflow-x:auto; padding-bottom:2px; }}
  .c {{ width:11px; height:11px; border-radius:2px; display:block;
        background:var(--surface-2); }}
  .c.blank {{ background:transparent; }}
  .c.l0 {{ background:rgba(255,255,255,0.035); }}
  .c.l1 {{ background:rgba(22,193,255,0.22); }}
  .c.l2 {{ background:rgba(22,193,255,0.42); }}
  .c.l3 {{ background:rgba(22,193,255,0.66); }}
  .c.l4 {{ background:rgba(22,193,255,0.95); }}
  .hm-foot {{ display:flex; align-items:center; justify-content:space-between;
              gap:1rem; margin-top:0.6rem; font-size:0.62rem; color:var(--dim);
              font-family:ui-monospace,SFMono-Regular,Menlo,monospace; }}
  .hm-key {{ display:flex; align-items:center; gap:3px; }}

  /* Hourly distribution */
  .hours {{ display:flex; align-items:flex-end; gap:3px; height:74px; }}
  .hb {{ flex:1; display:flex; flex-direction:column; justify-content:flex-end;
         align-items:center; height:100%; position:relative; }}
  .hb span {{ width:100%; background:rgba(22,193,255,0.42); border-radius:2px 2px 0 0;
              display:block; min-height:2px; }}
  .hb b {{ font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-weight:400;
           font-size:0.52rem; color:var(--dim); margin-top:5px; height:0.7rem;
           white-space:nowrap; }}
  .hb:hover span {{ background:rgba(22,193,255,0.85); }}

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
    <div class="card"><div class="n">{len(this_week) if HAS_EVENTS else v7}</div>
      <div class="k">This week</div>
      <div class="note">{"real visits" if HAS_EVENTS else f"{h7} page views"}</div></div>
    <div class="card"><div class="n">{len(last_week) if HAS_EVENTS else v30}</div>
      <div class="k">{"Week before" if HAS_EVENTS else "Last 30 days"}</div>
      <div class="note">{"real visits" if HAS_EVENTS else f"{h30} page views"}</div></div>
    <div class="card"><div class="n">{len(eng_week) if HAS_EVENTS else unique_visitors}</div>
      <div class="k">{"Read something" if HAS_EVENTS else "All time"}</div>
      <div class="note">{"this week" if HAS_EVENTS else f"{valid_requests} page views"}</div></div>
    <div class="card"><div class="n">{bot_pct}%</div><div class="k">Was bots</div>
      <div class="note">{bot_hits:,} of {total_requests:,} hits, excluded</div></div>
  </div>

  {BOT_NOTE}

  <h2>Visits per day</h2>
  {heatmap_html(days)}

  {ENGAGE_HTML}

  {hours_html()}

  {PAGES_HTML}

  <h2>Where visitors came from</h2>
  {rows_html(REF_SOURCE, "No external referrers yet — visits so far were direct.")}

  <h2>Countries</h2>
  {rows_html(places, "No location data. Add the GeoLite2 database to enable this.")}

  {f'<h2>Cities</h2>{rows_html(cities, "")}' if cities else ""}

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


# ── back link on the dashboard ───────────────────────────────────────
# Bottom-right and fixed, which is empty space in the GoAccess layout —
# the top is its header and the left is its sidebar, so anchoring there
# would cover controls. Styles are inline because we're injecting into
# someone else's document and must not depend on, or disturb, its CSS.

BACK_LINK = (
    '<a href="index.html" id="back-to-summary" style="'
    'position:fixed;right:18px;bottom:18px;z-index:99999;'
    'font-family:ui-monospace,SFMono-Regular,Menlo,monospace;'
    'font-size:11px;letter-spacing:0.14em;text-transform:uppercase;'
    'color:#16c1ff;background:#0b1220;'
    'border:1px solid rgba(126,200,227,0.35);border-radius:4px;'
    'padding:10px 16px;text-decoration:none;'
    'box-shadow:0 6px 22px rgba(0,0,0,0.5);'
    '">&#8592; Back to summary</a>'
)

if DASH:
    try:
        with open(DASH, encoding="utf-8", errors="replace") as fh:
            doc = fh.read()

        if "back-to-summary" in doc:
            pass                                   # already patched
        elif "</body>" in doc:
            # Insert before </body> so it can't land inside <head> or
            # break a script block partway through.
            doc = doc.replace("</body>", BACK_LINK + "</body>", 1)
            with open(DASH, "w", encoding="utf-8") as fh:
                fh.write(doc)
        else:
            # No recognisable body close — append rather than give up.
            with open(DASH, "a", encoding="utf-8") as fh:
                fh.write(BACK_LINK)
    except Exception as exc:                       # noqa: BLE001
        # Never fatal. A dashboard without a back button is a small
        # annoyance; no dashboard at all is not.
        print(f"warning: could not add back link to {DASH}: {exc}",
              file=sys.stderr)

print(f"summary written: {len(pages)} pages, {len(refs)} referrers, "
      f"{len(places)} countries, {len(cities)} cities, {len(days)} days of data, "
      f"{len(sessions)} sessions"
      + (f" ({excluded_events} self-excluded events skipped)" if excluded_events else ""))
if not days:
    print("warning: no per-day data parsed — heatmap and 7/30-day counts "
          "will read zero. Check the date format in the visitors panel.",
          file=sys.stderr)
