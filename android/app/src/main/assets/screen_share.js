(() => {
  if (!isSecureContext || location.protocol !== 'https:' || window !== top || !navigator.mediaDevices ||
      navigator.mediaDevices.getDisplayMedia || !window.SixScreenCapture) return;
  const bridge = window.SixScreenCapture;
  let next = 0;
  const pending = new Map();
  bridge.onmessage = ({data}) => {
    const reply = JSON.parse(data);
    const entry = pending.get(reply.id);
    if (!entry) return;
    pending.delete(reply.id);
    clearTimeout(entry.timer);
    reply.error ? entry.reject(new DOMException(reply.error, reply.name || 'NotAllowedError'))
                : entry.resolve(reply);
  };
  const call = (op) => new Promise((resolve, reject) => {
    const id = ++next;
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new DOMException('Screen capture timed out', 'AbortError'));
      bridge.postMessage(JSON.stringify({id: ++next, op: 'stop'}));
    }, op === 'start' ? 120000 : 10000);
    pending.set(id, {resolve, reject, timer});
    bridge.postMessage(JSON.stringify({id, op}));
  });
  navigator.mediaDevices.getDisplayMedia = async (options = {}) => {
    if (document.permissionsPolicy?.allowsFeature('display-capture') === false) {
      throw new DOMException('Screen capture is blocked by this page policy', 'NotAllowedError');
    }
    if (!navigator.userActivation.isActive) {
      throw new DOMException('Click Share screen to start capture', 'InvalidStateError');
    }
    if (options.video === false) throw new TypeError('Screen sharing requires video');
    if (typeof HTMLCanvasElement.prototype.captureStream !== 'function') {
      throw new DOMException('Canvas capture is unavailable', 'NotSupportedError');
    }
    await call('start'); // Android displays its system capture consent dialog.
    const canvas = document.createElement('canvas');
    const context = canvas.getContext('2d');
    let stream, running = true, hasFrame = false;
    const stop = () => {
      if (!running) return;
      running = false;
      call('stop').catch(() => {});
    };
    const draw = async () => {
      const frame = await call('frame');
      if (frame.ended) throw new DOMException('Screen sharing ended', 'AbortError');
      if (!frame.jpeg || !running) return;
      const img = new Image();
      img.src = 'data:image/jpeg;base64,' + frame.jpeg;
      await img.decode();
      if (!running) return;
      if (canvas.width !== img.width || canvas.height !== img.height) {
        canvas.width = img.width;
        canvas.height = img.height;
      }
      context.drawImage(img, 0, 0);
      hasFrame = true;
    };
    try {
      // Wait for the first frame before handing a video track to the caller.
      const deadline = Date.now() + 10000;
      do {
        await draw();
        if (hasFrame) break;
        await new Promise(r => setTimeout(r, 100));
      } while (Date.now() < deadline);
      if (!hasFrame) throw new DOMException('No screen frames received', 'NotReadableError');
      stream = canvas.captureStream(10);
      const track = stream.getVideoTracks()[0];
      const nativeStop = track.stop.bind(track);
      track.stop = () => { nativeStop(); stop(); };
      track.addEventListener('ended', stop, {once: true});
      addEventListener('pagehide', stop, {once: true});
      (async () => {
        try {
          while (running && track.readyState === 'live') {
            await new Promise(r => setTimeout(r, 100));
            await draw();
          }
        } catch (_) {
          nativeStop();
          track.dispatchEvent(new Event('ended'));
        } finally { stop(); }
      })();
      return stream;
    } catch (error) { stop(); throw error; }
  };
})();
