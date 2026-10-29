// The page-chrome watcher. Installed by the app as a user script at document
// end, main frame only, in the app's own content world, so the page's scripts
// never see it. It reports what the page pins to its top and bottom edges:
//
//   { top:    { kind: 'none' | 'bar',              color: [r, g, b] | null, guessed: Bool },
//     bottom: { kind: 'none' | 'bar' | 'floating', color: [r, g, b] | null, guessed: Bool },
//     overlay: Bool,   // a pinned box covers the viewport (a dialog, Google's AI overview)
//     atTop:   Bool,   // the document is scrolled to its top
//     height:  Number } // the viewport height in CSS px
//
// `guessed` marks a bar whose colour fell through to white: nothing opaque
// in its paint and no theme colour. The app samples the rendered edge then.
//
// A bar is a pinned box that spans the width and touches the edge: a header,
// a tab bar, a checkout bar, a cookie bar. Floating is anything else pinned
// near the edge: a button. The colour is the bar's paint, composited over
// what is behind it until opaque. It posts only when the verdict changes.
(() => {
  if (window.__pageChrome) return;

  // --- Cover pages ----------------------------------------------------
  // The app's web view reports no safe-area insets to the page, so a page
  // that asks for the whole screen (viewport-fit=cover) cannot pad itself
  // as it would in Safari and lands under the clock. Opt it out, and WebKit
  // insets it under the status bar like any other page.
  function uncover() {
    for (const meta of document.querySelectorAll('meta[name="viewport"]')) {
      const content = meta.getAttribute('content') || '';
      if (/viewport-fit\s*=\s*cover/i.test(content)) {
        meta.setAttribute('content', content.replace(/viewport-fit\s*=\s*cover/i, 'viewport-fit=contain'));
      }
    }
  }
  uncover();
  if (document.head) {
    new MutationObserver(uncover).observe(document.head, {
      childList: true, subtree: true, attributes: true, attributeFilter: ['content'],
    });
  }

  const EDGE = 2;       // touching the edge, in px
  const NEAR = 44;      // within this of the edge counts as floating
  const MIN_BAR = 20;   // a bar is at least this tall…
  const MAX_BAR = 0.4;  // …and at most this fraction of the viewport
  const SPAN = 4;       // spanning the width, slack per side

  const vw = () => window.innerWidth;
  const vh = () => window.innerHeight;

  // Up through shadow trees as well as the light one.
  const parentOf = (el) => el.parentElement || el.assignedSlot
    || (el.getRootNode() instanceof ShadowRoot ? el.getRootNode().host : null);

  // The deepest element at a point, descending into open shadow roots.
  function hit(x, y) {
    let el = document.elementFromPoint(x, y);
    while (el && el.shadowRoot) {
      const deeper = el.shadowRoot.elementFromPoint(x, y);
      if (!deeper || deeper === el) break;
      el = deeper;
    }
    return el;
  }

  function chainOf(el) {
    const chain = [];
    for (; el && el !== document.documentElement; el = parentOf(el)) chain.push(el);
    return chain;
  }

  const pinned = (el) => {
    const position = getComputedStyle(el).position;
    return position === 'fixed' || position === 'sticky';
  };
  const spans = (r) => r.left <= SPAN && r.right >= vw() - SPAN;
  const touches = (r, top) => top ? r.top <= EDGE : r.bottom >= vh() - EDGE;
  const near = (r, top) => top ? r.top <= NEAR : r.bottom >= vh() - NEAR;
  const barShaped = (r, top) => r.height >= MIN_BAR && r.height <= MAX_BAR * vh() && touches(r, top) && spans(r);
  const isOverlay = (el, r) => r.width >= 0.9 * vw() && r.height >= 0.9 * vh()
    && getComputedStyle(el).pointerEvents !== 'none';

  // One hit test at an edge: the innermost pinned ancestor is the anchor. An
  // anchor that covers the viewport is an overlay, not a bar: look inside it.
  // The bar is the outermost bar-shaped box inside the pinned one.
  function sample(x, y, top) {
    const chain = chainOf(hit(x, y));
    const i = chain.findIndex(pinned);
    if (i < 0) return { kind: 'none' };
    const anchor = chain[i];
    const anchorRect = anchor.getBoundingClientRect();
    const overlay = isOverlay(anchor, anchorRect);
    for (let k = i; k >= 0; k--) {
      if (overlay && k === i) continue;
      const r = chain[k].getBoundingClientRect();
      if (barShaped(r, top)) return { kind: 'bar', el: chain[k], hit: chain[0], overlay };
    }
    if (!overlay && near(anchorRect, top)) return { kind: 'floating', el: anchor, overlay };
    return { kind: 'none', overlay };
  }

  // Nine samples per edge: three columns, three rows (the outer rows catch
  // buttons that sit a little off the edge). A bar needs two votes.
  function edge(top) {
    const rows = top ? [EDGE, 20, 40] : [vh() - EDGE, vh() - 20, vh() - 40];
    const votes = new Map();
    let floating = null;
    let overlay = false;
    for (const y of rows) {
      for (const f of [0.1, 0.5, 0.9]) {
        const s = sample(f * vw(), y, top);
        overlay = overlay || !!s.overlay;
        if (s.kind === 'bar') {
          const v = votes.get(s.el) || { count: 0, hit: s.hit };
          v.count += 1;
          votes.set(s.el, v);
        } else if (s.kind === 'floating' && !floating) {
          floating = s.el;
        }
      }
    }
    let best = null;
    for (const [el, v] of votes) if (!best || v.count > best.count) best = { el, count: v.count, hit: v.hit };
    if (best && best.count >= 2) return { kind: 'bar', el: best.el, color: barColor(best.el, best.hit), overlay };
    if (floating) return { kind: 'floating', el: floating, color: null, overlay };
    return { kind: 'none', el: null, color: null, overlay };
  }

  // Is a pinned box covering the viewport centre? (An overlay whose edges
  // hold nothing pinned of their own.)
  function centreOverlay() {
    const chain = chainOf(hit(vw() / 2, vh() / 2));
    const i = chain.findIndex(pinned);
    return i >= 0 && isOverlay(chain[i], chain[i].getBoundingClientRect());
  }

  // --- Colour -----------------------------------------------------------

  const alphaOf = (v) => v === undefined ? 1 : v.endsWith('%') ? parseFloat(v) / 100 : parseFloat(v);

  // WebKit serialises computed colours as rgb()/rgba() or color(srgb …).
  function parseColor(s) {
    if (!s) return null;
    let m = s.match(/^rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[\s,/]+([\d.]+%?))?\s*\)$/);
    if (m) return { r: +m[1], g: +m[2], b: +m[3], a: alphaOf(m[4]) };
    m = s.match(/^color\(srgb\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)(?:\s*\/\s*([\d.]+%?))?\s*\)$/);
    if (m) return { r: 255 * +m[1], g: 255 * +m[2], b: 255 * +m[3], a: alphaOf(m[4]) };
    return null;
  }

  // Source-over: `front` painted over `back`.
  function over(front, back) {
    const a = front.a + back.a * (1 - front.a);
    if (a <= 0) return { r: 0, g: 0, b: 0, a: 0 };
    const mix = (f, b) => (f * front.a + b * back.a * (1 - front.a)) / a;
    return { r: mix(front.r, back.r), g: mix(front.g, back.g), b: mix(front.b, back.b), a };
  }

  const rgb = (c) => [c.r, c.g, c.b].map((v) => Math.max(0, Math.min(255, Math.round(v))));

  // The page's declared colour, for a bar whose own paint is see-through.
  function themeColor() {
    const metas = [...document.querySelectorAll('meta[name="theme-color"]')];
    const meta = metas.find((m) => !m.media || matchMedia(m.media).matches) || metas[0];
    if (!meta || !meta.content) return null;
    const probe = document.createElement('span');     // never inserted
    probe.style.color = meta.content;                  // normalises hex and names to rgb()
    return parseColor(probe.style.color);
  }

  // The bar's paint: its own layers from the hit element outward, keeping
  // only boxes that span the bar (a button inside it is not its paint), then
  // what is behind it up to the root, composited until opaque; then the
  // theme colour; then white. `sure` is false on the white fallback: the
  // app then samples the rendered edge instead, as Safari does.
  function barColor(bar, hitEl) {
    const barRect = bar.getBoundingClientRect();
    const layers = [];
    for (let el = hitEl; el; el = parentOf(el)) {
      const r = el.getBoundingClientRect();
      if (r.left <= barRect.left + SPAN && r.right >= barRect.right - SPAN) layers.push(el);
      if (el === bar) break;
    }
    for (let el = parentOf(bar); el; el = parentOf(el)) layers.push(el);
    let acc = null;
    for (const el of layers) {
      const c = parseColor(getComputedStyle(el).backgroundColor);
      if (!c || c.a <= 0) continue;
      acc = acc ? over(acc, c) : c;
      if (acc.a >= 0.999) return { rgb: rgb(acc), sure: true };
    }
    const theme = themeColor();
    if (theme) {
      acc = acc ? over(acc, theme) : theme;
      if (acc.a >= 0.999) return { rgb: rgb(acc), sure: true };
    }
    const white = { r: 255, g: 255, b: 255, a: 1 };
    return { rgb: rgb(acc ? over(acc, white) : white), sure: false };
  }

  // --- Verdicts and their stability --------------------------------------

  const remembered = { top: null, bottom: null };
  let seen = false;
  let lastKey = null;

  // Alive: still in the document and still anchored, itself pinned or inside
  // a pinned box (a panel inside a full-screen reel, as on YouTube Shorts).
  const alive = (el) => {
    if (!el || !el.isConnected || !chainOf(el).some(pinned)) return false;
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') return false;
    return el.getBoundingClientRect().width > 0;
  };

  // A bar lives while its element lives: a tab bar or header that a transform
  // slid off screen keeps its verdict, so nothing resizes under the finger.
  // The verdict drops when the element is gone, unpinned or hidden, or when
  // a new bar is found.
  function settle(which, found) {
    const old = remembered[which];
    const keep = old && old.el && alive(old.el)
      && (found.kind === 'none' || (found.kind === 'floating' && old.kind === 'bar'));
    if (keep) {
      remembered[which] = { ...old, overlay: found.overlay };
      return remembered[which];
    }
    remembered[which] = found;
    return found;
  }

  const pack = (v, top) => ({
    kind: v.kind === 'bar' ? 'bar' : (!top && v.kind === 'floating') ? 'floating' : 'none',
    color: v.kind === 'bar' ? v.color.rgb : null,
    guessed: v.kind === 'bar' && !v.color.sure,
  });

  // --- Addresses -----------------------------------------------------------

  // The page's address and title, for the app's memories: once at the
  // first look, then again whenever either changes, so a page reached
  // without a load (the next video on YouTube) and a title that settles
  // after the load (YouTube names its video a beat later) both reach the
  // app, which refreshes the memory. The page's scripts run in another
  // world, so `history` cannot be wrapped; both are checked on every look.
  const page = (href) => href.split('#')[0];
  let reportedAddress = null;
  let reportedTitle = null;
  // The name the memory keeps. A site that titles every page with its own
  // name (mobile YouTube: "YouTube" on every watch page) names the page in
  // its metadata instead, so og:title or the meta title wins when the
  // document title is empty or is just the site's name (og:site_name, or
  // the host's own label). Read on every look, so a page reached without a
  // load that refreshes its metadata is renamed too.
  const meta = (name) => {
    const el = document.querySelector('meta[property="' + name + '"], meta[name="' + name + '"]');
    const content = el && el.getAttribute('content');
    return content ? content.trim() : '';
  };
  // A page reached without a load may have no metadata for itself either
  // (mobile YouTube drops og:title after a tap in the feed), so the page's
  // own first heading stands in: the video's name on YouTube. Not on the
  // site's root, whose name the site's name is.
  const heading = () => {
    if (location.pathname === '/' || location.pathname === '') return '';
    const el = document.querySelector('ytm-slim-video-metadata-section-renderer h2')
      || document.querySelector('h1')
      || document.querySelector('main h2, article h2, h2');
    const text = el ? el.textContent.trim() : '';
    return text.slice(0, 200);
  };
  function pageTitle() {
    const title = (document.title || '').trim();
    const site = meta('og:site_name').toLowerCase();
    const parts = location.hostname.split('.');
    const label = (parts.length >= 2 ? parts[parts.length - 2] : parts[0] || '').toLowerCase();
    const bare = title.toLowerCase();
    if (title && bare !== site && bare !== label) return title;
    return meta('og:title') || meta('title') || heading() || title;
  }
  function reportAddress() {
    const address = page(location.href);
    const title = pageTitle();
    if (address === reportedAddress && title === reportedTitle) return;
    reportedAddress = address;
    reportedTitle = title;
    try { window.webkit.messageHandlers.pageAddress.postMessage({ url: address, title }); } catch (e) {}
  }

  // --- Audio ---------------------------------------------------------------

  // Whether anything on the page plays out loud. Media events do not bubble,
  // but a capture listener on the document sees them all, outside shadow
  // roots and iframes. Posted only when the answer changes; the count lets
  // the app tell "nothing here" from "a player it cannot see".
  let reportedAudible = null;
  let reportedMedia = null;
  function audible(el) { return !el.paused && !el.ended && !el.muted && el.volume > 0; }
  function reportAudio() {
    const media = document.querySelectorAll('video, audio');
    const playing = Array.prototype.some.call(media, audible);
    if (playing === reportedAudible && media.length === reportedMedia) return;
    reportedAudible = playing;
    reportedMedia = media.length;
    try { window.webkit.messageHandlers.pageAudio.postMessage({ audible: playing, media: media.length }); } catch (e) {}
  }
  for (const name of ['play', 'playing', 'pause', 'ended', 'emptied', 'volumechange']) {
    document.addEventListener(name, reportAudio, { capture: true, passive: true });
  }

  // --- In use ---------------------------------------------------------------

  // Whether leaving this page would lose something: a video or audio part
  // way through, or a form the user has typed into. The app keeps such a
  // page live longer than a page merely read. Posted only when it changes;
  // `form` stays set for the life of the document.
  let formTouched = false;
  let reportedUse = null;
  function partWay(el) { return el.currentTime > 0 && !el.ended; }
  function reportUse() {
    const media = Array.prototype.some.call(document.querySelectorAll('video, audio'), partWay);
    const key = (media ? 'm' : '-') + (formTouched ? 'f' : '-');
    if (key === reportedUse) return;
    reportedUse = key;
    try { window.webkit.messageHandlers.pageUse.postMessage({ media, form: formTouched }); } catch (e) {}
  }
  for (const name of ['playing', 'pause', 'seeked', 'timeupdate', 'ended', 'emptied']) {
    document.addEventListener(name, reportUse, { capture: true, passive: true });
  }
  document.addEventListener('input', (event) => {
    const el = event.target;
    if (!el || formTouched) return;
    const tag = (el.tagName || '').toLowerCase();
    if (tag === 'input' || tag === 'textarea' || tag === 'select' || el.isContentEditable) {
      formTouched = true;
      reportUse();
    }
  }, { capture: true, passive: true });

  // Where the page stands, for the app to bring it back after it has been
  // unloaded: the scroll, and how far into its first video the user was.
  function firstVideo() {
    return Array.prototype.find.call(document.querySelectorAll('video'), (v) => v.currentTime > 0) || document.querySelector('video');
  }
  function notes() {
    const scroller = document.scrollingElement;
    const video = firstVideo();
    return {
      scrollY: scroller ? scroller.scrollTop : window.scrollY,
      videoTime: video && video.currentTime > 0 ? video.currentTime : null,
    };
  }
  // The scroll goes back at once; the video seeks once one is on the page
  // and knows its length, giving up after a while if none appears.
  function restore(saved) {
    if (!saved) return;
    if (saved.scrollY > 0) {
      const scroller = document.scrollingElement;
      if (scroller) scroller.scrollTop = saved.scrollY; else window.scrollTo(0, saved.scrollY);
    }
    const time = saved.videoTime;
    if (!(time > 0)) return;
    const started = performance.now();
    const seek = () => {
      const video = document.querySelector('video');
      if (video && video.readyState >= 1) {
        if (Math.abs(video.currentTime - time) > 1) video.currentTime = time;
        return;
      }
      if (performance.now() - started < 15000) setTimeout(seek, 250);
    };
    seek();
  }

  function evaluate(force) {
    reportAddress();
    reportAudio();
    if (window.visualViewport && Math.abs(window.visualViewport.scale - 1) > 0.01) return null;
    const scroller = document.scrollingElement;
    const atTop = (scroller ? scroller.scrollTop : window.scrollY) <= 1;
    const bottom = settle('bottom', edge(false));
    const overlay = bottom.overlay || centreOverlay();
    // The top is classified at rest at the top of the page, under an overlay,
    // on the first look at a document, or once its bar is gone; otherwise the
    // last verdict stands, so headers that come and go with the scroll never
    // enter it.
    let top = remembered.top;
    if (atTop || overlay || !seen || (top && top.el && !alive(top.el))) {
      top = settle('top', edge(true));
    }
    if (!top) top = { kind: 'none', el: null, color: null };
    seen = true;
    // `height` is the page's viewport, so the app can find its edges in the
    // web view when it samples a guessed colour.
    const payload = { top: pack(top, true), bottom: pack(bottom, false), overlay, atTop, height: vh() };
    const key = JSON.stringify(payload);
    if (force || key !== lastKey) {
      lastKey = key;
      try { window.webkit.messageHandlers.pageChrome.postMessage(payload); } catch (e) {}
    }
    return payload;
  }

  // --- Triggers, coalesced ----------------------------------------------

  const REST = 200;     // a scheduled look waits until no scroll for this long
  let timer = null;
  let dirty = false;
  let lastScroll = -Infinity;
  // A look mid-scroll (a swipe between Shorts, mutations during a fling)
  // sees elements half-way across the edge; it waits for the scroll to rest.
  function schedule() {
    if (timer) { dirty = true; return; }
    timer = setTimeout(() => {
      timer = null;
      if (performance.now() - lastScroll < REST) { schedule(); return; }
      try { evaluate(false); } catch (e) {}
      if (dirty) { dirty = false; schedule(); }
    }, 150);
  }

  new MutationObserver(schedule).observe(document.documentElement, {
    childList: true, subtree: true,
    attributes: true, attributeFilter: ['class', 'style', 'hidden', 'aria-hidden', 'open'],
  });
  window.addEventListener('resize', schedule);
  if (window.visualViewport) window.visualViewport.addEventListener('resize', schedule);
  document.addEventListener('scroll', () => { lastScroll = performance.now(); }, { capture: true, passive: true });
  // A scroll has come to rest: the app may take the page's picture then.
  // At most one a few seconds, so a long read posts a handful, not hundreds.
  const REST_GAP = 3000;
  let lastRest = -Infinity;
  function rested() {
    schedule();
    const now = performance.now();
    if (now - lastRest < REST_GAP) return;
    lastRest = now;
    try { window.webkit.messageHandlers.pageRest.postMessage({}); } catch (e) {}
  }
  if ('onscrollend' in window) {
    document.addEventListener('scrollend', rested, { capture: true, passive: true });
  } else {
    let settling = null;
    document.addEventListener('scroll', () => {
      clearTimeout(settling);
      settling = setTimeout(rested, REST);
    }, { capture: true, passive: true });
  }
  window.addEventListener('load', () => setTimeout(schedule, 250));
  window.addEventListener('popstate', schedule);
  window.addEventListener('hashchange', schedule);
  window.addEventListener('pageshow', (event) => {
    if (event.persisted) { lastKey = null; reportedAudible = null; reportedMedia = null; reportedUse = null; schedule(); reportUse(); }
  });

  // --- The screen ----------------------------------------------------------

  // What the user sees, for the app's models at the moment a query starts:
  // the text in the viewport (in document order), the rest of the page's
  // text, the selection, and the links in view with their text and address.
  // Read on request only; nothing here is posted or decided.
  function inViewport(rect) {
    const height = window.innerHeight || document.documentElement.clientHeight;
    const width = window.innerWidth || document.documentElement.clientWidth;
    return rect.bottom > 0 && rect.top < height && rect.right > 0 && rect.left < width && rect.width > 0 && rect.height > 0;
  }
  function hidden(el) {
    const style = window.getComputedStyle(el);
    return style.display === 'none' || style.visibility === 'hidden' || el.closest('script, style, noscript, template, [aria-hidden="true"]') !== null;
  }
  // The page's own data: what it publishes for search engines and link
  // previews rather than draws. The canonical address, the preview tags,
  // and every JSON-LD block flattened to "dotted.key: value" lines, strings
  // and numbers only, in the page's own words. Capped at `limit` characters.
  function pageData(limit) {
    const lines = [];
    let count = 0;
    let cut = false;
    function add(key, value) {
      if (cut) return;
      const text = String(value).replace(/\s+/g, ' ').trim();
      if (!text) return;
      const line = key + ': ' + text.slice(0, 300);
      if (count + line.length > limit) { cut = true; return; }
      lines.push(line);
      count += line.length + 1;
    }
    const canonical = document.querySelector('link[rel="canonical"]');
    if (canonical && canonical.href) add('canonical', canonical.href);
    const wanted = ['og:title', 'og:description', 'og:type', 'og:site_name', 'description', 'author', 'article:published_time', 'article:author', 'video:duration', 'product:price:amount', 'product:price:currency', 'twitter:title', 'twitter:description'];
    const seen = new Set();
    for (const meta of document.querySelectorAll('meta[property], meta[name]')) {
      const key = meta.getAttribute('property') || meta.getAttribute('name');
      if (!wanted.includes(key) || seen.has(key)) continue;
      const content = meta.getAttribute('content');
      if (!content) continue;
      seen.add(key);
      add(key, content);
    }
    function flatten(prefix, value, depth) {
      if (cut || depth > 6) return;
      if (value === null || value === undefined) return;
      if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
        if (prefix) add(prefix, value);
      } else if (Array.isArray(value)) {
        value.slice(0, 12).forEach((item, index) => flatten(prefix ? prefix + '.' + index : String(index), item, depth + 1));
      } else if (typeof value === 'object') {
        for (const key of Object.keys(value)) {
          if (key === '@context') continue;
          flatten(prefix ? prefix + '.' + key : key, value[key], depth + 1);
        }
      }
    }
    for (const script of document.querySelectorAll('script[type="application/ld+json"]')) {
      try { flatten('', JSON.parse(script.textContent), 0); } catch (e) { }
    }
    if (cut) lines.push('\u2026 more');
    return lines.join('\n');
  }
  function screen(limits) {
    const visibleLimit = (limits && limits.visible) || 4000;
    const restLimit = (limits && limits.rest) || 8000;
    const itemLimit = (limits && limits.items) || 40;
    const dataLimit = (limits && limits.data) || 1500;
    const walker = document.createTreeWalker(document.body || document.documentElement, NodeFilter.SHOW_TEXT);
    const visible = [];
    const rest = [];
    let visibleCount = 0;
    let restCount = 0;
    const checked = new Map();
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const text = node.textContent.replace(/\s+/g, ' ').trim();
      if (!text) continue;
      const el = node.parentElement;
      if (!el) continue;
      let shown = checked.get(el);
      if (shown === undefined) {
        shown = !hidden(el) && inViewport(el.getBoundingClientRect());
        checked.set(el, shown);
      }
      if (shown) {
        if (visibleCount < visibleLimit) { visible.push(text); visibleCount += text.length + 1; }
      } else if (restCount < restLimit) {
        if (el.closest('script, style, noscript, template') === null) { rest.push(text); restCount += text.length + 1; }
      }
    }
    const selection = window.getSelection ? window.getSelection().toString() : '';
    const items = [];
    const seen = new Set();
    for (const a of document.querySelectorAll('a[href]')) {
      if (items.length >= itemLimit) break;
      const href = a.href;
      if (!href || !/^https?:/i.test(href) || seen.has(href)) continue;
      if (hidden(a) || !inViewport(a.getBoundingClientRect())) continue;
      const title = (a.innerText || a.textContent || a.getAttribute('aria-label') || a.title || '').replace(/\s+/g, ' ').trim();
      if (!title) continue;
      seen.add(href);
      items.push({ title: title.slice(0, 200), href });
    }
    return { visible: visible.join('\n'), rest: rest.join('\n'), selection, items };
  }

  window.__pageChrome = { evaluate, notes, restore, screen };
  schedule();
})();
