import 'dart:typed_data';

import 'package:examvault/app.dart';
import 'package:examvault/data/remote/cdn_client.dart';
import 'package:examvault/data/repositories/admit_card_repository.dart';
import 'package:examvault/data/services/share_service.dart';
import 'package:examvault/features/shell/root_shell.dart';
import 'package:examvault/providers/app_providers.dart';
import 'package:examvault/shared/widgets/ev_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:share_plus/share_plus.dart';

import 'support/fake_vault_store.dart';
import 'support/matrix.dart';

/// Tap every control on every screen and assert nothing breaks.
///
/// The layout matrix proves screens *look* right. This proves they *work*: it
/// walks the real app, presses every tappable surface one at a time, and asserts
/// that no tap throws, **no tap is dead**, and the app is still usable
/// afterwards.
///
/// ## The "no tap is dead" contract
///
/// The doc comment above always promised this, but the old body never checked
/// it: a button whose `onPressed` was silently null, or wired to nothing, walked
/// green as long as it did not throw. Now every tap is bracketed by a
/// fingerprint of the visible UI — all rendered Text data in tree order, the
/// Dialog and BottomSheet counts, and the selected tab index — and a tap whose
/// fingerprint is unchanged afterwards is collected into ONE failure list.
///
/// Three classes of surface change nothing *by design* and are excluded, each
/// re-checked at tap time (an earlier tap can change which one applies):
///
///  * **disabled controls** — the product renders them at 55% opacity with
///    `enabled: false` semantics and a null handler (e.g. Radar's "Check my
///    result instantly" with no exam resolved). Doing nothing is correct.
///  * **the already-selected tab button** — `RootShell` ignores re-selecting
///    the current tab (`if (active == t) return;`).
///  * **the already-selected filter chip** — re-selecting the active category
///    is a no-op.
///
/// Targets whose element unmounted or moved off-screen before their turn are
/// skipped, not failed: earlier taps legitimately reshape the tree (a filter
/// chip re-orders the radar list), and a stale coordinate pressing blank
/// canvas says nothing about the product.
///
/// It is deliberately blunt otherwise. A dead button and a crash both fall out
/// of it, which is exactly the class of bug a screenshot review cannot see.
void main() {
  late Box<dynamic> cacheBox;
  late Box<dynamic> settingsBox;
  late FakeVaultStore store;

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    cacheBox = await Hive.openBox<dynamic>('tc$stamp', bytes: Uint8List(0));
    settingsBox = await Hive.openBox<dynamic>('ts$stamp', bytes: Uint8List(0));
    store = FakeVaultStore();
  });

  Widget app() {
    final feed = matrixFeedJson();
    final mock = MockClient((req) async {
      if (req.url.path.contains('live_feed')) {
        // UTF-8 content-type like the real edge (see matrix.dart's pumpMatrix):
        // Response(String) defaults to latin1, which cannot carry Devanagari.
        return http.Response(
          feed,
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('', 404);
    });

    return ProviderScope(
      overrides: [
        httpCacheBoxProvider.overrideWithValue(cacheBox),
        settingsBoxProvider.overrideWithValue(settingsBox),
        admitCardRepositoryProvider.overrideWith(
          (ref) => AdmitCardRepository(store: store),
        ),
        cdnClientProvider.overrideWithValue(
          CdnClient(cache: cacheBox, client: mock, baseUrl: 'https://cdn.test'),
        ),
        // WHY: the real ShareService rasterises via RepaintBoundary.toImage —
        // a genuinely asynchronous GPU round-trip that never completes on the
        // widget-test fake clock. The share screen would sit in `_sharing`
        // forever, and its re-entrancy guard would then make every later share
        // tap legitimately dead — an artefact of the test environment, not a
        // product fact. The instant fake exercises the same code path
        // (capture → null → text fallback → SnackBar), so share controls show
        // real visible feedback and the walk can judge them honestly.
        shareServiceProvider.overrideWithValue(_InstantShareService()),
      ],
      child: const ExamVaultApp(),
    );
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    });

    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
    // The canned feed's response only completes on the real event loop (the
    // same limitation search_test.dart documents), so without this hop the walk
    // presses controls on the cold-start sentinel — a screen that says it is
    // still checking and that no user stays on. A filter chip there legitimately
    // changes nothing, which the dead-tap check would report as a wiring bug.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Every tab, walked in turn.
  const tabs = ['Home', 'Vault', 'Radar', 'Share'];

  for (final tab in tabs) {
    testWidgets('every control on $tab is alive', (tester) async {
      await pumpApp(tester);
      // `.last`, not `.first`: tab labels are plain words that body copy may
      // legitimately contain elsewhere on screen; the bar's own label is what
      // must be pressed. (Same convention as app_smoke_test.dart.)
      await tester.tap(find.text(tab).last);
      // TWO duration pumps, here and after every tap in this file: one `pump`
      // is one frame, and an animation's first tick only *starts* the ticker
      // (elapsed 0) — a single `pump(300ms)` advances the clock but leaves the
      // 220ms cross-fade at value 0. The second frame completes it and flushes
      // the rebuild that flips the outgoing tab Offstage. Without this, ghost
      // controls from the previous tab (invisible, pointer-ignored, but still
      // on stage) leak into the snapshot and the fingerprints.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      // Snapshot the tappables by ELEMENT, then press them one at a time: the
      // tree changes after each press, so holding Finder objects would go
      // stale — but holding elements lets the walk notice when a target has
      // unmounted or moved, and re-read its (possibly rebuilt) widget.
      final screen = Rect.fromLTWH(0, 0, 393, 852);
      final targets = <_Target>[];
      for (final finder in _tappableFinders()) {
        for (final element in finder.evaluate()) {
          final box = element.renderObject as RenderBox?;
          if (box == null || !box.hasSize || !box.attached) continue;
          final rect = box.localToGlobal(Offset.zero) & box.size;
          if (rect.width < 4 || rect.height < 4) continue;
          if (!screen.contains(rect.center)) continue;
          targets.add(_Target(element: element, describe: _describe(element)));
        }
      }

      expect(targets, isNotEmpty, reason: '$tab must expose controls');

      final deadTaps = <String>[];
      var tapped = 0;

      for (final t in targets) {
        // Stale target: the walk itself reshapes the tree (filters re-order
        // lists, sheets come and go). An element that is gone — or whose
        // centre left the screen — is skipped, not judged.
        if (!t.element.mounted) continue;
        final box = t.element.renderObject as RenderBox?;
        if (box == null || !box.hasSize || !box.attached) continue;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (!screen.contains(rect.center)) continue;

        // Inert-by-design, re-checked NOW: which tab/chip is selected and
        // which handlers are wired can both have changed since the snapshot.
        final inert = _inertReasonNow(tester, t.element);
        if (inert != null) continue;

        final before = _fingerprint(tester);
        await tester.tapAt(rect.center);
        // Two frames (see the tab-switch comment): the first starts any
        // animation the tap kicked off, the second completes it and flushes
        // the cross-fade's Offstage flip, so the after-fingerprint sees the
        // settled tree, not outgoing ghosts.
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 250));
        tapped++;

        // Whatever the tap did, it must not have thrown.
        final error = tester.takeException();
        expect(
          error,
          isNull,
          reason:
              'Tapping ${rect.center.dx.toInt()},${rect.center.dy.toInt()} '
              'on $tab threw: $error',
        );

        final after = _fingerprint(tester);
        if (before == after) {
          deadTaps.add(
            '${t.describe} at ${rect.center.dx.toInt()},'
            '${rect.center.dy.toInt()} changed nothing',
          );
        }

        // Leave the screen in a known state before the next press: overlays
        // (menus, dialogs, sheets) would otherwise absorb it, a floating
        // SnackBar would swallow taps over the dock, and a tab switch would
        // leave every remaining coordinate pointing at the wrong screen.
        await _dismissOverlays(tester);
        await _returnToTab(tester, tab);
      }

      expect(tapped, greaterThan(0), reason: '$tab walk pressed nothing');

      // ONE failure listing every dead tap, so a screen with three wiring bugs
      // is one actionable report instead of a stop-at-first walk.
      expect(
        deadTaps,
        isEmpty,
        reason:
            'Dead taps on $tab — controls whose press changed nothing '
            '(no text, overlay or tab-index change):\n'
            '  ${deadTaps.join('\n  ')}',
      );

      // The app must still be showing a screen, not a blank frame.
      expect(
        find.byType(Scaffold),
        findsWidgets,
        reason: '$tab ended up with no scaffold after the walk',
      );
    });
  }

  testWidgets('back from every tab returns to Home, never exits', (
    tester,
  ) async {
    await pumpApp(tester);

    for (final tab in ['Vault', 'Radar', 'Share']) {
      // `.last` for the same reason as the walk above.
      await tester.tap(find.text(tab).last);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      // Simulate the Android system back gesture.
      final popped = await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        popped,
        isTrue,
        reason: 'back on $tab must be handled in-app, not passed to the OS',
      );
      expect(
        find.text('Command Center'),
        findsWidgets,
        reason: 'back on $tab should land on Home',
      );
    }
  });
}

