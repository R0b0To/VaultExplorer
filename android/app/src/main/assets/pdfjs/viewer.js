'use strict';

(async function () {
  const params = new URLSearchParams(location.search);
  const pdfUrl = params.get('url');

  if (!pdfUrl) { showError('No PDF URL provided.'); return; }

  let pdfjsLib;
  try {
    pdfjsLib = await import('./pdf.min.mjs');
  } catch (e) {
    showError('Failed to load PDF library: ' + (e.message || e));
    return;
  }

  pdfjsLib.GlobalWorkerOptions.workerSrc =
    new URL('./pdf.worker.min.mjs', import.meta.url).href;

  const viewer = document.getElementById('viewer');
  const loadingOverlay = document.getElementById('loading-overlay');

  const MAX_ZOOM_MULTIPLIER = 4;
  const GAP = 8; // must match #viewer's CSS `gap` and top `padding` in viewer.css
  let currentZoom = 1;
  let zoomDebounceId = 0;
  let resizeDebounceId = 0;
  let DPR = window.devicePixelRatio || 1;

  const cMapUrl = new URL('./cmaps/', import.meta.url).href;
  const standardFontDataUrl = new URL('./standard_fonts/', import.meta.url).href;

  /* ── Selection Handling (Fixes Handle Jump & View Shifts) ──────── */
  function updateSelectionState() {
    const sel = window.getSelection();
    const isSelecting = sel && !sel.isCollapsed && sel.toString().trim().length > 0;
    document.querySelectorAll('.textLayer').forEach(el => {
      const endEl = el.querySelector('.endOfContent');
      if (isSelecting) {
        el.classList.add('selecting');
        if (endEl) endEl.classList.add('active');
      } else {
        el.classList.remove('selecting');
        if (endEl) endEl.classList.remove('active');
      }
    });
  }

  document.addEventListener('selectionchange', updateSelectionState);
  document.addEventListener('pointerup', () => setTimeout(updateSelectionState, 100));

  /* ── Search State ────────────────────────────────────────────────── */
  const searchIndex = new Map();
  const highlightedPages = new Set();
  let activeQuery = '';
  let matches = []; // [{ id, page, start, end, elements }]
  let currentIndex = -1;
  let searchGeneration = 0; // bumped on every new search/clear so stale scans self-cancel

  const supportsCssHighlights = typeof CSS !== 'undefined' && !!CSS.highlights;
  let allHighlightRanges = [];
  let currentHighlightRanges = [];

  try {
    const pdf = await pdfjsLib.getDocument({
      url                : pdfUrl,
      useWorkerFetch     : false,
      cMapUrl            : cMapUrl,
      cMapPacked         : true,
      standardFontDataUrl: standardFontDataUrl,
      useSystemFonts     : false, // Forces PDF.js to use exact PDF font metrics
      enableXfa          : false,
    }).promise;

    const pageCount = pdf.numPages;

    if (window.VaultPdfViewer) {
      VaultPdfViewer.onDocumentLoaded(pageCount);
    }

    const firstPage    = await pdf.getPage(1);
    const firstPageVp  = firstPage.getViewport({ scale: 1 });
    const firstAspect  = firstPageVp.height / firstPageVp.width;
    let fitWidth        = Math.max(viewer.clientWidth - 16, 200);

    // pageHeights/pageOffsets let the scroll handler find the current page with a
    // binary search instead of measuring every page's layout box on every frame.
    const pages = [];
    const pageHeights = [];
    const pageOffsets = [];

    for (let i = 1; i <= pageCount; i++) {
      const el = document.createElement('div');
      el.className       = 'page-container';
      el.dataset.pageNum = String(i);

      const h = firstAspect * fitWidth;
      el.style.width  = fitWidth + 'px';
      el.style.height = h + 'px';

      viewer.appendChild(el);
      pageHeights.push(h);

      pages.push({
        num: i,
        el,
        rendered: false,
        rendering: false,
        renderPromise: null,
        renderTask: null,  // active pdf.js RenderTask, kept so it can be cancelled
        renderGen: 0,      // token: a render result only gets applied if this still matches
        textDiv: null,
        aspect: firstAspect, // refined to the page's real aspect ratio once it renders
      });
    }

    function rebuildOffsetsFrom(startIdx) {
      let top = startIdx === 0 ? GAP : pageOffsets[startIdx];
      for (let i = startIdx; i < pages.length; i++) {
        pageOffsets[i] = top;
        top += pageHeights[i] + GAP;
      }
    }
    rebuildOffsetsFrom(0);

    loadingOverlay.classList.add('hidden');

    /* ── Rendering (generation-token guarded so stale async work is a no-op) ── */

    function cancelActiveRender(p) {
      if (p.renderTask) {
        try { p.renderTask.cancel(); } catch (_) { /* already finished/cancelled */ }
        p.renderTask = null;
      }
    }

    function updatePageSize(p, width, height) {
      const idx = p.num - 1;
      p.el.style.width  = width + 'px';
      p.el.style.height = height + 'px';
      if (Math.abs(pageHeights[idx] - height) > 0.5) {
        pageHeights[idx] = height;
        rebuildOffsetsFrom(idx);
      }
    }

    function startRender(p) {
      const myGen = ++p.renderGen;
      if (p.rendering) cancelActiveRender(p); // supersede whatever was in flight for this page
      p.rendering = true;

      p.renderPromise = (async () => {
        try {
          const page = await pdf.getPage(p.num);
          if (myGen !== p.renderGen) return; // reclaimed/superseded while awaiting the page

          const unscaledVp = page.getViewport({ scale: 1 });
          p.aspect = unscaledVp.height / unscaledVp.width;

          const pageScale = fitWidth / unscaledVp.width;
          const cssVp     = page.getViewport({ scale: pageScale });
          const zoomMult  = Math.min(currentZoom, MAX_ZOOM_MULTIPLIER);
          const canvasVp  = page.getViewport({ scale: pageScale * DPR * zoomMult });

          if (myGen !== p.renderGen) return; // cheap re-check before paying for a full rasterize

          const canvas  = document.createElement('canvas');
          canvas.width  = Math.floor(canvasVp.width);
          canvas.height = Math.floor(canvasVp.height);
          canvas.style.width  = cssVp.width + 'px';
          canvas.style.height = cssVp.height + 'px';

          const ctx = canvas.getContext('2d', { alpha: false });
          ctx.scale(DPR * zoomMult, DPR * zoomMult);

          const task = page.render({ canvasContext: ctx, viewport: cssVp });
          p.renderTask = task;
          await task.promise;
          p.renderTask = null;

          if (myGen !== p.renderGen) return; // superseded while painting - discard this result

          updatePageSize(p, cssVp.width, cssVp.height);
          p.el.innerHTML = '';
          p.el.appendChild(canvas);

          // Text layer (best-effort; page is still usable if this fails)
          try {
            if (pdfjsLib.TextLayer) {
              const textContent = await page.getTextContent();
              if (myGen !== p.renderGen) return;

              const textDiv     = document.createElement('div');
              textDiv.className    = 'textLayer';
              textDiv.style.width  = cssVp.width + 'px';
              textDiv.style.height = cssVp.height + 'px';

              const scaleStr = String(cssVp.scale);
              textDiv.style.setProperty('--scale-factor', scaleStr);
              textDiv.style.setProperty('--total-scale-factor', scaleStr);

              p.el.appendChild(textDiv);

              if (document.fonts && document.fonts.ready) {
                try { await document.fonts.ready; } catch (_) {}
              }
              if (myGen !== p.renderGen) return;

              const tl = new pdfjsLib.TextLayer({
                textContentSource : textContent,
                container         : textDiv,
                viewport          : cssVp,
              });
              await tl.render();
              if (myGen !== p.renderGen) return;

              // Sort spans in visual spatial order (top-to-bottom, left-to-right) so DOM order matches reading order.
              // Fixes WebKit text selection handle jumping across lines/selecting whole document.
              const spans = Array.from(textDiv.querySelectorAll('span:not(.endOfContent)'));
              spans.sort((a, b) => {
                const topA = parseFloat(a.style.top) || 0;
                const topB = parseFloat(b.style.top) || 0;
                if (Math.abs(topA - topB) > 0.8) return topA - topB;
                const leftA = parseFloat(a.style.left) || 0;
                const leftB = parseFloat(b.style.left) || 0;
                return leftA - leftB;
              });
              for (const span of spans) {
                textDiv.appendChild(span);
              }

              // Add endOfContent element for WebKit selection boundary anchoring
              const endEl = document.createElement('div');
              endEl.className = 'endOfContent';
              textDiv.appendChild(endEl);

              p.textDiv = textDiv;

              // Force WebKit font metric reflow so text layer aligns instantly
              requestAnimationFrame(() => {
                if (myGen === p.renderGen && textDiv) textDiv.offsetHeight;
              });
            }
          } catch (err) {
            console.error('TextLayer error page ' + p.num, err);
          }

          p.rendered = true;

          // Apply highlights if search is currently active
          if (activeQuery) {
            applyHighlightsForPage(p.num);
            highlightedPages.add(p.num);
          }
        } catch (e) {
          // Expected/benign: happens whenever a render is cancelled mid-flight
          // (fast scroll past a page, zoom change, rotation) - not a real error.
          if (e && e.name === 'RenderingCancelledException') return;
          console.error('Render error page ' + p.num, e);
        } finally {
          if (myGen === p.renderGen) p.rendering = false;
        }
      })();

      return p.renderPromise;
    }

    function renderPage(p) {
      if (p.rendered) return Promise.resolve();
      if (p.rendering && p.renderPromise) return p.renderPromise;
      return startRender(p);
    }

    // Re-paints a page that has already rendered once, at a new zoom/resolution or
    // page width. No-op for pages that were never rendered (or reclaimed) - those
    // will simply render fresh, at the current settings, next time they scroll in.
    function refreshRenderedPage(p) {
      if (!p.rendered && !p.rendering) return;
      startRender(p);
    }

    function reclaimPage(p) {
      if (!p.rendered && !p.rendering) return;
      p.renderGen += 1; // invalidates any render still in flight for this page
      cancelActiveRender(p);
      p.rendered  = false;
      p.rendering = false;
      p.renderPromise = null;
      p.textDiv   = null;
      p.el.innerHTML = '';
      highlightedPages.delete(p.num);
    }

    function scheduleZoomRerender() {
      clearTimeout(zoomDebounceId);
      zoomDebounceId = setTimeout(() => {
        const vv   = window.visualViewport;
        const zoom = vv ? vv.scale : 1;
        if (Math.abs(zoom - currentZoom) < 0.05) return;
        currentZoom = zoom;
        for (const p of pages) refreshRenderedPage(p);
      }, 250);
    }

    if (window.visualViewport) {
      window.visualViewport.addEventListener('resize', scheduleZoomRerender, { passive: true });
    }

    // Handles rotation and any other container-size change (distinct from pinch-zoom,
    // which changes visual scale but not layout size). Re-flows every page container
    // to the new width and re-renders whatever was already on screen.
    function relayout() {
      if (!pages.length) return;
      const newFitWidth = Math.max(viewer.clientWidth - 16, 200);
      DPR = window.devicePixelRatio || DPR;
      if (Math.abs(newFitWidth - fitWidth) < 1) return;
      fitWidth = newFitWidth;

      for (let i = 0; i < pages.length; i++) {
        const p = pages[i];
        const h = p.aspect * fitWidth;
        p.el.style.width  = fitWidth + 'px';
        p.el.style.height = h + 'px';
        pageHeights[i] = h;
      }
      rebuildOffsetsFrom(0);

      for (const p of pages) refreshRenderedPage(p);
    }

    function scheduleRelayout() {
      clearTimeout(resizeDebounceId);
      resizeDebounceId = setTimeout(relayout, 150);
    }

    if (typeof ResizeObserver !== 'undefined') {
      new ResizeObserver(scheduleRelayout).observe(viewer);
    }

    const renderObserver = new IntersectionObserver(entries => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        const n = parseInt(e.target.dataset.pageNum, 10);
        if (n >= 1 && n <= pages.length) renderPage(pages[n - 1]);
      }
    }, { rootMargin: '800px 0px' });

    const cleanupObserver = new IntersectionObserver(entries => {
      for (const e of entries) {
        if (e.isIntersecting) continue;
        const n = parseInt(e.target.dataset.pageNum, 10);
        if (n >= 1 && n <= pages.length) reclaimPage(pages[n - 1]);
      }
    }, { rootMargin: '3000px 0px' });

    for (const p of pages) {
      renderObserver.observe(p.el);
      cleanupObserver.observe(p.el);
    }

    /* ── Current-page tracking (binary search over cached offsets, no layout reads) ── */
    let lastReported = 0;
    let rafId        = 0;

    function findPageIndexAtOffset(target) {
      let lo = 0, hi = pageOffsets.length - 1, ans = 0;
      while (lo <= hi) {
        const mid = (lo + hi) >> 1;
        if (pageOffsets[mid] <= target) { ans = mid; lo = mid + 1; }
        else { hi = mid - 1; }
      }
      return ans;
    }

    viewer.addEventListener('scroll', () => {
      if (rafId) return;
      rafId = requestAnimationFrame(() => {
        rafId = 0;
        const mid = viewer.scrollTop + viewer.clientHeight / 2;
        const cur = Math.min(Math.max(findPageIndexAtOffset(mid) + 1, 1), pageCount);
        if (cur !== lastReported) {
          lastReported = cur;
          if (window.VaultPdfViewer) VaultPdfViewer.onPageChanged(cur);
        }
      });
    }, { passive: true });

    window.goToPage = function (n) {
      if (n >= 1 && n <= pages.length) {
        pages[n - 1].el.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }
    };

    /* ── Search Implementation (DOM TreeWalker + CSS Highlights) ──── */
    function getPageDomText(textDiv) {
      const walker = document.createTreeWalker(textDiv, NodeFilter.SHOW_TEXT, null);
      const textNodes = [];
      let fullText = '';
      let node;
      while ((node = walker.nextNode())) {
        const str = node.nodeValue || '';
        if (!str) continue;
        const start = fullText.length;
        fullText += str;
        textNodes.push({ node, start, end: fullText.length, len: str.length });
      }
      return { fullText, textNodes };
    }

    async function buildSearchIndex(pageNum) {
      if (searchIndex.has(pageNum)) return searchIndex.get(pageNum);
      const page    = await pdf.getPage(pageNum);
      const content = await page.getTextContent();
      let text = '';
      for (const item of content.items) {
        if (typeof item.str !== 'string') continue;
        text += item.str;
      }
      const entry = { text: text.toLowerCase() };
      searchIndex.set(pageNum, entry);
      return entry;
    }

    function updateCssHighlights() {
      if (supportsCssHighlights) {
        if (allHighlightRanges.length > 0) {
          CSS.highlights.set('pdf-search-highlight', new Highlight(...allHighlightRanges));
        } else {
          CSS.highlights.delete('pdf-search-highlight');
        }

        if (currentHighlightRanges.length > 0) {
          CSS.highlights.set('pdf-search-selected', new Highlight(...currentHighlightRanges));
        } else {
          CSS.highlights.delete('pdf-search-selected');
        }
      }
    }

    function clearHighlightsForPage(pageNum) {
      const p = pages[pageNum - 1];
      if (!p || !p.textDiv) return;
      if (!supportsCssHighlights) {
        const marks = p.textDiv.querySelectorAll('.pdf-search-highlight');
        for (const mark of marks) {
          const parent = mark.parentNode;
          if (!parent) continue;
          while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
          parent.removeChild(mark);
        }
        p.textDiv.normalize();
      }
    }

    function clearAllHighlights() {
      allHighlightRanges = [];
      currentHighlightRanges = [];
      updateCssHighlights();

      for (let n = 1; n <= pageCount; n++) {
        clearHighlightsForPage(n);
      }
    }

    function applyHighlightsForPage(pageNum) {
      const p = pages[pageNum - 1];
      if (!p || !p.rendered || !p.textDiv) return;

      clearHighlightsForPage(pageNum);

      const pageMatches = matches.filter(m => m.page === pageNum);
      if (!pageMatches.length) return;

      const { textNodes } = getPageDomText(p.textDiv);
      if (!textNodes.length) return;

      function findNodeOffset(charIndex) {
        for (const tn of textNodes) {
          if (charIndex >= tn.start && charIndex <= tn.end) {
            return { node: tn.node, offset: Math.min(charIndex - tn.start, tn.len) };
          }
        }
        const last = textNodes[textNodes.length - 1];
        return { node: last.node, offset: last.len };
      }

      for (const match of pageMatches) {
        const startPt = findNodeOffset(match.start);
        const endPt   = findNodeOffset(match.end);
        if (!startPt || !endPt) continue;

        try {
          const range = document.createRange();
          range.setStart(startPt.node, startPt.offset);
          range.setEnd(endPt.node, endPt.offset);

          if (supportsCssHighlights) {
            if (match.id === currentIndex) {
              currentHighlightRanges.push(range);
            } else {
              allHighlightRanges.push(range);
            }
          } else {
            // Fallback DOM highlight for older WebViews without CSS.highlights
            const mark = document.createElement('span');
            mark.className = 'pdf-search-highlight';
            if (match.id === currentIndex) {
              mark.classList.add('selected');
            }

            if (startPt.node === endPt.node) {
              range.surroundContents(mark);
            } else {
              const extracted = range.extractContents();
              mark.appendChild(extracted);
              range.insertNode(mark);
            }
            match.elements.push(mark);
          }
        } catch (e) {
          console.warn('Highlight range failed page ' + pageNum, e);
        }
      }

      updateCssHighlights();
    }

    async function goToMatch(i) {
      if (!matches.length) return;
      currentIndex = ((i % matches.length) + matches.length) % matches.length;
      const match = matches[currentIndex];

      const p = pages[match.page - 1];
      if (!p.rendered) {
        await renderPage(p);
      }

      if (!p.rendered || !p.textDiv) {
        // Page failed to render (corrupt page data, etc). Still move to it and
        // report the match position instead of throwing on a missing text layer.
        p.el.scrollIntoView({ behavior: 'smooth', block: 'start' });
        if (window.VaultPdfViewer) VaultPdfViewer.onSearchResult(currentIndex + 1, matches.length);
        return;
      }

      // Re-evaluate highlights for all rendered pages to update active/selected match
      allHighlightRanges = [];
      currentHighlightRanges = [];
      for (const renderedPageNum of highlightedPages) {
        applyHighlightsForPage(renderedPageNum);
      }
      applyHighlightsForPage(match.page);
      highlightedPages.add(match.page);

      let targetEl = null;
      if (supportsCssHighlights) {
        const { textNodes } = getPageDomText(p.textDiv);
        if (textNodes.length) {
          for (const tn of textNodes) {
            if (match.start >= tn.start && match.start <= tn.end) {
              targetEl = tn.node.parentElement;
              break;
            }
          }
        }
      } else {
        targetEl = p.textDiv.querySelector('.pdf-search-highlight.selected');
      }

      if (targetEl) {
        targetEl.scrollIntoView({ block: 'center', inline: 'nearest' });
      } else {
        p.el.scrollIntoView({ behavior: 'smooth', block: 'start' });
      }

      if (window.VaultPdfViewer) {
        VaultPdfViewer.onSearchResult(currentIndex + 1, matches.length);
      }
    }

    // Searches page-by-page and jumps to the first hit as soon as it's found instead
    // of waiting for the whole document to be scanned, then keeps indexing the rest
    // in the background so the match count keeps growing. A generation token means a
    // fast follow-up keystroke (or clearing the search) cancels the older scan instead
    // of racing it and possibly overwriting newer results with stale ones.
    window.searchText = async function (query) {
      const myGen = ++searchGeneration;
      activeQuery = query || '';
      clearAllHighlights();
      highlightedPages.clear();
      matches = [];
      currentIndex = -1;

      const q = activeQuery.trim();
      if (!q) {
        if (window.VaultPdfViewer) VaultPdfViewer.onSearchResult(0, 0);
        return;
      }

      let jumped = false;
      for (let n = 1; n <= pageCount; n++) {
        if (myGen !== searchGeneration) return;
        const idx = await buildSearchIndex(n);
        if (myGen !== searchGeneration) return;

        let from = 0;
        for (;;) {
          const at = idx.text.indexOf(q, from);
          if (at === -1) break;
          matches.push({ id: matches.length, page: n, start: at, end: at + q.length, elements: [] });
          from = at + q.length;
        }

        if (!jumped && matches.length) {
          jumped = true;
          await goToMatch(0);
        } else if (jumped && matches.length && window.VaultPdfViewer) {
          VaultPdfViewer.onSearchResult(currentIndex + 1, matches.length);
        }
      }

      if (myGen !== searchGeneration) return;
      if (!matches.length && window.VaultPdfViewer) {
        VaultPdfViewer.onSearchResult(0, 0);
      }
    };

    window.findNext     = function () { goToMatch(currentIndex + 1); };
    window.findPrevious = function () { goToMatch(currentIndex - 1); };

    window.clearSearch = function () {
      searchGeneration++; // cancels any scan still in flight
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
