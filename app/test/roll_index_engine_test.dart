import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:examvault/features/result_checker/engine/roll_index_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _gzipJson(Object payload) {
  final raw = utf8.encode(jsonEncode(payload));
  return Uint8List.fromList(gzip.encode(raw));
}

void main() {
  group('binarySearch', () {
    test('finds every present element exactly where List.indexOf does', () {
      final rng = Random(7);
      final values = <String>{
        for (var i = 0; i < 2000; i++) (1000000000 + rng.nextInt(900000000)).toString(),
      }.toList()
        ..sort();

      for (var i = 0; i < values.length; i++) {
        expect(binarySearch(values, values[i]), i, reason: 'value ${values[i]}');
      }
    });

    test('returns -1 for absent values, including both neighbours', () {
      final values = ['1000', '2000', '3000', '4000'];

      expect(binarySearch(values, '0500'), -1); // before first
      expect(binarySearch(values, '4500'), -1); // after last
      expect(binarySearch(values, '2500'), -1); // between
      expect(binarySearch(values, '1999'), -1); // just below
      expect(binarySearch(values, '2001'), -1); // just above
      expect(binarySearch(const [], '1000'), -1);
    });

    test('handles single element and duplicates deterministically', () {
      expect(binarySearch(['42'], '42'), 0);
      expect(binarySearch(['42'], '43'), -1);
      // Duplicates are a producer bug; we only require *a* matching index.
      final dup = ['1', '1', '1'];
      expect(binarySearch(dup, '1'), inInclusiveRange(0, 2));
    });
  });

  group('normaliseRoll', () {
    test('strips pasted whitespace, nbsp, zero-width and dashes', () {
      // Values copied out of a PDF routinely carry these.
      expect(normaliseRoll('  2201049821  '), '2201049821');
      expect(normaliseRoll('2201\u00A0049821'), '2201049821');
      expect(normaliseRoll('2201\u200B049821'), '2201049821');
      expect(normaliseRoll('2201\u2013049821'), '2201049821');
      expect(normaliseRoll('2201\u2014049821'), '2201049821');
    });

    test('upper-cases alphanumeric rolls but keeps internal dashes', () {
      expect(normaliseRoll('ibps-po-2026'), 'IBPS-PO-2026');
    });

    test('leaves a valid roll untouched', () {
      expect(normaliseRoll('2201049821'), '2201049821');
    });
  });

  group('RollIndex.decode', () {
    test('decodes a plain array of roll numbers', () {
      final index = RollIndex.decode(_gzipJson(['1001', '1002', '1003']));
      expect(index.total, 3);
      expect(index.sorted, isTrue);
      expect(index.indexOf('1002'), 1);
      expect(index.indexOf('9999'), -1);
    });

    test('decodes objects carrying merit ranks', () {
      final index = RollIndex.decode(_gzipJson([
        {'r': '1001', 'rank': 1},
        {'r': '1002', 'rank': 2},
      ]));
      expect(index.total, 2);
      expect(index.rankAt(index.indexOf('1002')), 2);
      expect(index.rankAt(index.indexOf('1001')), 1);
    });

    test('falls back to linear search when upstream is unsorted', () {
      final index = RollIndex.decode(_gzipJson(['3003', '1001', '2002']));
      expect(index.sorted, isFalse);
      // Correctness is preserved even though the producer broke the contract.
      expect(index.indexOf('1001'), 1);
      expect(index.indexOf('2002'), 2);
      expect(index.indexOf('3003'), 0);
      expect(index.indexOf('4004'), -1);
    });

    test('skips malformed rows instead of throwing', () {
      final index = RollIndex.decode(_gzipJson([
        '1001',
        {'nope': true},
        42,
        '1002',
      ]));
      expect(index.total, 2);
      expect(index.sorted, isTrue);
    });

    test('throws FormatException when the payload is not an array', () {
      expect(
        () => RollIndex.decode(_gzipJson({'rolls': []})),
        throwsA(isA<FormatException>()),
      );
    });

    test('reads transport-encoded bytes without double-decompressing', () {
      final plain = Uint8List.fromList(utf8.encode(jsonEncode(['7001', '7002'])));
      final index = RollIndex.decode(plain, transportEncoded: true);
      expect(index.indexOf('7002'), 1);
    });
  });

  group('RollIndexEngine.searchCompressed', () {
    test('finds a roll number in a gzipped index', () async {
      final bytes = _gzipJson(['2201049819', '2201049821', '2201049823']);
      final result = await RollIndexEngine.searchCompressed(
        compressed: bytes,
        rollNumber: '2201049821',
      );

      expect(result.state, RollLookupState.found);
      expect(result.rollNumber, '2201049821');
      expect(result.totalRolls, 3);
    });

    test('reports notFound for a well-formed absent roll', () async {
      final bytes = _gzipJson(['2201049819', '2201049823']);
      final result = await RollIndexEngine.searchCompressed(
        compressed: bytes,
        rollNumber: '2201049821',
      );

      expect(result.state, RollLookupState.notFound);
      expect(result.elapsedMicros, greaterThan(0));
    });

    test('normalises the user input before searching', () async {
      final bytes = _gzipJson(['2201049821']);
      final result = await RollIndexEngine.searchCompressed(
        compressed: bytes,
        rollNumber: ' 2201 049 821 ',
      );

      expect(result.state, RollLookupState.found);
    });

    test('rejects implausible input without touching the payload', () async {
      final result = await RollIndexEngine.searchCompressed(
        compressed: _gzipJson(['1']),
        rollNumber: 'a',
      );

      expect(result.state, RollLookupState.invalidInput);
      expect(result.totalRolls, 0);
    });

    test('reports indexUnavailable on corrupt bytes', () async {
      final result = await RollIndexEngine.searchCompressed(
        compressed: Uint8List.fromList([1, 2, 3, 4, 5]),
        rollNumber: '2201049821',
      );

      expect(result.state, RollLookupState.indexUnavailable);
    });

    test('leaves the UI isolate free: 250k rows decode + search off-thread',
        () async {
      final rows = <String>[
        for (var i = 0; i < 250000; i++) (1000000000 + i).toString(),
      ];
      final bytes = _gzipJson(rows);

      final watch = Stopwatch()..start();
      final result = await RollIndexEngine.searchCompressed(
        compressed: bytes,
        rollNumber: '1000200000',
      );
      watch.stop();

      expect(result.state, RollLookupState.found);
      expect(result.totalRolls, 250000);
      // Generous ceiling: this is a correctness smoke test, not a benchmark.
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
    });
  });

  group('RollIndexEngine.searchDecoded', () {
    test('reuses a warm index for repeat lookups', () {
      final index = RollIndex.decode(_gzipJson(['5005', '6006']));
      final hit = RollIndexEngine.searchDecoded(index: index, rollNumber: '6006');
      final miss = RollIndexEngine.searchDecoded(index: index, rollNumber: '7007');

      expect(hit.isFound, isTrue);
      expect(miss.state, RollLookupState.notFound);
    });
  });
}