/// The widget types the walk treats as user-tappable surfaces.
List<Finder> _tappableFinders() => <Finder>[
  find.byType(InkWell),
  find.byType(GestureDetector),
  find.byType(IconButton),
  find.byType(TextButton),
  find.byType(Switch),
];

/// One snapshotted tap target.
class _Target {
  _Target({required this.element, required this.describe});

  final Element element;
  final String describe;
}

/// A fingerprint of everything a tap can visibly change: all rendered text in
/// tree order, the overlay counts, and the selected tab. Deliberately blunt —
/// if none of this moved, the user saw nothing happen.
String _fingerprint(WidgetTester tester) {
  final texts = StringBuffer();
  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final s = w.data ?? w.textSpan?.toPlainText() ?? '';
    if (s.trim().isEmpty) continue;
    texts
      ..write(s)
      ..write('\u241F'); // unit separator: keeps adjacent strings distinct
  }
  return '$texts'
      '#dialogs=${find.byType(Dialog).evaluate().length}'
      '#sheets=${find.byType(BottomSheet).evaluate().length}'
      '#tab=${_currentTab(tester).index}';
}

EvTab _currentTab(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(RootShell)),
    listen: false,
  );
  return container.read(tabIndexProvider);
}

/// Why pressing [element] right now is *supposed* to do nothing, or null when
/// the control is live. See the file header for the three documented classes.
String? _inertReasonNow(WidgetTester tester, Element element) {
  final w = element.widget;

  // Disabled controls: every Ev* control gates its InkWell/GestureDetector
  // handler and dims to 55% opacity when disabled; the framework's own
  // IconButton/TextButton/Switch null their callbacks the same way.
  if (w is InkWell &&
      w.onTap == null &&
      w.onDoubleTap == null &&
      w.onLongPress == null) {
    return 'disabled surface (InkWell without handler)';
  }
  if (w is GestureDetector &&
      w.onTap == null &&
      w.onTapDown == null &&
      w.onTapUp == null &&
      w.onDoubleTap == null &&
      w.onLongPress == null &&
      w.onSecondaryTap == null) {
    return 'disabled surface (GestureDetector without handler)';
  }
  if (w is IconButton && w.onPressed == null) return 'disabled IconButton';
  if (w is TextButton && w.onPressed == null && w.onLongPress == null) {
    return 'disabled TextButton';
  }
  if (w is Switch && w.onChanged == null) return 'disabled Switch';

  // The selected tab button: RootShell ignores re-selecting the current tab.
  // Recomputed per tap — earlier taps (a wallet card, "N saved", a radar row)
  // switch tabs, so "selected" is a moving fact.
  if (_hasAncestorWidget<EvTabBar>(element)) {
    if (_tabLabelIn(element) == _currentTab(tester).label) {
      return 'the already-selected tab button';
    }
  }

  // The selected filter chip: select(same category) is a no-op by design.
  final chip = _ancestorWidget<EvChip>(element);
  if (chip != null && chip.selected) {
    return 'the already-selected "${chip.label}" chip';
  }

  return null;
}

