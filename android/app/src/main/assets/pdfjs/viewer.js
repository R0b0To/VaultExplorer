/**
 * viewer.js — custom pdf.js viewer for VaultExplorer
 *
 * Renders decrypted PDF pages streamed from the vault into canvas elements.
 * Supports lazy rendering via IntersectionObserver, text-layer selection,
 * and memory cleanup of far-off-screen pages.
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
    const BASE_SCALE  = fitWidth / unscaledVp.width;
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
      pages.push({ num: i, el, rendered: false, rendering: false });
    }

    loadingOverlay.classList.add('hidden');

    /* ── Render a single page into its container ────────────────── */
    async function renderPage(p) {
      if (p.rendered || p.rendering) return;
      p.rendering = true;

      try {
        const page       = await pdf.getPage(p.num);
        const unscaledVp = page.getViewport({ scale: 1 });
        const pageScale  = fitWidth / unscaledVp.width;
        const cssVp      = page.getViewport({ scale: pageScale });
        const canvasVp   = page.getViewport({ scale: pageScale * DPR });

        // Canvas at device-pixel resolution
        const canvas     = document.createElement('canvas');
        canvas.width     = Math.floor(canvasVp.width);
        canvas.height    = Math.floor(canvasVp.height);
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

            const tl = new pdfjsLib.TextLayer({
              textContentSource : textContent,
              container         : textDiv,
              viewport          : cssVp,
            });
            await tl.render();
            p.el.appendChild(textDiv);
          }
        } catch (_) { /* text selection unavailable for this page */ }

        p.rendered = true;
      } catch (e) {
        console.error('Render error page ' + p.num, e);
      } finally {
        p.rendering = false;
      }
    }

    /* ── Reclaim a page's canvas to save memory ─────────────────── */
    function reclaimPage(p) {
      if (!p.rendered) return;
      p.rendered = false;
      p.el.innerHTML = '';           // drop canvas + textLayer
      // keep el.style.width/height so scroll position is stable
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
