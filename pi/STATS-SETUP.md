# Private analytics setup — `stats.matthewjgonzalez.me`

Self-hosted GoAccess report, behind Cloudflare Access, rolling 5 years.
Everything here is free and open source. Nothing asks for a card, and
nothing lapses into a paid tier.

**Run the sections in order.** Each one ends with a check — if the check
fails, stop there rather than continuing, because later steps assume the
earlier ones worked.

Target state:

| Hostname | Tunnel → | nginx block | Doc root | Who can reach it |
|---|---|---|---|---|
| `matthewjgonzalez.me` | `localhost:80` | `sites-available/default` | `/var/www/html` | everyone |
| `dev.matthewjgonzalez.me` | `localhost:8081` | `sites-available/staging` | `/var/www/staging` | you, via Access |
| `stats.matthewjgonzalez.me` | `localhost:8082` | `sites-available/stats` | `/var/www/stats` | you, via Access |

---

## 1 — On your Mac: ship the new files

The pi pulls from `main`, so these have to be promoted before the pi can
see them.

```bash
cd "$HOME/Documents/Bootstrap Studio/Portfolio Site Files"
deploy-dev
deploy
```

**Check:** wait a minute, then on the pi:

```bash
ls /var/www/html/pi/
```

You should see `stats-refresh.sh`, `nginx-stats.conf`, `nginx-log-anon.conf`,
`logrotate-nginx`.

---

## 2 — On the pi: install GoAccess

```bash
sudo apt update
sudo apt install -y goaccess
```

**Check:**

```bash
goaccess --version
```

Debian's packaged build is a little behind upstream but has everything we
use. If you ever want the newest version, GoAccess publishes its own apt
repo — not needed now.

---

## 3 — On the pi: set the clock to Eastern

nginx writes timestamps in the machine's local time. If the pi is on UTC,
every chart will be shifted by 4–5 hours and your "peak traffic hour" will
be wrong. Fixing the clock is better than correcting for it later.

```bash
timedatectl                                  # what is it now?
sudo timedatectl set-timezone America/New_York
```

**Check:** `date` prints the actual current time where you are.

> Existing log lines keep their old timestamps. Only new entries are
> affected, so the first few hours of data may look slightly odd at the
> boundary. This resolves itself.

---

## 4 — On the pi: real visitor IPs + updated deny rules

`harden.conf` gained the `set_real_ip_from` block and a `/pi/` deny rule.
Reinstall it:

```bash
sudo curl -fsSL \
  https://raw.githubusercontent.com/matty-gonz/portfolio-site/main/pi/harden.conf \
  -o /etc/nginx/snippets/harden.conf

sudo nginx -t && sudo systemctl reload nginx
```

**Check:** confirm the config leak is closed —

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://matthewjgonzalez.me/pi/harden.conf
```

Should print `404`. Before this change it printed `200` and served your
server config to anyone who asked.

---

## 5 — On the pi: anonymize IPs before they're written

Do this **before** step 6, so no complete address is ever written to disk.

Step 4 makes nginx start recording real visitor IPs where it previously
only ever saw `127.0.0.1`. That's a genuine change in what you're
responsible for: IP addresses are personal data, and a 5-year window
means five years of them on an SD card in your room.

This is also what makes long retention defensible in the first place —
keeping truncated addresses for years is a very different proposition
from keeping complete ones.

This step truncates them at write time — `203.0.113.45` is stored as
`203.0.113.0`. Nothing sensitive ever lands on the card, so there's
nothing to protect, leak, or lose with the hardware.

You still get accurate unique-visitor counts and city-level geolocation.
What you give up is identifying one specific visitor from the pi — and
Cloudflare still sees full addresses and is where blocking happens
anyway, so in practice you lose very little.

```bash
sudo curl -fsSL \
  https://raw.githubusercontent.com/matty-gonz/portfolio-site/main/pi/nginx-log-anon.conf \
  -o /etc/nginx/conf.d/log-anon.conf

