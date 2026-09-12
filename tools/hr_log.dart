// HR/RR calibration log tool (supervised).
//
// The app emits one JSON diagnostic line per measuring second under the
// `HG_HR` (HeartRateService) / `HG_RR` (BreathingRateService) tags via
// debugPrint -> logcat. This script collects those lines, then — with you
// labeling each reading as CLEAN (verified against a reference: oximeter for
// HR, manual breath count for RR) or NOISY (deliberately bad) — computes the
// factor distributions for each group and finds the medium/high threshold
// that best separates them. That is the recalibration input for the config
// structs (§9.3 / DECISIONS).
//
// Usage:
//   dart run tools/hr_log.dart collect --label          // HR (default tag)
//   dart run tools/hr_log.dart collect --label --tag HG_RR
//   ... same; RR sessions are 45 s, HR are 30 s
//   dart run tools/hr_log.dart analyze <file> --label [--tag HG_RR] [--csv out.csv]
//
// Suggested measurement protocol (already piloted on the target device):
//   HR: 2-4 clean readings (finger covering lens+flash, still, ~30 s each;
//       note the oximeter bpm) then 2-3 noisy (jitter/partial coverage).
//   RR: 2-4 clean readings (quiet room, phone near the mouth/nose, ~45 s;
//       count breaths for a 15 s slice x4 as the reference cpm) then 2-3 noisy
//       (talk over it, breathe weakly/far, fan or AC noise).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const kTag = 'HG_HR';
const kMedium = 0.50;
const kHigh = 0.75;
const kFallbackReg = 0.7;
const kDriftMax = 4.0;

/// Per-vital parsing profile: which metric key, the quality-medium constant to
/// compare against, and whether the factor set includes BPM drift.
class VitalSpec {
  const VitalSpec(this.tag, this.metric, this.medium, this.hasDrift);
  final String tag;
  final String metric;
  final double medium;
  final bool hasDrift;
}

const _specs = <String, VitalSpec>{
  'HG_HR': VitalSpec('HG_HR', 'bpm', 0.50, true),
  'HG_RR': VitalSpec('HG_RR', 'cpm', 0.55, false),
};

VitalSpec _specOf(List<String> args) {
  final i = args.indexOf('--tag');
  if (i >= 0 && i + 1 < args.length) {
    return _specs[args[i + 1].toUpperCase()] ?? _specs[kTag]!;
  }
  return _specs[kTag]!;
}

