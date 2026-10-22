// The page-chrome watcher. Installed by the app as a user script at document
// end, main frame only, in the app's own content world, so the page's scripts
// never see it. It reports what the page pins to its top and bottom edges:
//
//   { top:    { kind: 'none' | 'bar',              color: [r, g, b] | null },
//     bottom: { kind: 'none' | 'bar' | 'floating', color: [r, g, b] | null },
//     overlay: Bool,   // a pinned box covers the viewport (a dialog, Google's AI overview)
//     atTop:   Bool }  // the document is scrolled to its top
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
  // theme colour; then white.
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
      if (acc.a >= 0.999) return rgb(acc);
    }
    const theme = themeColor();
    if (theme) {
      acc = acc ? over(acc, theme) : theme;
      if (acc.a >= 0.999) return rgb(acc);
    }
    const white = { r: 255, g: 255, b: 255, a: 1 };
    return rgb(acc ? over(acc, white) : white);
  }

  // --- Verdicts and their stability --------------------------------------

  const remembered = { top: null, bottom: null };
  let seen = false;
  let lastKey = null;

  const alive = (el) => {
    if (!el || !el.isConnected || !pinned(el)) return false;
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
    color: v.kind === 'bar' ? v.color : null,
  });

  function evaluate(force) {
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
    const payload = { top: pack(top, true), bottom: pack(bottom, false), overlay, atTop };
    const key = JSON.stringify(payload);
    if (force || key !== lastKey) {
      lastKey = key;
      try { window.webkit.messageHandlers.pageChrome.postMessage(payload); } catch (e) {}
    }
    return payload;
  }

  // --- Triggers, coalesced ----------------------------------------------

  let timer = null;
  let dirty = false;
  function schedule() {
    if (timer) { dirty = true; return; }
    timer = setTimeout(() => {
      timer = null;
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
  if ('onscrollend' in window) {
    document.addEventListener('scrollend', schedule, { capture: true, passive: true });
  } else {
    let settling = null;
    document.addEventListener('scroll', () => {
      clearTimeout(settling);
      settling = setTimeout(schedule, 160);
    }, { capture: true, passive: true });
  }
  window.addEventListener('load', () => setTimeout(schedule, 250));
  window.addEventListener('pageshow', (event) => {
    if (event.persisted) { lastKey = null; schedule(); }
  });

  window.__pageChrome = { evaluate };
  schedule();
})();