sudo nginx -t
```

`nginx -t` must pass before you continue. If it complains about `map`,
the file landed somewhere other than `conf.d/` — `map` is only legal in
the http context.

---

## 6 — On the pi: give the live site its own log

Every site currently writes into the same `access.log`, so there's no way
to report on the portfolio alone.

```bash
sudo nano /etc/nginx/sites-available/default
```

Inside the `server { }` block, add — note the `anonymized` at the end,
which selects the format defined in step 5:

```nginx
access_log /var/log/nginx/portfolio.access.log anonymized;
```

Then:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

**Check — this is the important one.** Visit your site in a browser, then:

```bash
sudo tail -3 /var/log/nginx/portfolio.access.log
```

Read the first field on each line. You want an address **ending in `.0`**,
like `203.0.113.0`. That confirms both changes at once:

| What you see | What it means |
|---|---|
| `203.0.113.0` | Correct. Real visitor, anonymized. |
| `127.0.0.1` | Step 4 didn't apply. Every visitor counts as one person. |
| `203.0.113.45` | Step 5 didn't apply. Full IPs are being stored. |

Don't continue until you see an address ending in `.0`. Fixing it later
means the logs written in between still contain complete addresses.

---

## 7 — On the pi: 5-year log retention

```bash
sudo cp /etc/logrotate.d/nginx /etc/logrotate.d/nginx.backup
sudo curl -fsSL \
  https://raw.githubusercontent.com/matty-gonz/portfolio-site/main/pi/logrotate-nginx \
  -o /etc/logrotate.d/nginx
```

**Check — dry run, changes nothing:**

```bash
sudo logrotate -d /etc/logrotate.d/nginx
```

Read the output for errors. If anything looks wrong:
`sudo cp /etc/logrotate.d/nginx.backup /etc/logrotate.d/nginx`

**Changing the window later** is one number: `rotate 260` (weeks) in
`/etc/logrotate.d/nginx`. The report window follows automatically, since
it's built from whatever logs still exist. `--keep-last` in
`stats-refresh.sh` is only a safety net and should be set to match.

At your traffic this is roughly 130 MB compressed over 5 years, so disk
isn't a real constraint. Check anytime with `du -sh /var/log/nginx`.

---

## 8 — On the pi: install the report generator

Two files: the generator, and the summary builder that turns GoAccess's
output into readable English.

```bash
sudo curl -fsSL \
  https://raw.githubusercontent.com/matty-gonz/portfolio-site/main/pi/stats-refresh.sh \
  -o /usr/local/bin/stats-refresh
sudo chmod 755 /usr/local/bin/stats-refresh

sudo curl -fsSL \
  https://raw.githubusercontent.com/matty-gonz/portfolio-site/main/pi/stats-summary.py \
  -o /usr/local/bin/stats-summary
sudo chmod 755 /usr/local/bin/stats-summary

sudo curl -fsSL \
  https://raw.githubusercontent.com/matty-gonz/portfolio-site/main/pi/stats-exclude.sh \
  -o /usr/local/bin/stats-exclude
sudo chmod 755 /usr/local/bin/stats-exclude

sudo mkdir -p /var/www/stats
sudo chown www-data:www-data /var/www/stats
```

**Check — run it by hand:**

```bash
sudo /usr/local/bin/stats-refresh
ls -lh /var/www/stats/
```

You want **two** files: `index.html` (the plain-English summary, your
landing page) and `dashboard.html` (the full GoAccess report, linked from
the bottom of the summary).

If it says "no logs matching", go back to step 6. If it says
`stats-summary not installed`, the second curl didn't land — the
dashboard still publishes, so nothing is broken, you just don't get the
summary.

> The summary is deliberately non-fatal. If it ever fails, the dashboard
> still updates and the old summary stays put, rather than a formatting
> bug costing you the whole report.

---

## 9 — On the pi: country data (optional)

Skip this if you want; everything else works without it. Free, but needs a
MaxMind account signup.

Create a free account at `https://www.maxmind.com/en/geolite2/signup`,
download **GeoLite2-City**, then:

```bash
sudo mkdir -p /var/lib/GeoIP
# copy the .mmdb file to /var/lib/GeoIP/GeoLite2-City.mmdb
sudo /usr/local/bin/stats-refresh
```

The script auto-detects the database and adds a Geo Location panel. No
edits needed.

---

## 10 — On the pi: the nginx block for the stats site

```bash
sudo curl -fsSL \
  https://raw.githubusercontent.com/matty-gonz/portfolio-site/main/pi/nginx-stats.conf \
  -o /etc/nginx/sites-available/stats
sudo ln -sf /etc/nginx/sites-available/stats /etc/nginx/sites-enabled/stats
sudo nginx -t && sudo systemctl reload nginx
```

**Check — it works locally but is NOT exposed to your network:**

```bash
curl -s -o /dev/null -w 'loopback: %{http_code}\n' http://127.0.0.1:8082/
curl -s -o /dev/null -w 'LAN:      %{http_code}\n' http://$(hostname -I | awk '{print $1}'):8082/ --max-time 5
```

Want: loopback `200`, LAN **fails to connect**. A LAN result of `200` means
it's listening on all interfaces — stop and re-check the `listen` lines.

