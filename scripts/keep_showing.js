(function() {
  // Clicks the "Keep Working" button when notification appears and repeats every 10 minutes.
  const INTERVAL_MS = 10 * 60 * 1000; // 10 minutes

  function findKeepButton() {
    // Prefer searching for exact visible text, but allow trimmed match
    const anchors = Array.from(document.querySelectorAll('a, button'));
    for (const el of anchors) {
      if (!el.textContent) continue;
      const txt = el.textContent.trim();
      if (/^keep\s+working$/i.test(txt)) return el;
      // some locales or slight differences may exist
      if (/keep\s+working/i.test(txt)) return el;
    }
    return null;
  }

  function clickKeep() {
    try {
      const btn = findKeepButton();
      if (btn) {
        btn.click();
        console.info('[keep_showing] Clicked Keep Working at', new Date().toISOString());
        return true;
      }
    } catch (err) {
      console.error('[keep_showing] Error clicking:', err);
    }
    return false;
  }

  // Click immediately if present
  clickKeep();

  // Periodic click every INTERVAL_MS
  const intervalId = setInterval(() => clickKeep(), INTERVAL_MS);

  // Observe DOM mutations to click as soon as notification appears
  const observer = new MutationObserver(mutations => {
    for (const m of mutations) {
      if (m.addedNodes && m.addedNodes.length) {
        if (clickKeep()) break;
      }
    }
  });

  observer.observe(document.body, { childList: true, subtree: true });

  // Expose controls for manual stop/start
  window.keepShowing = {
    stop() {
      clearInterval(intervalId);
      observer.disconnect();
      console.info('[keep_showing] stopped');
    },
    clickNow() {
      return clickKeep();
    }
  };

  console.info('[keep_showing] running — clicks every', INTERVAL_MS / 60000, 'minutes. Use keepShowing.stop() to stop.');
})();