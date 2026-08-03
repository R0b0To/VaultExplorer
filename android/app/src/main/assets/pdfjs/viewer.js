/**
 * viewer.js — custom pdf.js viewer for VaultExplorer
 *
 * Renders decrypted PDF pages streamed from the vault into canvas elements.
 * Supports lazy rendering via IntersectionObserver, text-layer selection,
 * in-document search with highlighting, zoom-adaptive re-rasterization,
 * and memory cleanup of far-off-screen pages.
 *
 * This file is shared by every container that mounts a PDF — there is no
 * separate "decoy" variant. Whether the mounted volume is the normal or the
 * hidden/outer container is decided upstream (native side); this viewer only
 * ever sees a `volId` + `pdfPath` and treats them identically either way.
 *
 * Communication with the native side is through the "VaultPdfViewer"
 * JavascriptInterface injected by PdfViewerPlugin.kt.
 */
'use strict';

(async function () {
  /* ── Read PDF URL from query-string ─────────────────────────────── */
  const params  = new URLSearchParams(location.search);
  const pdfUrl  = params.get('url');

  if (!pdfUrl) { showError('No PDF URL provided.'); return; }

  /* ── Import pdf.js ──────────────────────────────────────────────── */
  let pdfjsLib;
  try {
    pdfjsLib = await import('./pdf.min.mjs');
  } catch (e) {
    showError('Failed to load PDF library: ' + (e.message || e));
    return;
  }

  // Point the worker at the intercepted URL so it's served from assets
  pdfjsLib.GlobalWorkerOptions.workerSrc =
    new URL('./pdf.worker.min.mjs', import.meta.url).href;

  const viewer         = document.getElementById('viewer');
  const loadingOverlay = document.getElementById('loading-overlay');

  /* ── Zoom-adaptive rendering ──────────────────────────────────────
   * The base raster (see BASE render below) is sized to fit-width at the
   * device's native pixel ratio — good enough for the common case and
   * cheap to keep many pages of around in memory. We deliberately do NOT
   * pre-render every page at some large fixed size "just in case" the user
   * zooms in — that wastes memory/CPU on pages that may never be zoomed.
   * Instead, once the user pinch/double-tap zooms, we re-rasterize only the
   * pages that are *currently rendered* at a higher internal resolution
   * (bounded by MAX_ZOOM_MULTIPLIER) so the bitmap stays crisp instead of
   * being stretched blurry by the browser's native zoom. The text layer
   * never needs to be rebuilt for this since its CSS size never changes —
   * only the canvas's backing resolution does.
   * ------------------------------------------------------------------ */
  const MAX_ZOOM_MULTIPLIER = 4;
  let currentZoom      = 1;
  let zoomDebounceId   = 0;

  try {
    /* ── Load the document ──────────────────────────────────────── */
    const pdf = await pdfjsLib.getDocument({
      url            : pdfUrl,
      useWorkerFetch : false,   // route all fetches through the main thread
      cMapPacked     : true,
      enableXfa      : false,
    }).promise;

    const pageCount = pdf.numPages;

    // Tell the native side the document is ready
    if (window.VaultPdfViewer) {
      VaultPdfViewer.onDocumentLoaded(pageCount);
    }

    /* ── Determine a "fit-width" scale from the first page ──────── */
    const firstPage   = await pdf.getPage(1);
    const unscaledVp  = firstPage.getViewport({ scale: 1 });
    const fitWidth    = Math.max(viewer.clientWidth - 16, 200);
    const DPR         = window.devicePixelRatio || 1;

    /* ── Create lightweight placeholders for every page ──────────── */
    const pages = [];

    for (let i = 1; i <= pageCount; i++) {
      const el = document.createElement('div');
      el.className       = 'page-container';
      el.dataset.pageNum = String(i);

      // approximate height so the scrollbar is roughly correct
      const h = (unscaledVp.height / unscaledVp.width) * fitWidth;
      el.style.width  = fitWidth + 'px';
      el.style.height = Math.floor(h) + 'px';

      viewer.appendChild(el);
      pages.push({
        num: i, el, rendered: false, rendering: false,
        textDivs: null,        // set once the text layer is built
      });
    }

    loadingOverlay.classList.add('hidden');

    /* ── Render a single page (canvas + text layer) into its container ── */
    async function renderPage(p) {
      if (p.rendered || p.rendering) return;
      p.rendering = true;

      try {
        const page       = await pdf.getPage(p.num);
        const unscaledVp = page.getViewport({ scale: 1 });
        const pageScale  = fitWidth / unscaledVp.width;
        const cssVp      = page.getViewport({ scale: pageScale });
        const zoomMult   = Math.min(currentZoom, MAX_ZOOM_MULTIPLIER);
        const canvasVp   = page.getViewport({ scale: pageScale * DPR * zoomMult });

        // Canvas at device-pixel resolution (times current zoom, capped)
        const canvas     = document.createElement('canvas');
        canvas.width     = Math.floor(canvasVp.width);
        canvas.height    = Math.floor(canvasVp.height);
        // CSS size is always the *unzoomed* logical size — native pinch/
        // double-tap zoom scales this box up; extra canvas resolution
        // above is what keeps that scaling crisp instead of blurry.
        canvas.style.width  = Math.floor(cssVp.width)  + 'px';
        canvas.style.height = Math.floor(cssVp.height) + 'px';

        // Correct the container to the true page dimensions
        p.el.style.width  = Math.floor(cssVp.width)  + 'px';
        p.el.style.height = Math.floor(cssVp.height) + 'px';

        const ctx = canvas.getContext('2d');
        await page.render({ canvasContext: ctx, viewport: canvasVp }).promise;

        p.el.innerHTML = '';
        p.el.appendChild(canvas);

        // Text layer (optional — best-effort)
        try {
          if (pdfjsLib.TextLayer) {
            const textContent = await page.getTextContent();
            const textDiv     = document.createElement('div');
            textDiv.className    = 'textLayer';
            textDiv.style.width  = Math.floor(cssVp.width)  + 'px';
            textDiv.style.height = Math.floor(cssVp.height) + 'px';

            // REQUIRED by pdf.js: without --scale-factor set to the same
            // value as the viewport's scale, the TextLayer sizes/positions
            // every span using the wrong scale, so highlighted/selected
            // text lands in the wrong place relative to the canvas glyphs
            // underneath it. This was previously never set anywhere.
            textDiv.style.setProperty('--scale-factor', String(cssVp.scale));

            const tl = new pdfjsLib.TextLayer({
              textContentSource : textContent,
              container         : textDiv,
              viewport          : cssVp,
            });
            await tl.render();
            p.el.appendChild(textDiv);
            p.textDivs = tl.textDivs;

            if (activeQuery && !highlightedPages.has(p.num)) {
              await applyHighlightsForPage(p.num);
              highlightedPages.add(p.num);
              const cur = matches[currentIndex];
              if (cur && cur.page === p.num) {
                (cur.elements || []).forEach(el => el.classList.add('current'));
              }
            }
          }
        } catch (_) { /* text selection unavailable for this page */ }

        p.rendered = true;
      } catch (e) {
        console.error('Render error page ' + p.num, e);
      } finally {
        p.rendering = false;
      }
    }

    /* ── Re-rasterize just the canvas of an already-rendered page at the
     * current zoom level. Cheaper than a full renderPage() and — crucially
     * — leaves the text layer (and any active search highlights) alone,
     * since its CSS geometry never changes with zoom. ─────────────────── */
    async function rerenderCanvasForZoom(p) {
      if (!p.rendered || p.rendering) return;
      const canvas = p.el.querySelector('canvas');
      if (!canvas) return;
      p.rendering = true;
      try {
        const page       = await pdf.getPage(p.num);
        const unscaledVp = page.getViewport({ scale: 1 });
        const pageScale  = fitWidth / unscaledVp.width;
        const zoomMult   = Math.min(currentZoom, MAX_ZOOM_MULTIPLIER);
        const canvasVp   = page.getViewport({ scale: pageScale * DPR * zoomMult });

        canvas.width  = Math.floor(canvasVp.width);
        canvas.height = Math.floor(canvasVp.height);
        const ctx = canvas.getContext('2d');
        await page.render({ canvasContext: ctx, viewport: canvasVp }).promise;
      } catch (e) {
        console.error('Zoom re-render error page ' + p.num, e);
      } finally {
        p.rendering = false;
      }
    }

    function scheduleZoomRerender() {
      clearTimeout(zoomDebounceId);
      zoomDebounceId = setTimeout(() => {
        const vv   = window.visualViewport;
        const zoom = vv ? vv.scale : 1;
        if (Math.abs(zoom - currentZoom) < 0.05) return; // ignore jitter
        currentZoom = zoom;
        for (const p of pages) {
          if (p.rendered) rerenderCanvasForZoom(p);
        }
      }, 250); // wait for the pinch/double-tap gesture to settle
    }

    if (window.visualViewport) {
      window.visualViewport.addEventListener('resize', scheduleZoomRerender, { passive: true });
    }

    /* ── Reclaim a page's canvas to save memory ─────────────────── */
    function reclaimPage(p) {
      if (!p.rendered) return;
      p.rendered  = false;
      p.textDivs  = null;
      p.el.innerHTML = '';           // drop canvas + textLayer
      // keep el.style.width/height so scroll position is stable
      highlightedPages.delete(p.num);
      for (const m of matches) {
        if (m.page === p.num) m.elements = []; // stale refs, will rebuild
      }
    }

    /* ── Observers for lazy render + memory cleanup ─────────────── */
    const renderObserver = new IntersectionObserver(entries => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        const n = parseInt(e.target.dataset.pageNum, 10);
        if (n >= 1 && n <= pages.length) renderPage(pages[n - 1]);
      }
    }, { rootMargin: '800px 0px' });

    const cleanupObserver = new IntersectionObserver(entries => {
      for (const e of entries) {
        if (e.isIntersecting) continue;          // still nearby
        const n = parseInt(e.target.dataset.pageNum, 10);
        if (n >= 1 && n <= pages.length) reclaimPage(pages[n - 1]);
      }
    }, { rootMargin: '3000px 0px' });   // reclaim beyond 3 000 px

    for (const p of pages) {
      renderObserver.observe(p.el);
      cleanupObserver.observe(p.el);
    }

    /* ── Track the current page on scroll ────────────────────────── */
    let lastReported = 0;
    let rafId        = 0;

    viewer.addEventListener('scroll', () => {
      if (rafId) return;
      rafId = requestAnimationFrame(() => {
        rafId = 0;
        const rect = viewer.getBoundingClientRect();
        const mid  = rect.top + rect.height / 2;
        let cur = 1;
        for (const p of pages) {
          const r = p.el.getBoundingClientRect();
          if (r.bottom < rect.top) { cur = p.num + 1; continue; }
          if (r.top <= mid) cur = p.num;
          if (r.top  > mid) break;
        }
        cur = Math.min(Math.max(cur, 1), pageCount);
        if (cur !== lastReported) {
          lastReported = cur;
          if (window.VaultPdfViewer) VaultPdfViewer.onPageChanged(cur);
        }
      });
    }, { passive: true });

    /* ── Expose goToPage for native calls ────────────────────────── */
    window.goToPage = function (n) {
      if (n >= 1 && n <= pages.length) {
        pages[n - 1].el.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    };

    /* ══════════════════════════════════════════════════════════════
     * Search
     *
     * getTextContent() works independently of rendering, so the full
     * document is indexed immediately on search (fast — no canvas work
     * involved). Matches are found against the *concatenated* per-page
     * text so a query can span two adjacent text items, then mapped back
     * to the specific item(s)/spans that overlap the match.
     *
     * Highlighting a match requires that page's text layer to actually
     * exist in the DOM, so off-screen pages are force-rendered on demand
     * when a search jumps to them (renderPage() doesn't require the page
     * to be visible — the IntersectionObserver is just one caller of it).
     * ══════════════════════════════════════════════════════════════ */
    const searchIndex     = new Map();   // pageNum -> { text, itemRanges }
    const highlightedPages = new Set();  // pageNum -> highlights already applied
    let activeQuery = '';
    let matches     = [];                // [{ id, page, start, end, elements }]
    let currentIndex = -1;

    async function buildSearchIndex(pageNum) {
      if (searchIndex.has(pageNum)) return searchIndex.get(pageNum);
      const page    = await pdf.getPage(pageNum);
      const content = await page.getTextContent();
      let text = '';
      const itemRanges = []; // { start, end, divIndex } — divIndex aligns
                              // 1:1 with TextLayer#textDivs (str-items only)
      let divIndex = 0;
      for (const item of content.items) {
        if (typeof item.str !== 'string') continue; // marked-content marker
        const start = text.length;
        text += item.str;
        itemRanges.push({ start, end: text.length, divIndex });
        divIndex++;
        if (item.hasEOL) text += '\n';
      }
      const entry = { text: text.toLowerCase(), itemRanges };
      searchIndex.set(pageNum, entry);
      return entry;
    }

    async function findAllMatches(query) {
      const q = query.trim().toLowerCase();
      const found = [];
      if (!q) return found;
      for (let n = 1; n <= pageCount; n++) {
        const idx = await buildSearchIndex(n);
        let from = 0;
        for (;;) {
          const at = idx.text.indexOf(q, from);
          if (at === -1) break;
          found.push({ page: n, start: at, end: at + q.length, elements: [] });
          from = at + q.length;
        }
      }
      return found;
    }

    function clearAllHighlights() {
      for (const mark of document.querySelectorAll('.pdf-search-highlight')) {
        const parent = mark.parentNode;
        if (!parent) continue;
        while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
        parent.removeChild(mark);
        parent.normalize();
      }
    }

    async function applyHighlightsForPage(pageNum) {
      const p = pages[pageNum - 1];
      if (!p || !p.rendered || !p.textDivs) return;
      const idx = searchIndex.get(pageNum);
      if (!idx) return;

      // Group overlaps by divIndex so multiple matches inside the same
      // text-layer span can be wrapped safely (right-to-left, see below).
      const byDiv = new Map();
      for (const match of matches) {
        if (match.page !== pageNum) continue;
        for (const r of idx.itemRanges) {
          const s = Math.max(r.start, match.start);
          const e = Math.min(r.end, match.end);
          if (s >= e) continue;
          const list = byDiv.get(r.divIndex) || [];
          list.push({ match, localStart: s - r.start, localEnd: e - r.start });
          byDiv.set(r.divIndex, list);
        }
      }

      for (const [divIndex, list] of byDiv) {
        const div = p.textDivs[divIndex];
        if (!div) continue;
        // Wrap right-to-left: wrapping the rightmost match first leaves the
        // original text node (and thus earlier offsets) intact for the
        // matches still to be processed.
        list.sort((a, b) => b.localStart - a.localStart);
        for (const { match, localStart, localEnd } of list) {
          const textNode = Array.prototype.find.call(
            div.childNodes, n => n.nodeType === Node.TEXT_NODE,
          );
          if (!textNode) continue;
          const len = textNode.length;
          if (localStart >= len) continue;
          const range = document.createRange();
          range.setStart(textNode, Math.max(0, Math.min(localStart, len)));
          range.setEnd(textNode, Math.max(0, Math.min(localEnd, len)));
          const mark = document.createElement('span');
          mark.className = 'pdf-search-highlight';
          try {
            range.surroundContents(mark);
            match.elements.push(mark);
          } catch (_) { /* range crossed an element boundary — skip */ }
        }
      }
    }

    async function goToMatch(i) {
      if (!matches.length) return;
      currentIndex = ((i % matches.length) + matches.length) % matches.length;
      const match = matches[currentIndex];

      if (!pages[match.page - 1].rendered) await renderPage(pages[match.page - 1]);
      if (!highlightedPages.has(match.page)) {
        await applyHighlightsForPage(match.page);
        highlightedPages.add(match.page);
      }

      for (const el of document.querySelectorAll('.pdf-search-highlight.current')) {
        el.classList.remove('current');
      }
      for (const el of match.elements) el.classList.add('current');
      if (match.elements[0]) {
        match.elements[0].scrollIntoView({ block: 'center', inline: 'center' });
      }

      if (window.VaultPdfViewer) {
        VaultPdfViewer.onSearchResult(currentIndex + 1, matches.length);
      }
    }

    window.searchText = async function (query) {
      activeQuery = query || '';
      clearAllHighlights();
      highlightedPages.clear();
      for (const m of matches) m.elements = [];
      matches = [];
      currentIndex = -1;

      if (!activeQuery.trim()) {
        if (window.VaultPdfViewer) VaultPdfViewer.onSearchResult(0, 0);
        return;
      }

      matches = await findAllMatches(activeQuery);
      matches.forEach((m, i) => { m.id = i; });

      if (!matches.length) {
        if (window.VaultPdfViewer) VaultPdfViewer.onSearchResult(0, 0);
        return;
      }
      await goToMatch(0);
    };

    window.findNext     = function () { goToMatch(currentIndex + 1); };
    window.findPrevious = function () { goToMatch(currentIndex - 1); };

    window.clearSearch = function () {
      activeQuery = '';
      clearAllHighlights();
      highlightedPages.clear();
      matches = [];
      currentIndex = -1;
    };

  } catch (err) {
    const msg = err.message || String(err);
    showError(msg);
    if (window.VaultPdfViewer) VaultPdfViewer.onError(msg);
  }
})();

/* ── Helpers ──────────────────────────────────────────────────────── */

function showError(message) {
  const lo = document.getElementById('loading-overlay');
  if (lo) lo.classList.add('hidden');
  let el = document.getElementById('error');
  if (!el) { el = document.createElement('div'); el.id = 'error'; document.body.appendChild(el); }
  el.innerHTML =
    '<div class="icon">\u26A0\uFE0F</div>' +
    '<div style="font-size:16px;font-weight:bold;margin-bottom:8px">Cannot open PDF</div>' +
    '<div class="message">' + escapeHtml(message) + '</div>';
  el.classList.add('visible');
}

function escapeHtml(s) {
  const d = document.createElement('div');
  d.textContent = s;
  return d.innerHTML;
}
