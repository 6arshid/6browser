/// Data model for importing bookmarks, saved logins and the extension list
/// from other desktop browsers.
library;

/// A browser family we know how to read data from.
enum SourceBrowser {
  chrome('Google Chrome', _EngineKind.chromium),
  edge('Microsoft Edge', _EngineKind.chromium),
  brave('Brave', _EngineKind.chromium),
  firefox('Mozilla Firefox', _EngineKind.firefox);

  const SourceBrowser(this.displayName, this._engine);

  final String displayName;
  final _EngineKind _engine;

  bool get isChromium => _engine == _EngineKind.chromium;
  bool get isFirefox => _engine == _EngineKind.firefox;
}

enum _EngineKind { chromium, firefox }

/// One profile directory belonging to a [SourceBrowser].
///
/// Chromium browsers can have several ("Default", "Profile 1", ...); Firefox
/// uses randomly named profile folders.
class BrowserProfile {
  const BrowserProfile({
    required this.browser,
    required this.name,
    required this.path,
  });

  final SourceBrowser browser;

  /// Human label, e.g. "Default" or a Firefox profile name.
  final String name;

  /// Absolute path to the profile directory.
  final String path;

  String get label => '${browser.displayName} — $name';
}

class ImportedBookmark {
  const ImportedBookmark({
    required this.url,
    required this.title,
    this.folders = const [],
  });

  final String url;
  final String title;

  /// Folder names from the bookmarks bar down to this bookmark; empty for a
  /// bookmark on the bar itself.
  final List<String> folders;
}

/// Where bookmarks that were outside the source browser's bookmarks bar go.
const otherBookmarksFolder = 'Other bookmarks';

class ImportedLogin {
  const ImportedLogin({
    required this.url,
    required this.username,
    required this.password,
  });

  final String url;
  final String username;
  final String password;
}

class ImportedExtension {
  const ImportedExtension({
    required this.id,
    required this.name,
    this.version,
    this.enabled = true,
    this.webStoreUrl,
  });

  final String id;
  final String name;
  final String? version;
  final bool enabled;

  /// Chrome Web Store / AMO URL, when the id maps to a known store.
  final String? webStoreUrl;
}

/// Why a category could not be read, so the UI can be honest instead of
/// pretending the data is empty.
class ImportIssue {
  const ImportIssue(this.category, this.message);

  final String category;
  final String message;
}

/// Everything read from a single profile.
class ProfileImport {
  const ProfileImport({
    required this.profile,
    this.bookmarks = const [],
    this.logins = const [],
    this.extensions = const [],
    this.issues = const [],
  });

  final BrowserProfile profile;
  final List<ImportedBookmark> bookmarks;
  final List<ImportedLogin> logins;
  final List<ImportedExtension> extensions;
  final List<ImportIssue> issues;
}
