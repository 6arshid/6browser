// Run with: node --test tool/screen_share_test.cjs
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync('android/app/src/main/assets/screen_share.js', 'utf8');

function page({active = true, denied = false, policy = true, secure = true, iframe = false, ends = false} = {}) {
  const operations = [];
  const track = new EventTarget();
  track.readyState = 'live';
  track.stop = () => { track.readyState = 'ended'; };
  const stream = {getVideoTracks: () => [track]};
  const canvas = {
    width: 300, height: 150,
    getContext: () => ({drawImage() {}}),
    captureStream: () => stream,
  };
  const bridge = {
    postMessage(data) {
      const {id, op} = JSON.parse(data);
      operations.push(op);
      const result = {id};
      if (op === 'start' && denied) result.error = 'Cancelled by user';
      if (op === 'frame') {
        result.jpeg = 'test-frame';
        result.ended = ends && operations.filter(op => op === 'frame').length > 1;
      }
      queueMicrotask(() => bridge.onmessage({data: JSON.stringify(result)}));
    },
  };
  const window = {SixScreenCapture: bridge};
  class Image {
    width = 720; height = 1280;
    async decode() {}
  }
  const context = {
    window, top: iframe ? {} : window, isSecureContext: secure, location: {protocol: 'https:'},
    navigator: {mediaDevices: {}, userActivation: {isActive: active}},
    document: {createElement: () => canvas, permissionsPolicy: {allowsFeature: () => policy}},
    HTMLCanvasElement: {prototype: {captureStream() {}}},
    Image, DOMException, Event, setTimeout, clearTimeout, addEventListener() {},
  };
  vm.runInNewContext(source, context);
  return {capture: context.navigator.mediaDevices.getDisplayMedia, operations, track, stream};
}

test('returns a video stream after consent and stops native capture with the track', async () => {
  const p = page();
  assert.equal(await p.capture({video: true, audio: true}), p.stream);
  assert.deepEqual(p.operations.slice(0, 2), ['start', 'frame']);
  p.track.stop();
  await new Promise(r => setTimeout(r, 120));
  assert.equal(p.track.readyState, 'ended');
  assert.equal(p.operations.filter(op => op === 'stop').length, 1);
});

test('cancelling consent rejects without reading any frames', async () => {
  const p = page({denied: true});
  await assert.rejects(p.capture(), {name: 'NotAllowedError'});
  assert.deepEqual(p.operations, ['start']);
});

test('ending capture in Android ends the web track and releases the bridge', async () => {
  const p = page({ends: true});
  await p.capture();
  const ended = new Promise(resolve => p.track.addEventListener('ended', resolve, {once: true}));
  await ended;
  assert.equal(p.track.readyState, 'ended');
  assert.equal(p.operations.filter(op => op === 'stop').length, 1);
});

test('requires a user gesture and respects display-capture policy', async () => {
  for (const options of [{active: false}, {policy: false}]) {
    const p = page(options);
    await assert.rejects(p.capture());
    assert.deepEqual(p.operations, []);
  }
});

test('requires video and does not expose capture in insecure pages or subframes', async () => {
  const p = page();
  await assert.rejects(p.capture({video: false}), {name: 'TypeError'});
  assert.deepEqual(p.operations, []);
  assert.equal(page({secure: false}).capture, undefined);
  assert.equal(page({iframe: true}).capture, undefined);
});
