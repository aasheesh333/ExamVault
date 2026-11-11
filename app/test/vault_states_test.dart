import 'dart:io';

import 'package:examvault/features/vault/admit_card_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import 'support/matrix.dart';

/// The vault tab must never claim the vault is empty while it is still loading
/// or when the encrypted store failed to open.
///
/// The layout matrix renders these states but only asserts geometry — this pins
/// the *meaning* of each state, which is the part that was wrong: a slow
/// Keystore read greeted users with "Your vault is empty" + an Add CTA over a
/// vault that was full, and a Keystore failure claimed emptiness forever.
void main() {
  late Directory hiveDir;
  late MatrixEnv env;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('ev_vault_states');
    Hive.init(hiveDir.path);
  });

  setUp(() async {
    env = await MatrixEnv.open();
  });

  tearDownAll(() async {
    try {
      if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('loading vault says "reading", not "empty"', (tester) async {
    await pumpMatrix(
      tester,
      const AdmitCardDetailScreen(),
      matrixPoints[1],
      env: env,
      hangVault: true,
    );

    expect(find.text('Your vault is empty'), findsNothing);
    expect(find.text('Add admit card'), findsNothing);
    expect(find.text('Reading your vault…'), findsOneWidget);

    await disposeMatrix(tester);
  });

  testWidgets('failed vault offers a retry, not the empty state', (
    tester,
  ) async {
    await pumpMatrix(
      tester,
      const AdmitCardDetailScreen(),
      matrixPoints[1],
      env: env,
      failVault: true,
    );

    expect(find.text('Your vault is empty'), findsNothing);
    expect(find.text('Could not open your vault'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await disposeMatrix(tester);
  });

  testWidgets('genuinely empty vault still shows the empty state', (
    tester,
  ) async {
    await pumpMatrix(
      tester,
      const AdmitCardDetailScreen(),
      matrixPoints[1],
      env: env,
    );

    expect(find.text('Your vault is empty'), findsOneWidget);
    expect(find.text('Reading your vault…'), findsNothing);

    await disposeMatrix(tester);
  });
}