/// Type + first recognisable label, enough to find a dead control in lib/.
String _describe(Element element) {
  final label = _firstLabelIn(element);
  return '${element.widget.runtimeType}'
      '${label == null ? '' : ' "$label"'}';
}

String? _firstLabelIn(Element element) {
  String? label;
  void visit(Element e) {
    if (label != null) return;
    final w = e.widget;
    if (w is Text && w.data != null && w.data!.trim().isNotEmpty) {
      label = w.data!.trim();
    } else if (w is Icon && w.icon != null) {
      label ??= 'icon:0x${w.icon!.codePoint.toRadixString(16)}';
    }
    e.visitChildren(visit);
  }

  element.visitChildren(visit);
  return label;
}

/// The tab label rendered inside a tab button.
///
/// A tab button paints its Icon *before* its label Text, so the generic
/// [_firstLabelIn] scan reports the icon; the selected-tab exclusion needs the
/// actual label.
String? _tabLabelIn(Element element) {
  final labels = EvTab.values.map((t) => t.label).toSet();
  String? found;
  void visit(Element e) {
    if (found != null) return;
    final w = e.widget;
    if (w is Text && w.data != null && labels.contains(w.data)) {
      found = w.data;
    }
    e.visitChildren(visit);
  }

  element.visitChildren(visit);
  return found;
}

