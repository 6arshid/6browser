import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../engine/browser_engine.dart';
import '../tabs/tabs_controller.dart';

/// How a permission is named in the prompt ("wants to use your camera"), in
/// the settings ("Camera") and the icon shown with it.
extension SitePermissionText on SitePermission {
  String get request => switch (this) {
    SitePermission.camera => 'Use your camera',
    SitePermission.microphone => 'Use your microphone',
    SitePermission.cameraControl => 'Move your camera',
    SitePermission.location => 'Know your location',
    SitePermission.clipboard => 'See text and images copied to the clipboard',
    SitePermission.midi => 'Control and reprogram your MIDI devices',
    SitePermission.windowManagement => 'Manage windows on all your displays',
    SitePermission.localFonts => 'Use the fonts on your computer',
    SitePermission.idleDetection => 'Know when you are using this device',
    SitePermission.automaticDownloads => 'Download multiple files',
    SitePermission.sensors => 'Use your motion sensors',
    SitePermission.localNetwork =>
      'Look for and connect to devices on your local network',
  };

  String get label => switch (this) {
    SitePermission.camera => 'Camera',
    SitePermission.microphone => 'Microphone',
    SitePermission.cameraControl => 'Camera pan, tilt and zoom',
    SitePermission.location => 'Location',
    SitePermission.clipboard => 'Clipboard',
    SitePermission.midi => 'MIDI devices',
    SitePermission.windowManagement => 'Window management',
    SitePermission.localFonts => 'Fonts',
    SitePermission.idleDetection => 'Device use',
    SitePermission.automaticDownloads => 'Automatic downloads',
    SitePermission.sensors => 'Motion sensors',
    SitePermission.localNetwork => 'Local network',
  };

  IconData get icon => switch (this) {
    SitePermission.camera => Icons.videocam_outlined,
    SitePermission.microphone => Icons.mic_none,
    SitePermission.cameraControl => Icons.control_camera,
    SitePermission.location => Icons.location_on_outlined,
    SitePermission.clipboard => Icons.content_paste,
    SitePermission.midi => Icons.piano,
    SitePermission.windowManagement => Icons.filter_none,
    SitePermission.localFonts => Icons.font_download_outlined,
    SitePermission.idleDetection => Icons.person_outline,
    SitePermission.automaticDownloads => Icons.file_download_outlined,
    SitePermission.sensors => Icons.sensors,
    SitePermission.localNetwork => Icons.lan_outlined,
  };
}

/// One saved decision.
typedef SitePermissionEntry = ({
  String origin,
  SitePermission permission,
  bool allowed,
});

/// The user's Allow / Block per site and permission, so a site asks once.
/// Decisions in private tabs are kept in memory only, until 6browser
/// closes; there, saved blocks still apply (as in Chrome).
class SitePermissionStore {
  SitePermissionStore(this._db, this._engine);

  final AppDatabase _db;
  final BrowserEngine _engine;
  final _private = <(String, SitePermission), bool>{};

  /// The saved answer to a request for [permissions]: allow when every one
  /// is allowed, block when any is blocked, null when the user must be
  /// asked.
  Future<PermissionAnswer?> decisionFor(
    String origin,
    Set<SitePermission> permissions, {
    required bool incognito,
  }) async {
    final saved = {
      for (final row in await _db.sitePermissionsFor(origin))
        row.permission: row.allowed,
    };
    var allAllowed = true;
    for (final permission in permissions) {
      final allowed = incognito
          ? _private[(origin, permission)] ??
                (saved[permission.name] == false ? false : null)
          : saved[permission.name];
      if (allowed == false) return PermissionAnswer.block;
      if (allowed != true) allAllowed = false;
    }
    return allAllowed ? PermissionAnswer.allow : null;
  }

  /// Saves the user's answer in the prompt. The engine keeps its own copy
  /// of prompt answers, so it is not told.
  Future<void> remember(
    String origin,
    Set<SitePermission> permissions, {
    required bool allowed,
    required bool incognito,
  }) async {
    if (incognito) {
      for (final permission in permissions) {
        _private[(origin, permission)] = allowed;
      }
      return;
    }
    await _db.setSitePermissions(origin, [
      for (final p in permissions) p.name,
    ], allowed);
  }

  /// Every saved decision (not those of private tabs), by site.
  Stream<List<SitePermissionEntry>> watchAll() =>
      _db.watchSitePermissions().map(
        (rows) => [
          for (final row in rows)
            if (_byName[row.permission] case final permission?)
              (
                origin: row.origin,
                permission: permission,
                allowed: row.allowed,
              ),
        ],
      );

  /// Changes a decision from the settings; [allowed] null: ask next time.
  Future<void> change(
    String origin,
    SitePermission permission, {
    required bool? allowed,
  }) async {
    if (allowed == null) {
      await _db.forgetSitePermission(origin, permission.name);
    } else {
      await _db.setSitePermissions(origin, [permission.name], allowed);
    }
    await _engine.setSitePermission(origin, {permission}, allowed);
  }

  /// Forgets everything saved for [origin].
  Future<void> forgetSite(
    String origin,
    Set<SitePermission> permissions,
  ) async {
    await _db.forgetSitePermissions(origin);
    await _engine.setSitePermission(origin, permissions, null);
  }

  static final _byName = {for (final p in SitePermission.values) p.name: p};
}

final sitePermissionStoreProvider = Provider<SitePermissionStore>(
  (ref) => SitePermissionStore(
    ref.watch(databaseProvider),
    ref.watch(engineProvider),
  ),
);

/// "meet.google.com" for "https://meet.google.com"; the origin itself when
/// it has no host.
String siteName(String origin) {
  final uri = Uri.tryParse(origin);
  if (uri == null || uri.host.isEmpty) return origin;
  final defaultPort =
      (uri.scheme == 'https' && uri.port == 443) ||
      (uri.scheme == 'http' && uri.port == 80);
  return uri.hasPort && !defaultPort ? '${uri.host}:${uri.port}' : uri.host;
}