---

## 11 — On the pi: schedule it

```bash
sudo crontab -e
```

Add:

```cron
*/5 * * * * /usr/local/bin/stats-refresh >/dev/null 2>&1
```

Every 5 minutes, which is cheap because the script checks first whether
anything changed. It compares the live log's size and modification time
against the last successful run and exits immediately if they match — so
a run with no new visitors costs one `stat()` call, not a rebuild. On a
quiet night that's ~288 no-ops a day and no measurable load.

When there *is* new traffic it does the full rebuild, which is about a
second today and grows with retention. If it ever feels slow years from
now, raise the interval — or switch to GoAccess's incremental mode
(`--persist` / `--restore` / `--db-path`), though that moves retention
into a database and reintroduces the pruning problem this design avoids.

Force a rebuild any time with `sudo stats-refresh --force`.

---

## 12 — Cloudflare: DNS + tunnel

**DNS** — add a CNAME for `stats` pointing at your tunnel, exactly like the
`dev` record. Proxy status must be **Proxied** (orange cloud). Grey cloud
means traffic bypasses Cloudflare, and Access can't protect what it never
sees.

**Tunnel** — add an ingress rule alongside the existing two:

| Hostname | Service |
|---|---|
| `stats.matthewjgonzalez.me` | `http://localhost:8082` |

---

## 13 — Cloudflare Access: lock it down

Zero Trust dashboard → **Access → Applications → Add an application**
→ *Self-hosted*.

- **Name:** Portfolio stats
- **Domain:** `stats.matthewjgonzalez.me`
- **Policy name:** Just me
- **Action:** Allow
- **Include → Emails →** your email address only

Same one-time-code flow as the dev site.

**Check, and do this one properly:**

1. Open `https://stats.matthewjgonzalez.me` in a **private window**.
   You must get the Cloudflare login page, *not* the report.
2. Log in with the emailed code. Now you should see the report.

If step 1 shows you the report without asking for a login, the Access
policy isn't attached to the hostname. Fix that before leaving it up —
the page contains visitor IP prefixes and your traffic patterns.

---

## Leaving yourself out of the stats

Your own visits will otherwise dominate the numbers early on.

```bash
sudo stats-exclude me      # detect this network and exclude it
sudo stats-exclude list    # show the list and whether it's active
sudo stats-exclude off     # keep the list, count everyone again
sudo stats-exclude on
sudo stats-exclude clear   # empty it
sudo stats-refresh --force # apply immediately
```

`me` works because your Mac and the pi share one public IP behind your
home router — so the pi asking "what's my address?" gets yours too.

**Only run `me` at home.** Logs store truncated addresses, so exclusions
are `/24`-wide. On your home ISP that's you and maybe a few neighbours.
On campus wifi it would cover thousands of people and quietly delete real
visitors from your stats. If that happens: `sudo stats-exclude clear`.

Your home IP changes occasionally; re-run `me` when it does. The
dashboard's **Excl. IP Hits** box shows how many requests were dropped,
which is how you can tell it's still matching.

---

## Troubleshooting

**Report exists but shows almost nothing**
Normal at first — it only counts traffic since step 6. Give it a day.

**Every visitor is `127.0.0.1`**
Step 4 didn't apply. Confirm `harden.conf` is `include`d inside the
`server { }` block of `sites-available/default`, not just sitting in
`snippets/`.

**Numbers look far lower than Cloudflare's**
Expected, and the point. Cloudflare counts every request for every image
and font plus bots; this counts human page loads with crawlers stripped.

**Report stopped updating**
```bash
sudo /usr/local/bin/stats-refresh    # run manually, read the error
sudo grep CRON /var/log/syslog | tail
```

**Disk filling up**
```bash
du -sh /var/log/nginx
```
Lower `rotate 260` in `/etc/logrotate.d/nginx` if needed. The report window
shrinks to match automatically.

**Backing up the history**
Long retention on an SD card is only as durable as the card, and cards
fail without warning. If the data matters to you, copy it off the pi
periodically — from your Mac:
```bash
rsync -avz --ignore-existing pi@<pi-address>:/var/log/nginx/portfolio.access.log.* ~/portfolio-logs/
```
Rotated files never change once written, so `--ignore-existing` makes
repeat runs cheap.

---

## What this costs

| Component | Cost |
|---|---|
| GoAccess | Free, open source (MIT) |
| Cloudflare Access | Free up to 50 users |
| Cloudflare Tunnel | Free |
| DNS record | Free |
| MaxMind GeoLite2 | Free, account required |
| Disk on the pi | Yours already |

No recurring charges, no trials.
