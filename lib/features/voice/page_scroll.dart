import 'dart:convert';

import 'voice_commands.dart';

/// Page script that scrolls the page as [move] says ("scroll down": about a
/// screen) and sends back `{t: token, moved: true|false}` through [post]
/// (the backend's function); moved is false when the page cannot go that
/// way any more.
///
/// It scrolls the document when the document can move that way. Web mail,
/// chats and online documents keep the document still and scroll a box
/// inside it: then the box under the middle of the window (or one around
/// it), or else the largest one on screen, scrolls. When the box that would
/// scroll is already at its end, nothing else does: a sidebar does not
/// start moving at the end of the mail list.
String scrollPageScript(
  ScrollMove move, {
  required String token,
  required String post,
}) =>
    '''
(function (move, token, post) {
  var d = document, w = window;
  var root = d.scrollingElement || d.documentElement;
  var down = move === 'down' || move === 'bottom';
  // How far el can still scroll that way.
  function room(el) {
    var max = el.scrollHeight - el.clientHeight;
    return down ? max - el.scrollTop : el.scrollTop;
  }
  function scrollable(el) {
    if (el.clientHeight < 40 || el.scrollHeight - el.clientHeight < 2) {
      return false;
    }
    if (el === root) return true;
    var o = getComputedStyle(el).overflowY;
    return o === 'auto' || o === 'scroll' || o === 'overlay';
  }
  // box: what scrolls; stuck: what would, but is at its end already.
  var box = null, stuck = null;
  function consider(el) {
    if (!scrollable(el)) return false;
    if (room(el) >= 2) { box = el; return true; }
    stuck = stuck || el;
    return false;
  }
  if (!(root && consider(root))) {
    var el = d.elementFromPoint(w.innerWidth / 2, w.innerHeight / 2);
    for (; el && el !== root; el = el.parentElement) {
      if (consider(el)) break;
    }
  }
  if (!box && !stuck && d.body) {
    var best = 0, biggest = null;
    [].forEach.call(d.body.querySelectorAll('*'), function (el) {
      var r = el.getBoundingClientRect();
      var area = Math.max(0, Math.min(r.right, w.innerWidth) - Math.max(r.left, 0)) *
          Math.max(0, Math.min(r.bottom, w.innerHeight) - Math.max(r.top, 0));
      if (area > best && scrollable(el)) { best = area; biggest = el; }
    });
    if (biggest) consider(biggest);
  }
  if (box) {
    var screen = box === root ? w.innerHeight : box.clientHeight;
    var by = move === 'top' || move === 'bottom'
        ? room(box) : Math.min(room(box), Math.round(screen * 0.8));
    var still = w.matchMedia &&
        w.matchMedia('(prefers-reduced-motion: reduce)').matches;
    (box === root ? w : box).scrollBy(
        {top: down ? by : -by, behavior: still ? 'auto' : 'smooth'});
  }
  try { post({t: token, moved: !!box}); } catch (e) {}
})(${jsonEncode(move.name)}, ${jsonEncode(token)}, $post);
''';