bool _hasAncestorWidget<T extends Widget>(Element element) =>
    _ancestorWidget<T>(element) != null;

T? _ancestorWidget<T extends Widget>(Element element) {
  T? found;
  element.visitAncestorElements((a) {
    final w = a.widget;
    if (w is T) {
      found = w;
      return false;
    }
    return true;
  });
  return found;
}

/// Restore the pre-tap surface: close menus/dialogs/sheets, drop SnackBars,
/// and go back to the tab under test if the tap navigated away.
///
/// WHY: a left-over floating SnackBar sits over the dock and swallows every
/// later tap aimed there; a sheet or popup menu absorbs them wholesale; and a
/// tab switch leaves every remaining snapshotted coordinate pointing at the
/// wrong screen. Without this the walk's later taps measure the overlay, not
/// the product.
Future<void> _dismissOverlays(WidgetTester tester) async {
  // Bounded: the form sheet's dirty-guard could in principle surface a
  // discard dialog behind a popped sheet; four pops is far more than the app
  // ever stacks, and the loop must not spin if a pop fails to dismiss.
  for (var i = 0; i < 4; i++) {
    final overlayOpen =
        find.byType(Dialog).evaluate().isNotEmpty ||
        find.byType(BottomSheet).evaluate().isNotEmpty ||
        find
            .byWidgetPredicate((w) => w is PopupMenuItem<Object?>)
            .evaluate()
            .isNotEmpty;
    if (!overlayOpen) break;
    // Direct pop, not a barrier tap at a guessed coordinate: a popup menu can
    // cover anywhere on screen, and only its items are dangerous to hit.
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.pop();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    tester.takeException();
  }

  // SnackBars go without animation: clearSnackBars also cancels the pending
  // auto-hide timer, so nothing leaks into teardown.
  if (find.byType(SnackBar).evaluate().isNotEmpty) {
    final messenger = tester.state<ScaffoldMessengerState>(
      find.byType(ScaffoldMessenger).first,
    );
    messenger.clearSnackBars();
    await tester.pump();
    tester.takeException();
  }
}

Future<void> _returnToTab(WidgetTester tester, String tab) async {
  if (_currentTab(tester).label == tab) return;
  await tester.tap(find.text(tab).last);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
  tester.takeException();
}

/// Share that completes instantly and without platform channels — see the
/// override site in `app()` for why the walk needs this.
class _InstantShareService extends ShareService {
  @override
  Future<Uint8List?> capturePng(GlobalKey key, {double pixelRatio = 3.0}) =>
      Future.value(null); // forces the text-fallback path, which shows a SnackBar

  @override
  Future<ShareResult> shareCardImage({
    required Uint8List png,
    required String caption,
    required String subject,
    Rect? origin,
    String fileName = 'examvault_result.png',
  }) => Future.value(const ShareResult('walk', ShareResultStatus.success));

  @override
  Future<ShareResult> shareText({
    required String caption,
    required String subject,
    Rect? origin,
  }) => Future.value(const ShareResult('walk', ShareResultStatus.success));

  @override
  Future<void> clearCache() => Future.value();
}
