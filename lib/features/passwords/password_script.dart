import 'dart:convert';

/// Page helper injected into the main frame of http(s) pages. It reports
/// password fields ('form') so saved sign-ins can be filled, and a typed
/// sign-in ('submit') once it looks successful: the page goes away, or the
/// password field disappears. It runs only if the page is still [origin];
/// every message carries [token], which other frames cannot know. [post] is
/// the backend's function that sends an object to the app.
String passwordScript({
  required String token,
  required String origin,
  required String post,
}) =>
    '''
(function (token, origin, post) {
  if (location.origin !== origin) return;
  var KEY = Symbol.for('sixbrowser.passwords');
  if (document[KEY]) { document[KEY].scan(); return; }
  var USER = /^(text|email|tel)\$/;
  var seen = new WeakSet();
  var pending = null, sent = '', typedUser = '', timer = 0;

  function send(m) { m.t = token; try { post(m); } catch (e) {} }
  function shown(el) {
    return !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length);
  }
  function passwords(root) {
    return [].filter.call(root.querySelectorAll('input[type=password]'), shown);
  }
  function rootOf(el) {
    return (el && el.closest && el.closest('form')) || document;
  }
  // The user name field: the last visible text field before the password.
  function userFor(pw) {
    var root = rootOf(pw), found = null;
    [].forEach.call(root.querySelectorAll('input'), function (el) {
      if (USER.test(el.type) && shown(el) && !el.disabled &&
          (el.compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING)) {
        found = el;
      }
    });
    return found || root.querySelector(
        'input[autocomplete~=username],input[autocomplete~=email]');
  }
  function capture(from) {
    var filled = passwords(rootOf(from)).filter(function (el) { return el.value; });
    if (!filled.length) {
      filled = passwords(document).filter(function (el) { return el.value; });
    }
    if (!filled.length) return;
    // Sign-up and change-password forms repeat the new password.
    var field = filled[0];
    for (var i = 0; i < filled.length; i++) {
      for (var j = i + 1; j < filled.length; j++) {
        if (filled[i].value === filled[j].value) field = filled[i];
      }
    }
    var user = userFor(field);
    pending = {
      field: field,
      username: ((user && user.value) || typedUser).trim(),
      password: field.value
    };
  }
  function flush() {
    if (!pending) return;
    var p = pending, key = p.username + '\\n' + p.password;
    pending = null;
    if (key === sent) return;
    sent = key;
    send({type: 'submit', username: p.username, password: p.password});
  }
  function scan() {
    if (pending && (!document.contains(pending.field) || !shown(pending.field))) {
      flush();
    }
    var fresh = passwords(document).filter(function (el) { return !seen.has(el); });
    if (!fresh.length) return;
    fresh.forEach(function (el) { seen.add(el); });
    send({type: 'form'});
  }
  function set(el, value) {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')
        .set.call(el, value);
    el.dispatchEvent(new Event('input', {bubbles: true}));
    el.dispatchEvent(new Event('change', {bubbles: true}));
  }
  // Fills sign-in forms (one password field). What the user typed stays
  // unless they picked this sign-in themselves.
  function fill(username, password, force) {
    passwords(document).forEach(function (pw) {
      if (passwords(rootOf(pw)).length !== 1 || (pw.value && !force)) return;
      var user = userFor(pw);
      if (user && username && (force || !user.value)) set(user, username);
      set(pw, password);
    });
  }

  document[KEY] = {scan: scan, fill: fill};
  document.addEventListener('submit', function (e) { capture(e.target); }, true);
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' && e.target && e.target.tagName === 'INPUT') {
      capture(e.target);
    }
  }, true);
  // Sign-in buttons that are not part of a form. Icon-only buttons (such as
  // "show password") are not sign-ins.
  document.addEventListener('click', function (e) {
    var b = e.target && e.target.closest &&
        e.target.closest('button,input[type=submit],input[type=image],[role=button]');
    if (b && (b.textContent.trim() || b.value)) capture(b);
  }, true);
  // Sites that ask for the password on a second step.
  document.addEventListener('change', function (e) {
    var el = e.target;
    if (el && el.tagName === 'INPUT' && USER.test(el.type) &&
        el.value.length < 100 &&
        /user|mail|login|account|ident/i.test(
            (el.name || '') + (el.id || '') + (el.autocomplete || ''))) {
      typedUser = el.value;
    }
  }, true);
  window.addEventListener('pagehide', flush, true);
  // At most every 300 ms, so busy pages still get scanned.
  new MutationObserver(function () {
    if (!timer) timer = setTimeout(function () { timer = 0; scan(); }, 300);
  }).observe(document.documentElement || document, {
    childList: true, subtree: true, attributes: true,
    attributeFilter: ['style', 'class', 'hidden']
  });
  scan();
})(${jsonEncode(token)}, ${jsonEncode(origin)}, $post);
''';

/// Fills a saved sign-in into the page, if it is still [origin]. The check
/// is here, outside anything the page could replace.
String passwordFillScript({
  required String origin,
  required String username,
  required String password,
  bool force = false,
}) =>
    '''
(function () {
  if (location.origin !== ${jsonEncode(origin)}) return;
  var api = document[Symbol.for('sixbrowser.passwords')];
  if (api) api.fill(${jsonEncode(username)}, ${jsonEncode(password)}, $force);
})();
''';
