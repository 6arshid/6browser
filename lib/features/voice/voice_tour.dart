import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/browser_commands.dart';
import '../../ui/toolbar.dart' show compactBreakpoint;
import '../settings/app_settings.dart';
import 'voice_language.dart';
import 'voice_panel.dart';

/// Whether the first-run tour of voice commands may show. main() turns it
/// on; tests leave it off unless they are about the tour.
final voiceTourEnabledProvider = Provider<bool>((ref) => false);

/// Settings key, set once the tour has been finished or skipped.
const voiceTourSeenSetting = 'voiceTourSeen';

/// Asks the shell to show the tour again (Settings > Voice commands).
final voiceTourRequestProvider = NotifierProvider<VoiceTourRequests, int>(
  VoiceTourRequests.new,
);

class VoiceTourRequests extends Notifier<int> {
  @override
  int build() => 0;

  void show() => state++;
}

/// How the tour ended.
enum VoiceTourResult { skipped, tryIt }

/// Shows the tour over the whole window, pointing at [target] (the address
/// bar microphone). Tapping the microphone, or "Try it now" on the last
/// step, ends it with [VoiceTourResult.tryIt].
Future<VoiceTourResult> showVoiceTour(
  BuildContext context, {
  required GlobalKey target,
}) async {
  final result = await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<VoiceTourResult>(
      opaque: false,
      // The tour animates itself in and out.
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => VoiceTour(target: target),
    ),
  );
  return result ?? VoiceTourResult.skipped;
}

/// What to say in the tour's demo, and what happens, in the language the
/// user speaks. Commands are understood in English, Persian and Danish.
List<(String said, String does)> voiceTourExamples(VoiceLanguage language) =>
    switch (language.code) {
      'fa' => const [
        ('جستجو کن ایران', 'Searches the web'),
        ('برو به یوتیوب', 'Opens youtube.com'),
        ('تو یوتیوب موزیک ایرانی رو سرچ کن', 'Plays it on YouTube'),
        ('یه تب جدید باز کن', 'Opens a new tab'),
        ('برگرد', 'Goes back a page'),
      ],
      'da' => const [
        ('søg efter Iran', 'Searches the web'),
        ('åbn YouTube', 'Opens youtube.com'),
        ('afspil dansk musik', 'Plays it on YouTube'),
        ('ny fane', 'Opens a new tab'),
        ('gå tilbage', 'Goes back a page'),
      ],
      _ => const [
        ('search Iran', 'Searches the web'),
        ('open YouTube', 'Opens youtube.com'),
        ('play Persian music', 'Plays it on YouTube'),
        ('new tab', 'Opens a new tab'),
        ('go back', 'Goes back a page'),
      ],
    };

const _steps = 3;

/// How long the card takes to settle into a new step.
const _settle = Duration(milliseconds: 300);

/// A spotlight on the microphone with a card that walks through voice
/// commands in three steps.
class VoiceTour extends ConsumerStatefulWidget {
  const VoiceTour({super.key, required this.target});

  final GlobalKey target;

  @override
  ConsumerState<VoiceTour> createState() => _VoiceTourState();
}

