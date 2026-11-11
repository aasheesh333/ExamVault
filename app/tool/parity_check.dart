// Cross-language digest parity gate — the executable twin of the pinned
// vectors in app/test/hashed_index_test.dart.
//
// `tools/hashed_index.py --emit-vectors` prints the Python producer's digests
// and normalisation results as JSON; this script recomputes every one of them
// with the app's OWN engine (HashedRollIndex) and exits non-zero on any
// mismatch. The app binary-searches what Python hashed: if the two sides
// disagree, every lookup silently answers "not selected" — the worst failure
// this product has. Until this gate existed, the Dart test pinned hardcoded
// vectors and NO CI job ever ran the Python side, so an edit to normalise(),
// DIGEST_BYTES or the salt format shipped green and broke every lookup.
//
// Run by .github/workflows/parity.yml on any change to tools/ or the engine:
//
//   python3 tools/hashed_index.py --emit-vectors > vectors.json
//   cd app && dart run tool/parity_check.dart vectors.json
import 'dart:convert';
import 'dart:io';

import 'package:examvault/features/result_checker/engine/hashed_index.dart';

int _failures = 0;
int _checks = 0;

void _check(String what, Object? actual, Object? expected) {
  _checks++;
  if (actual == expected) {
    stdout.writeln('  ok    $what');
    return;
  }
  _failures++;
  stderr.writeln('  FAIL  $what');
  stderr.writeln('          dart   : $actual');
  stderr.writeln('          python : $expected');
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/parity_check.dart <vectors.json>');
    stderr.writeln('  generate with: python3 tools/hashed_index.py --emit-vectors');
    exit(2);
  }

  final Map<String, dynamic> vectors;
  try {
    final decoded = jsonDecode(File(args.first).readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('vectors file is not a JSON object');
    }
    vectors = decoded;
  } catch (error) {
    stderr.writeln('cannot read ${args.first}: $error');
    exit(2);
  }

  stdout.writeln('parity vectors : ${args.first}');

  final salt = vectors['salt'];
  if (salt is! String || salt.isEmpty) {
    stderr.writeln('vectors file carries no salt');
    exit(2);
  }

  // Wire-format constants: a silent DIGEST_BYTES or mode change on either side
  // is exactly the drift this gate exists to catch.
  _check('mode', HashedRollIndex.mode, vectors['mode']);
  _check('digestBytes', HashedRollIndex.digestBytes, vectors['digest_bytes']);

  final digests = vectors['digests'];
  if (digests is! Map<String, dynamic> || digests.isEmpty) {
    stderr.writeln('vectors file carries no digests');
    exit(2);
  }
  digests.forEach((roll, expected) {
    _check('digest(${jsonEncode(roll)})', HashedRollIndex.digest(roll, salt), expected);
  });

  final normalise = vectors['normalise'];
  if (normalise is! Map<String, dynamic> || normalise.isEmpty) {
    stderr.writeln('vectors file carries no normalise cases');
    exit(2);
  }
  normalise.forEach((input, expected) {
    _check('normalise(${jsonEncode(input)})', HashedRollIndex.normalise(input), expected);
  });

  // End-to-end through the real search path: an index built from the PYTHON
  // digests must answer "found" for every canonical roll (binary search) and
  // "not found" for an absent one.
  final pythonDigests = digests.values.whereType<String>().toList()..sort();
  final index = HashedRollIndex(
    salt: salt,
    hashes: pythonDigests,
    total: pythonDigests.length,
    sorted: true,
  );
  for (final roll in digests.keys) {
    _check('contains(${jsonEncode(roll)}) in python-built index', index.contains(roll), true);
  }
  _check('absent roll stays absent', index.contains('125130000999'), false);

  if (_failures > 0) {
    stderr.writeln(
      'PARITY FAILED: $_failures of $_checks checks differ. Do NOT ship — '
      'every roll lookup would answer "not selected".',
    );
    exit(1);
  }
  stdout.writeln('parity OK: $_checks checks — python producer and dart engine agree');
}
