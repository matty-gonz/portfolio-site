/* ─────────────────────────────────────────────────────────────
   analytics.js — first-party behaviour beacon.

   Answers the questions server logs cannot: did anyone scroll, how
   long did they stay, which project did they click, did anyone go
   for the resume or the email link.

   Sends to /e on your own domain. No third party, no cookies, no
   fingerprinting, nothing leaves the pi.

   WHAT IT SENDS
     t  type      view | end | click
     p  path      the page, without query string
     r  referrer  hostname only, never the full URL
     s  session   random id, lives in sessionStorage, dies with the tab
     d  depth     furthest scroll, as a percentage
     w  dwell     seconds on the page
     l  label     what was clicked

   WHAT IT DELIBERATELY DOES NOT SEND
     No canvas/audio/font fingerprinting — Safari and every ad blocker
     defeat it, so it makes the data worse, not better, and it is
     exactly the visitors you most want (a recruiter on a managed
     laptop) who are most likely to be blocked.
     No mouse tracking or keystrokes — that would capture what someone
     typed into a contact form before deciding whether to send it.
     No full referrer URLs — the hostname answers "did LinkedIn send
     them" without recording what else they were reading.
   ───────────────────────────────────────────────────────────── */

(function () {
  'use strict';

  // Respect Do Not Track. Costs a little data; the alternative is a
  // privacy note on the contact page that isn't quite true.
  var dnt = navigator.doNotTrack || window.doNotTrack;
  if (dnt === '1' || dnt === 'yes') return;

  if (!navigator.sendBeacon) return;          // pre-2015 browsers: skip

  var ENDPOINT = '/e';
  var path = location.pathname + (location.search.indexOf('id=') > -1
      ? '?' + (location.search.match(/id=[^&]*/) || [''])[0] : '');

  // ── session id ──────────────────────────────────────────────────
  // sessionStorage, not a cookie and not localStorage: it is cleared
  // when the tab closes, so it can group one visit's pages together
  // and cannot follow anyone across days.
  var sid;
  try {
    sid = sessionStorage.getItem('_s');
    if (!sid) {
      sid = Math.random().toString(36).slice(2, 10);
      sessionStorage.setItem('_s', sid);
    }
  } catch (e) {
    sid = 'nostore';                          // private mode: still count the view
  }

  // Hostname only. A full referrer URL can carry search terms and
  // private path info that is none of our business.
  var ref = '';
  try {
    if (document.referrer) {
      var host = new URL(document.referrer).hostname;
      if (host && host.indexOf('matthewjgonzalez.me') === -1) ref = host;
    }
  } catch (e) { /* malformed referrer, ignore */ }

  function send(params) {
    params.s = sid;
    params.p = path;
    var q = Object.keys(params)
      .filter(function (k) { return params[k] !== '' && params[k] != null; })
      .map(function (k) {
        return encodeURIComponent(k) + '=' + encodeURIComponent(params[k]);
      }).join('&');
    try { navigator.sendBeacon(ENDPOINT + '?' + q); } catch (e) { /* never break the page */ }
  }

  // ── page view ───────────────────────────────────────────────────
  send({ t: 'view', r: ref });

  // ── scroll depth ────────────────────────────────────────────────
  // The single most useful signal for a portfolio: it separates
  // "they never scrolled far enough to see the project cards" from
  // "they saw them and weren't interested". Those need opposite fixes.
  var maxDepth = 0;
  function measure() {
    var h = document.documentElement.scrollHeight - window.innerHeight;
    var d = h <= 0 ? 100 : Math.round((window.scrollY / h) * 100);
    if (d > maxDepth) maxDepth = Math.min(d, 100);
  }
  measure();
  addEventListener('scroll', measure, { passive: true });

  // ── clicks worth knowing about ──────────────────────────────────
  addEventListener('click', function (ev) {
    var a = ev.target.closest && ev.target.closest('a');
    if (!a) return;
    var href = a.getAttribute('href') || '';
    var label = '';

    if (/^mailto:/i.test(href)) label = 'email';
    else if (/linkedin\.com/i.test(href)) label = 'linkedin';
    else if (/github\.com/i.test(href)) label = 'github';
    // Documents live on R2 (media.matthewjgonzalez.me), a different
    // hostname that never touches this server — so these clicks are
    // invisible in nginx logs. This is the only way to count them.
    else if (/\.(pdf|zip|step|stp|stl|xlsx|csv|docx)(\?|$)/i.test(href)) {
      label = 'download:' + (href.split('/').pop() || '').split('?')[0];
    }
    else if (/project\.html\?id=/i.test(href)) {
      label = 'project:' + (href.match(/id=([^&]*)/) || [, ''])[1];
    }
    else if (/viewer\.html/i.test(href)) label = 'viewer';

    if (label) send({ t: 'click', l: label.slice(0, 80) });
  }, true);

  // ── dwell + final depth ─────────────────────────────────────────
  // visibilitychange, not unload: unload is unreliable on mobile
  // Safari, which is where a good share of LinkedIn traffic lands.
  var start = Date.now();
  var sent = false;
  function finish() {
    if (sent) return;
    sent = true;
    measure();
    send({
      t: 'end',
      d: maxDepth,
      w: Math.min(Math.round((Date.now() - start) / 1000), 3600)
    });
  }
  addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'hidden') finish();
  });
  addEventListener('pagehide', finish);
})();