class _VoiceTourState extends ConsumerState<VoiceTour>
    with TickerProviderStateMixin {
  /// 0 to 1: the backdrop closes in on the microphone, then the card rises.
  late final _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
    reverseDuration: const Duration(milliseconds: 280),
  );

  /// Rings that spread from the microphone, over and over.
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  int _step = 0;
  bool _forward = true;
  bool _closing = false;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _intro.value = 1;
      _pulse.stop();
    } else {
      if (_intro.status == AnimationStatus.dismissed && !_closing) {
        _intro.forward();
      }
      if (!_pulse.isAnimating) _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _close(VoiceTourResult result) async {
    if (_closing) return;
    _closing = true;
    _pulse.stop();
    if (!_still) await _intro.reverse();
    if (mounted) Navigator.of(context).pop(result);
  }

  void _go(int step) {
    if (_closing || step < 0) return;
    if (step >= _steps) {
      _close(VoiceTourResult.tryIt);
      return;
    }
    setState(() {
      _forward = step > _step;
      _step = step;
    });
  }

  /// Where the microphone is, in window coordinates (the tour covers the
  /// whole window), or null when it is not on screen.
  Rect? _target(Size screen) {
    final box = widget.target.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.isEmpty || !(Offset.zero & screen).overlaps(rect)) return null;
    return rect;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final scheme = Theme.of(context).colorScheme;
    final width = math.min(380.0, screen.width - 32);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _close(VoiceTourResult.skipped),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _go(_step + 1),
        const SingleActivator(LogicalKeyboardKey.enter): () => _go(_step + 1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _go(_step - 1),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: Listenable.merge([_intro, _pulse]),
            builder: (context, _) {
              final hole = _target(screen);
              final reveal = Curves.easeInOutCubic.transform(
                const Interval(0, 0.62).transform(_intro.value),
              );
              final card = Curves.easeOutCubic.transform(
                const Interval(0.38, 1).transform(_intro.value),
              );
              return Stack(
                children: [
                  // The backdrop takes every click, so the browser below
                  // waits until the tour is over.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: CustomPaint(
                        painter: _SpotlightPainter(
                          hole: hole,
                          reveal: reveal,
                          pulse: _still ? null : _pulse.value,
                          accent: scheme.primary,
                        ),
                      ),
                    ),
                  ),
                  if (hole != null)
                    Positioned.fromRect(
                      rect: Rect.fromCircle(
                        center: hole.center,
                        radius: _holeRadius(hole),
                      ),
                      child: Semantics(
                        button: true,
                        label: 'Try a voice command now',
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            key: const ValueKey('voice-tour-mic'),
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _close(VoiceTourResult.tryIt),
                          ),
                        ),
                      ),
                    ),
                  _placeCard(
                    screen: screen,
                    hole: hole,
                    width: width,
                    child: Opacity(
                      opacity: card,
                      child: Transform.translate(
                        offset: Offset(0, 14 * (1 - card)),
                        child: Transform.scale(
                          scale: 0.96 + 0.04 * card,
                          child: _card(context, hole, width),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Below the microphone when it is in the top half of the window (the
  /// toolbar), above it otherwise, and centered when it is not on screen.
  Widget _placeCard({
    required Size screen,
    required Rect? hole,
    required double width,
    required Widget child,
  }) {
    if (hole == null) {
      return Center(
        child: SizedBox(width: width, child: child),
      );
    }
    final left = (hole.center.dx - width / 2)
        .clamp(16.0, math.max(16.0, screen.width - width - 16))
        .toDouble();
    final gap = _holeRadius(hole) - hole.height / 2 + 14;
    final below = hole.center.dy < screen.height / 2;
    return Positioned(
      left: left,
      width: width,
      top: below ? hole.bottom + gap : null,
      bottom: below ? null : screen.height - hole.top + gap,
      child: child,
    );
  }

  Widget _card(BuildContext context, Rect? hole, double width) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final language = ref.watch(appSettingsProvider).voiceLanguage;
    final screen = MediaQuery.sizeOf(context);
    final below = hole != null && hole.center.dy < screen.height / 2;
    final last = _step == _steps - 1;

    // The arrow points at the microphone from the card's edge.
    double? arrowX;
    if (hole != null) {
      final left = (hole.center.dx - width / 2).clamp(
        16.0,
        math.max(16.0, screen.width - width - 16),
      );
      arrowX = (hole.center.dx - left).clamp(24.0, width - 24.0);
    }

    final body = Material(
      color: scheme.surface,
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'NEW',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'VOICE CONTROL',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_step + 1} of $_steps',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: AnimatedSize(
                duration: _still ? Duration.zero : _settle,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: _still
                      ? Duration.zero
                      : const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) {
                    final incoming = child.key == ValueKey(_step);
                    final dx = (_forward == incoming ? 1 : -1) * 0.12;
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween(
                          begin: Offset(dx, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _stepContent(context, language),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (var i = 0; i < _steps; i++)
                  AnimatedContainer(
                    duration: _still ? Duration.zero : _settle,
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.only(right: 5),
                    width: i == _step ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _step
                          ? scheme.primary
                          : scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                const Spacer(),
                if (!last)
                  TextButton(
                    onPressed: () => _close(VoiceTourResult.skipped),
                    child: const Text('Skip'),
                  ),
                if (_step > 0)
                  TextButton(
                    onPressed: () => _go(_step - 1),
                    child: const Text('Back'),
                  ),
                const SizedBox(width: 4),
                if (last)
                  FilledButton.icon(
                    onPressed: () => _go(_step + 1),
                    icon: const Icon(CupertinoIcons.mic_fill, size: 16),
                    label: const Text('Try it now'),
                  )
                else
                  FilledButton(
                    onPressed: () => _go(_step + 1),
                    child: const Text('Next'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    if (arrowX == null) return body;
    final arrow = Padding(
      padding: EdgeInsets.only(left: arrowX - 9),
      child: CustomPaint(
        size: const Size(18, 9),
        painter: _ArrowPainter(color: scheme.surface, up: below),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: below ? [arrow, body] : [body, arrow],
    );
  }

  Widget _stepContent(BuildContext context, VoiceLanguage language) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final title = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    final text = theme.textTheme.bodyMedium?.copyWith(
      color: muted,
      height: 1.45,
    );
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Talk to 6browser', style: title),
            const SizedBox(height: 8),
            Text(
              'The microphone in the address bar works on every page. '
              'Click it and say what you want, and 6browser does it.',
              style: text,
            ),
          ],
        );
      case 1:
        final supported = const {'en', 'fa', 'da'}.contains(language.code);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Just say it', style: title),
            const SizedBox(height: 8),
            Text(
              supported
                  ? 'Search, open a site, play music, open a tab or go '
                        'back, in plain words.'
                  : 'Commands are understood in English, Persian and '
                        'Danish; in other languages, what you say is '
                        'searched for.',
              style: text,
            ),
            const SizedBox(height: 14),
            _SpeechDemo(
              examples: voiceTourExamples(language),
              animate: !_still,
            ),
          ],
        );
      default:
        final whisper = ref.watch(usesWhisperModelsProvider);
        final settings = ref.watch(appSettingsProvider);
        final keyboard = MediaQuery.sizeOf(context).width >= compactBreakpoint;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Made for you', style: title),
            const SizedBox(height: 12),
            _Feature(
              icon: CupertinoIcons.globe,
              text:
                  'You speak ${language.label}. Change it in Settings › '
                  'Voice commands, or with the globe while listening.',
            ),
            if (whisper)
              _Feature(
                icon: CupertinoIcons.lock_shield,
                text:
                    'Private: speech is recognized on this computer and '
                    'your voice is not sent anywhere. The first time, a '
                    '${settings.voiceModel.size} speech model is '
                    'downloaded.',
              ),
            if (keyboard)
              _Feature(
                icon: CupertinoIcons.keyboard,
                text:
                    'Press ${shortcutFor(BrowserCommand.voiceCommand)} on '
                    'any page to turn listening on or off.',
              ),
          ],
        );
    }
  }
}

/// How far the spotlight reaches around the microphone.
double _holeRadius(Rect hole) => hole.longestSide / 2 + 4;

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A command being spoken: a waveform while the words appear, then what
/// 6browser does with them; then the next example.
class _SpeechDemo extends StatefulWidget {
  const _SpeechDemo({required this.examples, required this.animate});

  final List<(String said, String does)> examples;
  final bool animate;

  @override
  State<_SpeechDemo> createState() => _SpeechDemoState();
}

class _SpeechDemoState extends State<_SpeechDemo>
    with SingleTickerProviderStateMixin {
  static const _perExample = Duration(milliseconds: 3200);

  late final _clock = AnimationController(
    vsync: this,
    duration: _perExample * widget.examples.length,
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _clock.repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final count = widget.examples.length;
        final at = widget.animate ? _clock.value * count : 0.999;
        final index = at.floor() % count;
        final t = at - at.floorToDouble(); // 0 to 1 within this example
        final (said, does) = widget.examples[index];
        final letters = said.characters;
        // Listening, then the words appear, then the result shows.
        final typed = widget.animate
            ? letters
                  .take(
                    (letters.length * const Interval(0.1, 0.5).transform(t))
                        .round(),
                  )
                  .toString()
            : said;
        final listening = widget.animate && t < 0.56;
        final result = widget.animate
            ? const Interval(0.6, 0.7).transform(t) *
                  (1 - const Interval(0.93, 1).transform(t))
            : 1.0;
        final seconds =
            _clock.value * (_perExample.inMilliseconds * count) / 1000;
        final rtl = voiceTextDirection(said) == TextDirection.rtl;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: listening
                          ? scheme.primary
                          : scheme.primary.withValues(alpha: 0.15),
                    ),
                    child: Icon(
                      CupertinoIcons.mic_fill,
                      size: 17,
                      color: listening ? scheme.onPrimary : scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _Waveform(
                    seconds: seconds,
                    active: listening,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      typed.isEmpty
                          ? ''
                          : rtl
                          ? '«$typed»'
                          : '“$typed”',
                      key: const ValueKey('voice-tour-said'),
                      textDirection: rtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: result,
              child: Transform.translate(
                offset: Offset(0, 6 * (1 - result)),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(
                      CupertinoIcons.arrow_turn_down_right,
                      size: 15,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      does,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Bars that bounce while the demo "listens".
class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.seconds,
    required this.active,
    required this.color,
  });

  final double seconds;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 24,
    child: Row(
      children: [
        for (var i = 0; i < 5; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 3,
            height: active
                ? 5 +
                      17 *
                          (0.5 +
                                  0.5 *
                                      math.sin(
                                        seconds * (7 + i * 1.7) + i * 1.3,
                                      ))
                              .abs()
                : 4,
            decoration: BoxDecoration(
              color: color.withValues(alpha: active ? 0.9 : 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    ),
  );
}

/// The dimmed window with a round opening around the microphone. The
/// opening starts as wide as the window and closes in on it; rings then
/// spread from it.
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({
    required this.hole,
    required this.reveal,
    required this.pulse,
    required this.accent,
  });

  final Rect? hole;
  final double reveal;
  final double? pulse;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()
      ..color = Colors.black.withValues(alpha: 0.62 * reveal);
    final hole = this.hole;
    if (hole == null) {
      canvas.drawRect(Offset.zero & size, scrim);
      return;
    }
    final center = hole.center;
    final far = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - center).distance).reduce(math.max);
    final radius = lerpDouble(far, _holeRadius(hole), reveal)!;
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addOval(Rect.fromCircle(center: center, radius: radius)),
      scrim,
    );
    final ring = Paint()..style = PaintingStyle.stroke;
    canvas.drawCircle(
      center,
      radius,
      ring
        ..strokeWidth = 2
        ..color = accent.withValues(alpha: 0.95 * reveal),
    );
    final pulse = this.pulse;
    if (pulse == null || reveal < 1) return;
    for (var i = 0; i < 2; i++) {
      final p = (pulse + i / 2) % 1;
      canvas.drawCircle(
        center,
        radius + 3 + 30 * Curves.easeOut.transform(p),
        ring
          ..strokeWidth = 2.5 * (1 - p) + 0.5
          ..color = accent.withValues(alpha: 0.7 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole ||
      old.reveal != reveal ||
      old.pulse != pulse ||
      old.accent != accent;
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.color, required this.up});

  final Color color;
  final bool up;

  @override
  void paint(Canvas canvas, Size size) {
    final path = up
        ? (Path()
            ..moveTo(0, size.height)
            ..lineTo(size.width / 2, 0)
            ..lineTo(size.width, size.height))
        : (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width / 2, size.height)
            ..lineTo(size.width, 0));
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color || old.up != up;
}
