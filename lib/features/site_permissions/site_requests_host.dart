import 'package:flutter/widgets.dart';

import '../../engine/browser_engine.dart';
import '../page_dialogs/page_dialogs.dart';
import '../screen_share/screen_share_picker.dart';
import 'permission_prompt.dart';

/// Everything a page can ask the user, drawn by 6browser over the tab:
/// permissions (camera, microphone...), the screen share picker and the
/// page's own dialogs.
class SiteRequestsHost extends StatelessWidget {
  const SiteRequestsHost({super.key, required this.view, required this.child});

  final BrowserView view;
  final Widget child;

  @override
  Widget build(BuildContext context) => SitePermissionHost(
    view: view,
    child: ScreenShareHost(
      view: view,
      child: PageDialogHost(view: view, child: child),
    ),
  );
}
