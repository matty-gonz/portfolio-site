# hello
# Staging platform setup

One-time setup. Run the sections in order — the `dev` branch has to exist
on GitHub before the pi can clone it.

Current state, for reference:

| Hostname | Tunnel → | nginx block | Doc root | Branch |
|---|---|---|---|---|
| `matthewjgonzalez.me` | `localhost:80` | `sites-available/default` | `/var/www/html` | `main` |
| `dev.matthewjgonzalez.me` | `localhost:8081` | `sites-available/staging` | `/var/www/staging` | `dev` |

DNS, the Cloudflare tunnel, and both nginx blocks were already correct.
The only thing missing was a git clone behind `/var/www/staging` and a
puller feeding it.

---

## 1 — On your Mac: create the `dev` branch

```bash
cd "$HOME/Documents/Bootstrap Studio/Portfolio Site Files"

git add -A
git commit -m "add staging deploy tooling"
git push origin main

git checkout -b dev
git push -u origin dev
```

You now stay on `dev` permanently. `main` only ever moves via `deploy`.

---

## 2 — On the pi: install the puller

```bash
sudo curl -fsSL \
  https://raw.githubusercontent.com/matty-gonz/portfolio-site/main/pi/site-pull.sh \
  -o /usr/local/bin/site-pull
sudo chmod 755 /usr/local/bin/site-pull
```

Or paste `pi/site-pull.sh` in by hand with `sudo nano /usr/local/bin/site-pull`.

Then let root run git in both doc roots without the dubious-ownership error:

```bash
sudo git config --global --add safe.directory /var/www/html
sudo git config --global --add safe.directory /var/www/staging
```

---

## 3 — On the pi: make staging a real clone

`/var/www/staging` is currently a hand-copied folder. Replace it:

```bash
sudo rm -rf /var/www/staging
sudo git clone -b dev https://github.com/matty-gonz/portfolio-site.git /var/www/staging
sudo chown -R www-data:www-data /var/www/staging
```

---

## 4 — On the pi: replace the cron job

The old job runs `/var/www/html/deploy.sh`, which contains itself twice and
therefore pulls and reloads nginx **two** times per minute. Remove it and add
one line per site:

```bash
sudo crontab -e
```

Delete this line:

```
* * * * * /var/www/html/deploy.sh >> /var/log/deploy.log 2>&1
```

Add these two:

```
* * * * * /usr/local/bin/site-pull /var/www/html    main >> /var/log/deploy.log 2>&1
* * * * * /usr/local/bin/site-pull /var/www/staging dev  >> /var/log/deploy.log 2>&1
```

Then delete the old script from both web roots:

```bash
sudo rm -f /var/www/html/deploy.sh /var/www/staging/deploy.sh
sudo truncate -s 0 /var/log/deploy.log
```

Truncating the log is safe — the new puller only writes on an actual deploy or
an actual failure, so it stays readable instead of growing by 1,440 lines a day.

---

## 5 — On the pi: block `.git` from the web

Right now `https://matthewjgonzalez.me/.git/config` returns `200`.

```bash
sudo curl -fsSL \
  https://raw.githubusercontent.com/matty-gonz/portfolio-site/main/pi/harden.conf \
  -o /etc/nginx/snippets/harden.conf
```

Add this line inside the `server { }` block of **both** config files:

```
include snippets/harden.conf;
```

```bash
sudo nano /etc/nginx/sites-available/default   # put it near the `root` line
sudo nano /etc/nginx/sites-available/staging   # same
sudo nginx -t && sudo nginx -s reload
```

---

## 6 — On your Mac: replace the deploy alias

Open `~/.zshrc` and **delete** this line:

```
alias deploy="cd /Users/mattyg/Documents/Bootstrap\ Studio/Portfolio\ Site\ Files && git add . && git commit -m \"update\" && git push"
```

Replace it with:

```
source "$HOME/Documents/Bootstrap Studio/Portfolio Site Files/pi/portfolio.zsh"
```

Then `source ~/.zshrc`.

---

## Verify

```bash
# staging is a clone on the right branch
ssh american-pi 'cd /var/www/staging && git branch -vv'

# .git is no longer reachable — both should be 404
curl -sI https://matthewjgonzalez.me/.git/config     | head -1
curl -sI https://dev.matthewjgonzalez.me/.git/config | head -1

# old script is gone
curl -sI https://matthewjgonzalez.me/deploy.sh | head -1
```

End-to-end test: change something small, run `deploy-dev`, wait a minute, load
`dev.matthewjgonzalez.me` and confirm the change is there and
`matthewjgonzalez.me` is unchanged. Then run `deploy` and confirm it lands live.

---

## Day-to-day

```
deploy-dev             # push work to dev.matthewjgonzalez.me
deploy-dev "message"   # ...with a real commit message
deploy                 # promote dev to live (asks for confirmation)
deploy-rollback        # revert the last live commit
```
