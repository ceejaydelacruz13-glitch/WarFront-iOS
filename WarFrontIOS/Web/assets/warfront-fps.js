(function () {
  'use strict';
  var count = 0, start = performance.now(), display = null;
  function mount() {
    if (!document.body) return;
    if (!display || !display.isConnected) {
      display = document.createElement('div');
      display.id = 'warfront-fps-meter';
      display.textContent = 'FPS: --';
      display.style.cssText = 'all:initial!important;position:fixed!important;top:12px!important;left:12px!important;z-index:2147483647!important;color:#fff!important;background:rgba(0,0,0,.55)!important;padding:5px 9px!important;border-radius:4px!important;font:bold 20px monospace!important;text-shadow:1px 1px 2px #000!important;pointer-events:none!important;display:block!important;visibility:visible!important;opacity:1!important;';
      document.body.appendChild(display);
    }
  }
  function frame(now) {
    count++;
    if (now - start >= 750) {
      mount();
      if (display) display.textContent = 'FPS: ' + Math.round(count * 1000 / (now - start));
      count = 0;
      start = now;
    }
    requestAnimationFrame(frame);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount);
  else mount();
  requestAnimationFrame(frame);
})();
