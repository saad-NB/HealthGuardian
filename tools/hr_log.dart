// HR calibration log tool (supervised).
//
// The app emits one JSON diagnostic line per measuring second under the
// `HG_HR` tag (see HeartRateService._logEntry -> debugPrint -> logcat). This
// script collects those lines, then — with you labeling each reading as
// CLEAN (verified against a pulse oximeter) or NOISY (deliberately bad:
// movement, partial coverage) — computes the factor distributions for each
// group and finds the medium/high threshold that best separates them. That is
// the recalibration input for PpgConfig (§9.3 / DECISIONS).
//
// Usage:
//   dart run tools/hr_log.dart collect --label   clear logcat, you measure
//                                                clean readings then noisy
//                                                ones, hit Enter, then label
//   dart run tools/hr_log.dart analyze <file> --label
//   ... [--csv out.csv]
//
// Suggested measurement protocol (already piloted on the target device):
//   1) 2-4 clean readings: fingertip fully covering lens+flash, still, ~30 s
//      each; note the oximeter bpm per reading.
//   2) 2-3 noisy readings: deliberately jitter the finger, slide/press
//      unevenly, or cover only part of the lens, ~20-30 s each.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const kTag = 'HG_HR';
const kMedium = 0.50;
const kHigh = 0.75;
const kFallbackReg = 0.7;
const kDriftMax = 4.0;

Future<void> main(List<String> args) async {
  final csv = _flagArgs(args, '--csv');
  final labeled = args.contains('--label') || args.contains('-l');
  switch (args.firstOrNull) {
    case 'collect':
      await collect(csv: csv, labeled: labeled);
      break;
    case 'analyze':
      final pos = args.indexOf('--csv');
      if (pos == 1) {
        final file = args.length > 2 ? args[2] : null;
        if (file == null) return usage();
        analyzeAll(await File(file).readAsString(),
            csv: csv, labeled: labeled);
      } else if (args.length > 1) {
        analyzeAll(await File(args[1]).readAsString(),
            csv: csv, labeled: labeled);
      } else {
        return usage();
      }
      break;
    default:
      usage();
  }
}

