# Private analytics setup — `stats.matthewjgonzalez.me`

Self-hosted GoAccess report, behind Cloudflare Access, rolling 12 months.
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

You should see `stats-refresh.sh`, `nginx-stats.conf`, `logrotate-nginx`.

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

## 5 — On the pi: give the live site its own log

Right now every site writes into the same `access.log`, so there's no way
to report on the portfolio alone.

```bash
sudo nano /etc/nginx/sites-available/default
```

Inside the `server { }` block, add:

```nginx
access_log /var/log/nginx/portfolio.access.log;
```

Then:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

**Check:** visit your site in a browser, then:

```bash
sudo tail -3 /var/log/nginx/portfolio.access.log
```

You should see your request — and crucially, the first field should be a
**real public IP, not `127.0.0.1`**. If it's still `127.0.0.1`, step 4
didn't take effect; don't continue until it's fixed, because every visitor
would be counted as the same person.

---

## 6 — On the pi: 1-year log retention

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

---

## 7 — On the pi: install the report generator

```bash
sudo curl -fsSL \
  https://raw.githubusercontent.com/matty-gonz/portfolio-site/main/pi/stats-refresh.sh \
  -o /usr/local/bin/stats-refresh
sudo chmod 755 /usr/local/bin/stats-refresh
sudo mkdir -p /var/www/stats
sudo chown www-data:www-data /var/www/stats
```

**Check — run it by hand:**

```bash
sudo /usr/local/bin/stats-refresh
ls -lh /var/www/stats/index.html
```

You want a non-empty HTML file. If it says "no logs matching", go back to
step 5.

---

## 8 — On the pi: country data (optional)

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

## 9 — On the pi: the nginx block for the stats site

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

## 10 — On the pi: schedule it

```bash
sudo crontab -e
```

Add:

```cron
*/30 * * * * /usr/local/bin/stats-refresh >/dev/null 2>&1
```

---

## 11 — Cloudflare: DNS + tunnel

**DNS** — add a CNAME for `stats` pointing at your tunnel, exactly like the
`dev` record. Proxy status must be **Proxied** (orange cloud). Grey cloud
means traffic bypasses Cloudflare, and Access can't protect what it never
sees.

**Tunnel** — add an ingress rule alongside the existing two:

| Hostname | Service |
|---|---|
| `stats.matthewjgonzalez.me` | `http://localhost:8082` |

---

## 12 — Cloudflare Access: lock it down

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

## Troubleshooting

**Report exists but shows almost nothing**
Normal at first — it only counts traffic since step 5. Give it a day.

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
Lower `rotate 365` in `/etc/logrotate.d/nginx` if needed. The report window
shrinks to match automatically.

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