Future<void> main(List<String> args) async {
  final spec = _specOf(args);
  final csv = _flagArgs(args, '--csv');
  final labeled = args.contains('--label') || args.contains('-l');
  switch (args.firstOrNull) {
    case 'collect':
      await collect(spec, csv: csv, labeled: labeled);
      break;
    case 'analyze':
      final pos = args.indexOf('--csv');
      if (pos == 1) {
        final file = args.length > 2 ? args[2] : null;
        if (file == null) return usage();
        analyzeAll(await File(file).readAsString(),
            spec: spec, csv: csv, labeled: labeled);
      } else if (args.length > 1) {
        analyzeAll(await File(args[1]).readAsString(),
            spec: spec, csv: csv, labeled: labeled);
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
  stdout.writeln('''HR/RR log analyzer (supervised)
 usage:
   dart run tools/hr_log.dart collect [--label] [--tag HG_HR|HG_RR] [--csv out.csv]
   dart run tools/hr_log.dart analyze <logcat_file> [--label] [--tag HG_HR|HG_RR]
                                        [--csv out.csv]
 Interactive: label each measured session "clean <reference>" or "noisy"
 (or "skip"); the tool then finds the quality threshold that best separates
 clean from noisy and reports factor distributions vs the medium constant
 (HR bpm 0.50 / RR cpm 0.55).''');
}

String _fmt(double? v) =>
    v == null ? '——' : v.toStringAsFixed(2).padLeft(6);

double? _numOf(Map<String, Object?> e, String k) {
  final v = e[k];
  return v is num ? v.toDouble() : null;
}

Future<void> collect(VitalSpec spec,
    {String? csv, bool labeled = false}) async {
  stdout.writeln('Clearing device logcat...');
  final clear = await Process.run('adb', ['logcat', '-c']);
  if (clear.exitCode != 0) {
    stderr.writeln('adb logcat -c failed: ${clear.stderr}');
    exitCode = 1;
    return;
  }
  stdout.writeln('Clear. ${spec.tag} protocol: first 2-4 CLEAN readings '
      '(verified as described in the tool header),\nthen 2-3 deliberately '
      'NOISY ones.');
  stdout.writeln('Press Enter here when all readings are done.');
  stdin.readLineSync();

  stdout.writeln('Pulling logcat dump...');
  final pull = await Process.run('adb', ['logcat', '-d']);
  if (pull.exitCode != 0) {
    stderr.writeln('adb logcat -d failed: ${pull.stderr}');
    exitCode = 1;
    return;
  }
  analyzeAll('${pull.stdout}', spec: spec, csv: csv, labeled: labeled);
}

/// One parsed session: its progress/final events.
class _Session {
  _Session(this.events, this.metric);
  final List<Map<String, Object?>> events;
  final String metric;

  List<Map<String, Object?>> get progress =>
      events.where((e) => e['type'] == 'p').toList();
  Map<String, Object?>? get final_ =>
      events.where((e) => e['type'] == 'f').toList().lastOrNull;
  String get outcome => (final_?['outcome'] ?? 'incomplete').toString();
  Object? get value => final_?[metric];
  String get conf => (final_?['conf'] ?? '—').toString();
  Object? get reason => final_?['reason'];

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
      'outcome=$outcome${conf == '—' ? '' : ' [$conf]'} $metric=${value ?? '—'}';
}

void analyzeAll(String log,
    {required VitalSpec spec, String? csv, bool labeled = false}) {
  final sessions = <_Session>[];
  List<Map<String, Object?>>? cur;
  var parsed = 0;

  final re = RegExp('${spec.tag}\\s*(\\{.*\\})');
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
      sessions.add(_Session(cur, spec.metric));
      cur = null;
    }
  }
  if (cur != null) sessions.add(_Session(cur, spec.metric));

  stdout.writeln('Parsed $parsed ${spec.tag} lines -> ${sessions.length} '
      'session(s).');
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
    final reason =
        s.reason is String ? ' reason=${s.reason}' : '';
    stdout.writeln('--- session $i ${s.tag} '
        '${s.outcome == 'insufficient' &&
                (m.q ?? 0) >= spec.medium && (m.reg ?? 0) >= kFallbackReg
            ? '<<< GATE ANOMALY: medium score but insufficient'
            : ''}$reason');
    stdout.writeln('    secs=${s.progress.length} '
        'q=Î¼${_fmt(m.q)} [${qLoHi.$1 == null ? '—' : qLoHi.$1!.toStringAsFixed(2)}..'
        '${qLoHi.$2 == null ? '—' : qLoHi.$2!.toStringAsFixed(2)}] '
        'reg=Î¼${_fmt(m.reg)} corr=Î¼${_fmt(m.corr)} amp=Î¼${_fmt(m.amp)} '
        '${spec.hasDrift ? 'drift=Î¼${_fmt(m.drift)}' : ''}');
    if (!spec.hasDrift) {
      final fe = s.final_ ?? s.progress.lastOrNull;
      if (fe != null) {
        stdout.writeln('    gates noisy=${fe['noisy'] == true} '
            'sub=${fe['sub'] == true} envSub=${fe['env_sub'] == true} '
            'breath=${fe['breath'] == true} ibis=${fe['ibis'] ?? '—'} '
            'lag=${fe['lag'] ?? '—'}');
      }
      final last = s.progress.lastOrNull;
      if (last != null) {
        stdout.writeln('    levels raw=${last['raw'] ?? '—'} '
            'band=${last['band'] ?? '—'} peak=${last['peak'] ?? '—'} '
            'peaks=${last['peaks'] ?? '—'}');
      }
    }
    if (m.q != null) {
      totalQ += m.q!;
      qCount++;
    }
    if (csv != null) {
      final cols = <String>[
        'sec',
        spec.metric,
        'reg',
        'corr',
        'amp',
        if (spec.hasDrift) 'drift',
        'q',
        'usable',
        if (!spec.hasDrift) 'ibis',
        if (!spec.hasDrift) 'lag',
        if (!spec.hasDrift) 'peaks',
        if (!spec.hasDrift) 'raw',
        if (!spec.hasDrift) 'band',
        if (!spec.hasDrift) 'peak',
        if (!spec.hasDrift) 'breath',
        if (!spec.hasDrift) 'noisy',
        if (!spec.hasDrift) 'sub',
        if (!spec.hasDrift) 'env_sub',
      ];
      for (final e in s.progress) {
        csvLines.add([
          '$i',
          s.outcome,
          for (final k in cols) '${e[k] ?? ''}',
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

  if (labeled) _supervisedReport(sessions, spec);

  if (csv != null) {
    final header = <String>[
      'session',
      'outcome',
      'sec',
      spec.metric,
      'reg',
      'corr',
      'amp',
      if (spec.hasDrift) 'drift',
      'q',
      'usable',
      if (!spec.hasDrift) 'ibis',
      if (!spec.hasDrift) 'lag',
      if (!spec.hasDrift) 'peaks',
      if (!spec.hasDrift) 'raw',
      if (!spec.hasDrift) 'band',
      if (!spec.hasDrift) 'peak',
      if (!spec.hasDrift) 'breath',
      if (!spec.hasDrift) 'noisy',
      if (!spec.hasDrift) 'sub',
      if (!spec.hasDrift) 'env_sub',
    ];
    File(csv).writeAsStringSync(
        '${header.join(',')}\n${csvLines.map((r) => r.join(',')).join('\n')}');
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

void _supervisedReport(List<_Session> sessions, VitalSpec spec) {
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
            final b = l.session.value;
            if (b is num && l.ref != null) return (b.toDouble() - l.ref!).abs();
            return null;
          })
          .whereType<double>()
          .toList();
      err = errs.isEmpty ? null : errs.reduce((a, b) => a + b) / errs.length;
    }
stdout.writeln('-- $name n=${g.length}'
      '${group && err != null ? ' mean|err|=${err.toStringAsFixed(1)} ${spec.metric}' : ''}');
    stdout.writeln('    q    Î¼=${_fmt(meanQ(g))} ${_rangeOf(g, (l) => l.q)} '
        'max=${_fmt(_gmax(g, (l) => l.maxQ))}');
    stdout.writeln('    reg  Î¼=${_fmt(_gmean(g, (l) => l.reg))} '
        '${_rangeOf(g, (l) => l.reg)}');
    stdout.writeln('    corr Î¼=${_fmt(_gmean(g, (l) => l.corr))} '
        '${_rangeOf(g, (l) => l.corr)}');
    stdout.writeln('    amp  Î¼=${_fmt(_gmean(g, (l) => l.amp))} '
        '${_rangeOf(g, (l) => l.amp)}');
    stdout.writeln('    drift Î¼=${_fmt(_gmean(g, (l) => l.drift))} '
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
    if ((l.maxQ ?? 0) >= spec.medium) fp++;
  }
  for (final l in clean) {
    if (l.q == null || l.q! < spec.medium) fn++;
  }
  stdout.writeln();
  stdout.writeln('current medium=${spec.medium.toStringAsFixed(2)}: NOISY '
      'false-positives (max q >= medium): $fp/${noisy.length}; '
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