String? _flagArgs(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

void usage() {
  stdout.writeln('''HR log analyzer (supervised)
 usage:
   dart run tools/hr_log.dart collect [--label] [--csv out.csv]
   dart run tools/hr_log.dart analyze <logcat_file> [--label] [--csv out.csv]
 Iteractive: label each measured session "clean <oximeter_bpm>" or "noisy"
 (or "skip"); the tool then finds the quality threshold that best separates
 clean from noisy and reports factor distributions vs medium=$kMedium /
 high=$kHigh.''');
}

String _fmt(double? v) =>
    v == null ? '——' : v.toStringAsFixed(2).padLeft(6);

double? _numOf(Map<String, Object?> e, String k) {
  final v = e[k];
  return v is num ? v.toDouble() : null;
}

Future<void> collect({String? csv, bool labeled = false}) async {
  stdout.writeln('Clearing device logcat...');
  final clear = await Process.run('adb', ['logcat', '-c']);
  if (clear.exitCode != 0) {
    stderr.writeln('adb logcat -c failed: ${clear.stderr}');
    exitCode = 1;
    return;
  }
  stdout.writeln('Clear. Protocol: first 2-4 CLEAN readings (verified vs the '
      'pulse oximeter),\nthen 2-3 deliberately NOISY ones (movement, partial '
      'coverage).');
  stdout.writeln('Press Enter here when all readings are done.');
  stdin.readLineSync();

  stdout.writeln('Pulling logcat dump...');
  final pull = await Process.run('adb', ['logcat', '-d']);
  if (pull.exitCode != 0) {
    stderr.writeln('adb logcat -d failed: ${pull.stderr}');
    exitCode = 1;
    return;
  }
  analyzeAll('${pull.stdout}', csv: csv, labeled: labeled);
}

/// One parsed session: its progress/final HG_HR events.
class _Session {
  _Session(this.events);
  final List<Map<String, Object?>> events;

  List<Map<String, Object?>> get progress =>
      events.where((e) => e['type'] == 'p').toList();
  Map<String, Object?>? get final_ =>
      events.where((e) => e['type'] == 'f').toList().lastOrNull;
  String get outcome => (final_?['outcome'] ?? 'incomplete').toString();
  Object? get bpm => final_?['bpm'];
  String get conf => (final_?['conf'] ?? '—').toString();

  /// Means of each factor over this session's progress lines.
  ({double? q, double? reg, double? corr, double? amp, double? drift}) means() {
    final p = progress;
    if (p.isEmpty) return (q: null, reg: null, corr: null, amp: null, drift: null);
    double sq = 0, sr = 0, sc = 0, sa = 0, sd = 0;
    var nd = 0;
    for (final e in p) {
      final q = _numOf(e, 'q');
      if (q != null) sq += q;
      final r = _numOf(e, 'reg');
      if (r != null) sr += r;
      final c = _numOf(e, 'corr');
      if (c != null) sc += c;
      final a = _numOf(e, 'amp');
      if (a != null) sa += a;
      final dd = _numOf(e, 'drift');
      if (dd != null) {
        sd += dd;
        nd++;
      }
    }
    final n = p.length;
    return (
      q: n > 0 ? sq / n : null,
      reg: sr / n,
      corr: sc / n,
      amp: sa / n,
      drift: nd > 0 ? sd / nd : null,
    );
  }

  /// Best quality the session ever displayed (proxy for "would it pass a
  /// threshold" — acceptance also needs an estimate, reported separately).
  double? maxQ() {
    var best = 0.0;
    var found = false;
    for (final e in progress) {
      final q = _numOf(e, 'q');
      if (q != null) {
        best = math.max(best, q);
        found = true;
      }
    }
    best = math.max(best, _numOf(final_!, 'q') ?? 0);
    return found ? best : null;
  }

  String get tag =>
      'outcome=$outcome${conf == '—' ? '' : ' [$conf]'} bpm=${bpm ?? '—'}';
}

void analyzeAll(String log, {String? csv, bool labeled = false}) {
  final sessions = <_Session>[];
  List<Map<String, Object?>>? cur;
  var parsed = 0;

  final re = RegExp('$kTag\\s*(\\{.*\\})');
  for (final line in log.split('\n')) {
    final m = re.firstMatch(line);
    if (m == null) continue;
    Map<String, Object?>? e;
    try {
      e = (jsonDecode(m.group(1)!) as Map).cast<String, Object?>();
    } catch (_) {
      continue;
    }
    parsed++;
    if (e['type'] == 'p') {
      (cur ??= []).add(e);
    } else if (e['type'] == 'f' && e['outcome'] is String) {
      cur ??= [];
      cur.add(e);
      sessions.add(_Session(cur));
      cur = null;
    }
  }
  if (cur != null) sessions.add(_Session(cur));

  stdout.writeln('Parsed $parsed $kTag lines -> ${sessions.length} session(s).');
  if (sessions.isEmpty) {
    stdout.writeln('(nothing found; did you measure after clearing logcat?)');
    return;
  }

  var i = 0;
  var totalQ = 0.0;
  var qCount = 0;
  final csvLines = <List<String>>[];
  for (final s in sessions) {
    i++;
    final m = s.means();
    final qLoHi = _range(s.progress);
    stdout.writeln('--- session $i ${s.tag} ${s.outcome == 'insufficient' &&
            (m.q ?? 0) >= kMedium && (m.reg ?? 0) >= kFallbackReg
        ? ' <<< GATE ANOMALY: medium score but insufficient'
        : ''}');
    stdout.writeln('    secs=${s.progress.length} '
        'q=μ${_fmt(m.q)} [${qLoHi.$1 == null ? '—' : qLoHi.$1!.toStringAsFixed(2)}..'
        '${qLoHi.$2 == null ? '—' : qLoHi.$2!.toStringAsFixed(2)}] '
        'reg=μ${_fmt(m.reg)} corr=μ${_fmt(m.corr)} amp=μ${_fmt(m.amp)} '
        'drift=μ${_fmt(m.drift)}');
    if (m.q != null) {
      totalQ += m.q!;
      qCount++;
    }
    if (csv != null) {
      for (final e in s.progress) {
        csvLines.add([
          '$i',
          s.outcome,
          for (final k in ['sec', 'bpm', 'reg', 'corr', 'amp', 'drift', 'q', 'usable'])
            '${e[k] ?? ''}',
        ]);
      }
    }
  }

  stdout.writeln();
  if (qCount > 0) {
    stdout.writeln(
        'Overall mean quality ${(totalQ / qCount).toStringAsFixed(2)} across '
        '$qCount session(s).');
  }

  if (labeled) _supervisedReport(sessions);

  if (csv != null) {
    final rows = csvLines.map((r) => r.join(',')).join('\n');
    File(csv)
        .writeAsStringSync('session,outcome,sec,bpm,reg,corr,amp,drift,q,usable\n$rows');
    stdout.writeln('Wrote $csv');
  }
}

(double?, double?) _range(List<Map<String, Object?>> events) {
  final qs = events
      .map((e) => _numOf(e, 'q'))
      .whereType<double>()
      .toList()
    ..sort();
  final fe = events.lastOrNull;
  final fin = _numOf(fe ?? const {}, 'q');
  if (fe != null && fin != null && !qs.contains(fin)) qs.add(fin);
  if (qs.isEmpty) return (null, null);
  return (qs.first, qs.last);
}

class _Labelled {
  _Labelled(this.session, {this.ref});
  final _Session session;
  final double? ref;
  bool get clean => ref != null;

  double? get q => session.means().q;
  double? get reg => session.means().reg;
  double? get corr => session.means().corr;
  double? get amp => session.means().amp;
  double? get drift => session.means().drift;
  double? get maxQ => session.maxQ();
}

void _supervisedReport(List<_Session> sessions) {
  stdout.writeln();
  stdout.writeln('Labeling pass: for each session type '
      '"clean <oximeter_bpm>" or "noisy" (blank = skip).');
  final labels = <_Labelled>[];
  var i = 0;
  for (final s in sessions) {
    i++;
    stdout.write('  session $i [${s.tag}]: ');
    final input = stdin.readLineSync()?.trim() ?? '';
    if (input.isEmpty) continue;
    final parts = input.split(RegExp(r'\s+'));
    final kind = parts.first.toLowerCase();
    if (kind == 'clean' || kind == 'c' || kind == 'ok' || kind == 'o') {
      labels.add(_Labelled(s, ref: parts.length > 1 ? double.tryParse(parts[1]) : null));
    } else if (kind == 'noisy' || kind == 'n' || kind == 'x' || kind == 'bad') {
      labels.add(_Labelled(s));
    }
  }

  if (labels.isEmpty) {
    stdout.writeln('No labels given; skipping discrimination report.');
    return;
  }

  final clean = labels.where((l) => l.clean).toList();
  final noisy = labels.where((l) => !l.clean).toList();
  stdout.writeln();

  double? meanQ(List<_Labelled> g) {
    final qs = g.map((l) => l.q).whereType<double>().toList();
    return qs.isEmpty ? null : qs.reduce((a, b) => a + b) / qs.length;
  }

  for (bool group in [true, false]) {
    final g = group ? clean : noisy;
    final name = group ? 'CLEAN' : 'NOISY';
    if (g.isEmpty) {
      stdout.writeln('-- $name: none labeled');
      continue;
    }
    double? err;
    if (group) {
      final errs = g
          .map((l) {
            final b = l.session.bpm;
            if (b is num && l.ref != null) return (b.toDouble() - l.ref!).abs();
            return null;
          })
          .whereType<double>()
          .toList();
      err = errs.isEmpty ? null : errs.reduce((a, b) => a + b) / errs.length;
    }
    stdout.writeln('-- $name n=${g.length}'
        '${group && err != null ? ' mean|err|=${err.toStringAsFixed(1)} bpm' : ''}');
    stdout.writeln('    q    μ=${_fmt(meanQ(g))} ${_rangeOf(g, (l) => l.q)} '
        'max=${_fmt(_gmax(g, (l) => l.maxQ))}');
    stdout.writeln('    reg  μ=${_fmt(_gmean(g, (l) => l.reg))} '
        '${_rangeOf(g, (l) => l.reg)}');
    stdout.writeln('    corr μ=${_fmt(_gmean(g, (l) => l.corr))} '
        '${_rangeOf(g, (l) => l.corr)}');
    stdout.writeln('    amp  μ=${_fmt(_gmean(g, (l) => l.amp))} '
        '${_rangeOf(g, (l) => l.amp)}');
    stdout.writeln('    drift μ=${_fmt(_gmean(g, (l) => l.drift))} '
        '${_rangeOf(g, (l) => l.drift)}');
    final acc = g.where((l) => l.session.outcome == 'ok').length;
    stdout.writeln('    accepted as reading: $acc/${g.length}');
  }

  // Find the quality threshold that best separates clean (want >= t) from
  // noisy (want < t), searched over mean-q with max-q as a secondary view.
  for (final useMax in [false, true]) {
    final name = useMax ? 'max q' : 'mean q';
    double? score(_Labelled l) => useMax ? l.maxQ : l.q;
    final cleanQs = clean.map(score).whereType<double>().toList();
    final noisyQs = noisy.map(score).whereType<double>().toList();
    if (cleanQs.isEmpty || noisyQs.isEmpty) continue;

    double? bestT;
    var bestErr = 1 << 30;
    for (var t = 0.40; t <= 0.80 + 1e-6; t += 0.01) {
      var wrong = 0;
      for (final q in cleanQs) {
        if (q < t) wrong++;
      }
      for (final q in noisyQs) {
        if (q >= t) wrong++;
      }
      if (wrong < bestErr) {
        bestErr = wrong;
        bestT = t;
      }
    }
    final decisive = cleanQs.reduce(math.min) > noisyQs.reduce(math.max)
        ? 'clean never overlaps noisy'
        : 'ranges overlap';
    stdout.writeln(
        'discriminator ($name): best t=${bestT?.toStringAsFixed(2)} '
        '(misclassifies $bestErr/${cleanQs.length + noisyQs.length}) '
        '— $decisive');
  }

  // FPs/FNs at the CURRENT medium threshold, using per-reading mean q.
  var fp = 0, fn = 0;
  for (final l in noisy) {
    if ((l.maxQ ?? 0) >= kMedium) fp++;
  }
  for (final l in clean) {
    if (l.q == null || l.q! < kMedium) fn++;
  }
  stdout.writeln();
  stdout.writeln('current medium=$kMedium: NOISY false-positives '
      '(max q >= medium): $fp/${noisy.length}; '
      'CLEAN false-negatives (mean q < medium): $fn/${clean.length}.');

  final gap = _sepGap(clean, noisy);
  if (gap != null) {
    stdout.writeln(
        'rebalance suggestion for qualityMedium: ${gap.toStringAsFixed(2)} '
        '(midpoint of the clean/noisy gap). Requires a DECISIONS entry after '
        '2+ device confirmations.');
  }
}

double? _gmean(List<_Labelled> g, double? Function(_Labelled) f) {
  final vs = g.map(f).whereType<double>().toList();
  return vs.isEmpty ? null : vs.reduce((a, b) => a + b) / vs.length;
}

double? _gmax(List<_Labelled> g, double? Function(_Labelled) f) {
  final vs = g.map(f).whereType<double>().toList();
  return vs.isEmpty ? null : vs.reduce(math.max);
}

String _rangeOf(List<_Labelled> g, double? Function(_Labelled) f) {
  final vs = g.map(f).whereType<double>().toList();
  if (vs.isEmpty) return '(—)';
  vs.sort();
  return '[${vs.first.toStringAsFixed(2)}..${vs.last.toStringAsFixed(2)}]';
}

/// Midpoint of the largest clean/lowest-noisy-mean gap, or null if they
/// overlap so a plain threshold cannot separate.
double? _sepGap(List<_Labelled> clean, List<_Labelled> noisy) {
  if (clean.isEmpty || noisy.isEmpty) return null;
  final cMin = clean.map((l) => l.q).whereType<double>().reduce(math.min);
  final nMax = noisy.map((l) => l.q).whereType<double>().reduce(math.max);
  if (cMin <= nMax) return null;
  return ((cMin + nMax) / 2).clamp(0.35, 0.95);
}

// tiny helpers (firstOrNull / lastOrNull for this Dart version)
extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}