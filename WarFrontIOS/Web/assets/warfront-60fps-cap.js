(function () {
  'use strict';
  // Limit requestAnimationFrame-driven updates to at most ~60 per second.
  const nativeRAF = window.requestAnimationFrame.bind(window);
  const nativeCancel = window.cancelAnimationFrame.bind(window);
  const interval = 1000 / 60;
  let last = -Infinity, pending = new Map(), nextId = 1, scheduled = 0;
  function tick(now) {
    scheduled = 0;
    if (now - last >= interval - 0.5) {
      last = now;
      const batch = pending;
      pending = new Map();
      for (const [id, callback] of batch) {
        if (!cancelled.has(id)) {
          try { callback(now); } catch (err) { setTimeout(() => { throw err; }, 0); }
        }
        cancelled.delete(id);
      }
    }
    if (pending.size && !scheduled) scheduled = nativeRAF(tick);
  }
  const cancelled = new Set();
  window.requestAnimationFrame = function(callback) {
    if (typeof callback !== 'function') throw new TypeError('requestAnimationFrame callback must be a function');
    const id = nextId++;
    pending.set(id, callback);
    if (!scheduled) scheduled = nativeRAF(tick);
    return id;
  };
  window.cancelAnimationFrame = function(id) {
    if (pending.delete(id)) return;
    cancelled.add(id);
  };
})();
