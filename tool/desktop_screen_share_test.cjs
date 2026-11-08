// Tests the getDisplayMedia shim that webview_cef injects into every page on
// desktop (kScreenShareShim in third_party/webview_cef/common/webview_app.cc).
// Run with: node --test tool/desktop_screen_share_test.cjs
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');

const cc = fs.readFileSync('third_party/webview_cef/common/webview_app.cc', 'utf8');
const start = cc.indexOf('const char kScreenShareShim[] = R"JS(');
const source = cc.slice(cc.indexOf('R"JS(', start) + 5, cc.indexOf(')JS"', start));

// A page with fake media APIs and the |native| object the browser hands in.
function page({policy = true, secure = true, late = false, choice = {id: 'window:42:0', audio: false, surface: 'window'}} = {}) {
  const calls = {picks: [], gum: [], audio: []};
  let chunkSink = null;

  class FakeTrack extends EventTarget {
    constructor(kind) { super(); this.kind = kind; this.readyState = 'live'; }
    stop() { this.readyState = 'ended'; }
    getSettings() { return {width: 1280}; }
  }
  class FakeStream {
    constructor(tracks = []) { this.tracks = tracks; }
    getVideoTracks() { return this.tracks.filter(t => t.kind === 'video'); }
    getAudioTracks() { return this.tracks.filter(t => t.kind === 'audio'); }
    addTrack(t) { this.tracks.push(t); }
  }
  const played = [];
  class FakeAudioContext {
    constructor(options) { this.options = options; this.currentTime = 0; this.closed = false; }
    createMediaStreamDestination() {
      return {channelCount: 1, stream: new FakeStream([new FakeTrack('audio')])};
    }
    createBuffer(channels, frames, rate) {
      const data = [new Float32Array(frames), new Float32Array(frames)];
      return {duration: frames / rate, getChannelData: (c) => data[c]};
    }
    createBufferSource() {
      return {connect() {}, start(at) { played.push({at, buffer: this.buffer}); }};
    }
    close() { this.closed = true; return Promise.resolve(); }
  }
  class MediaDevices {
    getUserMedia(constraints) {
      calls.gum.push(constraints);
      return Promise.resolve(new FakeStream([new FakeTrack('video')]));
    }
  }
  class CaptureController {
    setFocusBehavior() { throw new DOMException('not bound', 'InvalidStateError'); }
  }
  const native = {
    pick(audio, callback) { calls.picks.push(audio); queueMicrotask(() => callback(choice)); },
    audio(start, sink) { calls.audio.push(start); chunkSink = start ? sink : null; },
  };
  // As in Blink, secure-context APIs appear after the context is created:
  // navigator.mediaDevices first, the interface objects a task later.
  const devices = new MediaDevices();
  const window = {isSecureContext: secure, AudioContext: FakeAudioContext};
  const navigator = {};
  const exposeDevices = () => { if (secure) navigator.mediaDevices = devices; };
  const exposeInterfaces = () => {
    if (!secure) return;
    window.MediaDevices = MediaDevices;
    window.CaptureController = CaptureController;
  };
  if (!late) {
    exposeDevices();
    exposeInterfaces();
  }
  const context = {
    window, navigator, MediaStream: FakeStream, MediaStreamTrack: FakeTrack, EventTarget,
    Reflect, Object, Promise, DOMException, TypeError, Int16Array, WeakSet,
    queueMicrotask, setTimeout,
    document: {permissionsPolicy: {allowsFeature: (f) => f !== 'display-capture' || policy}},
  };
  const factory = vm.runInNewContext(source, context);
  factory(native);
  if (late) {
    queueMicrotask(exposeDevices);
    setTimeout(exposeInterfaces, 0);
  }
  return {
    capture: (options) => devices.getDisplayMedia(options),
    calls, played, CaptureController,
    sendChunk: (samples) => chunkSink(new Int16Array(samples).buffer),
  };
}

const nextTask = () => new Promise(r => setTimeout(r, 5));

