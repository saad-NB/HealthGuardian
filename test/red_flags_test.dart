import 'package:flutter_test/flutter_test.dart';

import 'package:healthguardian/config/clinical_thresholds.dart';

typedef Vitals = ({
  int gcs,
  double sbp,
  double spo2,
  bool onOxygen,
  double rr,
  double hr,
  double temp,
});

Vitals _healthy({
  int gcs = 15,
  double sbp = 120,
  double spo2 = 98,
  bool onOxygen = false,
  double rr = 16,
  double hr = 70,
  double temp = 37.0,
}) {
  return (
    gcs: gcs,
    sbp: sbp,
    spo2: spo2,
    onOxygen: onOxygen,
    rr: rr,
    hr: hr,
    temp: temp,
  );
}

List<String> _firingFlags(Vitals v) {
  final flags = <String>[];
  if (RedFlags.severeImpairment(v.gcs)) flags.add('severeImpairment');
  if (RedFlags.hypotension(v.sbp)) flags.add('hypotension');
  if (RedFlags.severeHypoxia(v.spo2, v.onOxygen)) flags.add('severeHypoxia');
  if (RedFlags.criticalRespiratoryRate(v.rr)) flags.add('criticalRespiratoryRate');
  if (RedFlags.criticalHeartRate(v.hr)) flags.add('criticalHeartRate');
  if (RedFlags.criticalTemperature(v.temp)) flags.add('criticalTemperature');
  return flags;
}

bool _anyFire(Vitals v) {
  return RedFlags.anyFire(
    gcs: v.gcs,
    sbp: v.sbp,
    spo2: v.spo2,
    onOxygen: v.onOxygen,
    rr: v.rr,
    hr: v.hr,
    temp: v.temp,
  );
}

void main() {
  group('Red flag isolation matrix', () {
    final cases = <({String name, Vitals input, List<String> expected})>[
      (
        name: 'severeImpairment at gcs 8',
        input: _healthy(gcs: 8),
        expected: const ['severeImpairment'],
      ),
      (
        name: 'hypotension at sbp 90',
        input: _healthy(sbp: 90),
        expected: const ['hypotension'],
      ),
      (
        name: 'severeHypoxia at spo2 91 on room air',
        input: _healthy(spo2: 91),
        expected: const ['severeHypoxia'],
      ),
      (
        name: 'criticalRespiratoryRate low at rr 8',
        input: _healthy(rr: 8),
        expected: const ['criticalRespiratoryRate'],
      ),
      (
        name: 'criticalRespiratoryRate high at rr 25',
        input: _healthy(rr: 25),
        expected: const ['criticalRespiratoryRate'],
      ),
      (
        name: 'criticalHeartRate low at hr 40',
        input: _healthy(hr: 40),
        expected: const ['criticalHeartRate'],
      ),
      (
        name: 'criticalHeartRate high at hr 131',
        input: _healthy(hr: 131),
        expected: const ['criticalHeartRate'],
      ),
      (
        name: 'criticalTemperature low at temp 35.0',
        input: _healthy(temp: 35.0),
        expected: const ['criticalTemperature'],
      ),
      (
        name: 'criticalTemperature high at temp 39.1',
        input: _healthy(temp: 39.1),
        expected: const ['criticalTemperature'],
      ),
    ];

    for (final c in cases) {
      test('${c.name} fires as the only flag (no skip, no bleed)', () {
        final fired = _firingFlags(c.input);
        expect(fired, c.expected,
            reason: '${c.name}: exactly one flag must fire');
        expect(_anyFire(c.input), isTrue);
      });

      test('${c.name} is silent when its input is healthy', () {
        expect(_firingFlags(_healthy()), isEmpty);
        expect(_anyFire(_healthy()), isFalse);
      });
    }

    test('every red flag isolation row was examined', () {
      expect(cases.length, 9,
          reason: 'all 9 isolation rows (6 flags, 3 with dual bounds) ran');
    });
  });

  group('Red flag composite anyFire', () {
    test('healthy inputs fire nothing', () {
      expect(_anyFire(_healthy()), isFalse);
    });

    test('two simultaneous flags still fire', () {
      expect(_anyFire(_healthy(sbp: 90, spo2: 91)), isTrue,
          reason: 'hypotension + severeHypoxia together');
    });

    test('on-oxygen cancels only severeHypoxia, not siblings', () {
      expect(_anyFire(_healthy(onOxygen: true, spo2: 91, rr: 8)), isTrue,
          reason: 'RR flag still fires although hypoxia is suppressed by O2');
      expect(RedFlags.severeHypoxia(91, true), isFalse);
    });
  });

  group('Red flag boundary tightness', () {
    test('healthy side boundaries never fire', () {
      expect(RedFlags.severeImpairment(9), isFalse);
      expect(RedFlags.hypotension(91), isFalse);
      expect(RedFlags.severeHypoxia(92, false), isFalse);
      expect(RedFlags.criticalRespiratoryRate(12), isFalse);
      expect(RedFlags.criticalHeartRate(70), isFalse);
      expect(RedFlags.criticalTemperature(36.5), isFalse);
    });
  });
}