test('asks the browser, then captures exactly the chosen window', async () => {
  const p = page();
  const stream = await p.capture({video: {frameRate: {max: 15}, width: {max: 1920}}, audio: false});
  assert.deepEqual(p.calls.picks, [false]);
  assert.deepEqual(JSON.parse(JSON.stringify(p.calls.gum)), [{
    audio: false,
    video: {mandatory: {
      chromeMediaSource: 'desktop', chromeMediaSourceId: 'window:42:0',
      maxWidth: 1920, maxFrameRate: 15,
    }},
  }]);
  const [track] = stream.getVideoTracks();
  assert.equal(track.getSettings().displaySurface, 'window');
  assert.equal(stream.getAudioTracks().length, 0);
  assert.deepEqual(p.calls.audio, []);
});

test('cancelling the picker rejects with NotAllowedError and captures nothing', async () => {
  const p = page({choice: {id: '', audio: false, surface: ''}});
  await assert.rejects(p.capture({video: true}), {name: 'NotAllowedError'});
  assert.equal(p.calls.gum.length, 0);
});

test('system audio becomes an audio track fed by the browser', async () => {
  const p = page({choice: {id: 'screen:0:0', audio: true, surface: 'monitor'}});
  const stream = await p.capture({video: true, audio: true});
  assert.deepEqual(p.calls.picks, [true]);
  assert.deepEqual(p.calls.audio, [true]);
  const [audio] = stream.getAudioTracks();
  assert.ok(audio);
  // 2 frames of stereo 16-bit PCM.
  p.sendChunk([16384, -16384, 32767, 0]);
  assert.equal(p.played.length, 1);
  assert.equal(p.played[0].buffer.getChannelData(0)[0], 0.5);
  assert.equal(p.played[0].buffer.getChannelData(1)[0], -0.5);
  assert.ok(p.played[0].at > 0, 'played a little ahead of time');
  // Stopping the audio track stops the capture in the browser.
  audio.stop();
  assert.deepEqual(p.calls.audio, [true, false]);
  assert.equal(audio.readyState, 'ended');
});

test('the shared window closing stops the system audio', async () => {
  const p = page({choice: {id: 'window:7:0', audio: true, surface: 'window'}});
  const stream = await p.capture({video: true, audio: true});
  stream.getVideoTracks()[0].dispatchEvent(new Event('ended'));
  assert.deepEqual(p.calls.audio, [true, false]);
  assert.equal(stream.getAudioTracks()[0].readyState, 'ended');
});

test('one picker at a time', async () => {
  const p = page();
  const first = p.capture();
  await assert.rejects(p.capture(), {name: 'InvalidStateError'});
  await first;
  await p.capture();
  assert.equal(p.calls.picks.length, 2);
});

test('follows the spec and permissions policy before asking', async () => {
  await assert.rejects(page().capture({video: false}), TypeError);
  await assert.rejects(page().capture(null), TypeError);
  const blocked = page({policy: false});
  await assert.rejects(blocked.capture(), {name: 'NotAllowedError'});
  assert.equal(blocked.calls.picks.length, 0);
});

test('not installed outside secure pages', () => {
  const p = page({secure: false});
  assert.throws(() => p.capture(), TypeError);
});

test('installed once Blink adds the APIs, after the context is created', async () => {
  const p = page({late: true});
  assert.equal(typeof p.capture, 'function');
  assert.throws(() => p.capture(), TypeError, 'not there yet');
  await nextTask();
  const controller = new p.CaptureController();
  await p.capture({video: true, controller});
  assert.deepEqual(p.calls.picks, [false]);
  assert.doesNotThrow(() => controller.setFocusBehavior('no-focus-change'));
});

test('a CaptureController given to getDisplayMedia may set focus behavior', async () => {
  const p = page();
  const controller = new p.CaptureController();
  await p.capture({video: true, controller});
  assert.doesNotThrow(() => controller.setFocusBehavior('no-focus-change'));
  assert.throws(() => new p.CaptureController().setFocusBehavior('focus-capturing-application'));
});
