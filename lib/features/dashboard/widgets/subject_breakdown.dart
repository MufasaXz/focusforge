import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/data/seed.dart';
import '../../../core/utils/format.dart';

/// Today's focus split across subjects, as a donut.
///
/// The ring itself is one spoken sentence — "Subject breakdown. Math 1 hour 5
/// minutes, Physics 52 minutes…" — so the chart is legible to a screen reader
/// without walking the legend item by item. The legend stays live underneath
/// that label, because it is the control surface as well as the key.
///
/// Two details are lifted from a budgeting app whose donut got them right.
/// Every slice is guaranteed a minimum sweep, so a subject that got two
/// minutes is still an arc rather than a hairline the stroke caps swallow; and
/// the selected slice lifts out of the ring, which is what makes a tap feel
/// like it landed on *that* slice rather than on the chart as a whole.
class SubjectBreakdown extends StatefulWidget {
  const SubjectBreakdown({super.key, required this.subjects});

  final List<Subject> subjects;

  @override
  State<SubjectBreakdown> createState() => _SubjectBreakdownState();
}

/// The smallest arc a slice may occupy, in radians. 15° is about what a ring
/// this size can show before the neighbouring gaps close over it.
const _minSweep = 15 * math.pi / 180;

/// The gap between neighbouring slices, so the ring reads as slices rather
/// than as one continuous stroke.
const _sliceGap = 2.2 * math.pi / 180;

/// How far the selected slice lifts out of the ring.
const _popDistance = 7.0;

const _ringSize = 168.0;

class _SubjectBreakdownState extends State<SubjectBreakdown>
    with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.deliberate,
  )..forward();

  /// Drives the lift-out. Separate from [_c] so selecting a slice does not
  /// replay the entrance — the ring has already drawn itself by then.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: Motion.base,
  );

  int? _selected;

  @override
  void dispose() {
    _c.dispose();
    _pop.dispose();
    super.dispose();
  }

  void _select(int? index) {
    if (index == _selected) {
      setState(() => _selected = null);
      _pop.reverse();
      return;
    }
    setState(() => _selected = index);
    _pop.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (widget.subjects.isEmpty) {
      return Row(
        children: [
          Icon(Icons.donut_large_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              'No subjects yet — add one from the Focus tab.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
    }

    final sweeps = donutSweeps([
      for (final s in widget.subjects) s.minutesToday.toDouble(),
    ]);

    return LayoutBuilder(
      builder: (context, constraints) {
        // A tablet has room to put the key beside the ring; a phone does not,
        // and a squeezed legend is worse than a stacked one.
        final wide = constraints.maxWidth > 380;

        final ring = _Ring(
          size: _ringSize,
          subjects: widget.subjects,
          sweeps: sweeps,
          selected: _selected,
          entrance: _c,
          pop: _pop,
          onTapAt: (local, size) => _hitTest(local, size, sweeps),
        );

        final legend = Wrap(
          spacing: Gap.lg,
          runSpacing: Gap.md,
          children: [
            for (var i = 0; i < widget.subjects.length; i++)
              _Legend(
                color: widget.subjects[i].color,
                icon: widget.subjects[i].icon,
                label: widget.subjects[i].name,
                value: formatMinutes(widget.subjects[i].minutesToday),
                selected: _selected == i,
                onTap: () => _select(i),
              ),
          ],
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: _summary(widget.subjects),
              child: ExcludeSemantics(
                child: wide
                    ? Row(
                        children: [
                          ring,
                          const SizedBox(width: Gap.xl),
                          Expanded(child: legend),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ring,
                          const SizedBox(height: Gap.xl),
                          legend,
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Which slice a tap landed on.
  ///
  /// The band is deliberately wider than the painted ring — a tap on the
  /// lifted slice would otherwise fall through to whatever is behind it.
  void _hitTest(Offset local, Size size, List<double> sweeps) {
    final centre = Offset(size.width / 2, size.height / 2);
    final v = local - centre;
    final geometry = _RingGeometry.of(size);

    if (v.distance < geometry.inner - 4 ||
        v.distance > geometry.outer + _popDistance + 4) {
      _select(null);
      return;
    }

    // Measured from 12 o'clock, clockwise, to match the painter.
    final angle =
        (math.atan2(v.dy, v.dx) + math.pi / 2 + 2 * math.pi) % (2 * math.pi);

    var acc = 0.0;
    for (var i = 0; i < sweeps.length; i++) {
      acc += sweeps[i];
      if (angle < acc) {
        _select(i);
        return;
      }
    }
  }
}

/// The ring and its centre readout.
class _Ring extends StatelessWidget {
  const _Ring({
    required this.size,
    required this.subjects,
    required this.sweeps,
    required this.selected,
    required this.entrance,
    required this.pop,
    required this.onTapAt,
  });

  final double size;
  final List<Subject> subjects;
  final List<double> sweeps;
  final int? selected;
  final Animation<double> entrance;
  final Animation<double> pop;
  final void Function(Offset local, Size size) onTapAt;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final subject = selected == null ? null : subjects[selected!];
    final total = subjects.fold<int>(0, (a, s) => a + s.minutesToday);

    return SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => onTapAt(d.localPosition, Size(size, size)),
        child: AnimatedBuilder(
          animation: Listenable.merge([entrance, pop]),
          builder: (context, _) => Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(size, size),
                painter: _DonutPainter(
                  colors: [for (final s in subjects) s.color],
                  sweeps: sweeps,
                  progress: entrance.value,
                  pop: Curves.easeOutCubic.transform(pop.value),
                  selected: selected ?? -1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 34),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      subject?.name ?? 'Today',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatMinutes(subject?.minutesToday ?? total),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: tt.titleMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ring's band, derived from the paint size.
///
/// Shared by the painter and the hit test so a tap can never disagree with
/// what was drawn — the two used to compute their own radii.
class _RingGeometry {
  const _RingGeometry({
    required this.centre,
    required this.radius,
    required this.stroke,
  });

  final Offset centre;
  final double radius;
  final double stroke;

  double get inner => radius - stroke / 2;
  double get outer => radius + stroke / 2;

  static _RingGeometry of(Size size) {
    final maxRadius = math.min(size.width, size.height) / 2;
    // Leave room for the lift-out so the popped slice cannot clip.
    final limit = maxRadius - _popDistance;
    final stroke = limit * 0.30;
    return _RingGeometry(
      centre: Offset(size.width / 2, size.height / 2),
      radius: limit - stroke / 2,
      stroke: stroke,
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.colors,
    required this.sweeps,
    required this.progress,
    required this.pop,
    required this.selected,
  });

  final List<Color> colors;
  final List<double> sweeps;

  /// The entrance, 0–1.
  final double progress;

  /// The lift-out of the selected slice, 0–1.
  final double pop;

  /// Index of the lifted slice, or -1.
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    final g = _RingGeometry.of(size);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = g.stroke
      ..strokeCap = StrokeCap.butt;

    var start = -math.pi / 2;
    for (var i = 0; i < sweeps.length; i++) {
      // The stagger is what makes the ring draw itself rather than appear.
      final t = ((progress - i * 0.08) / (1 - i * 0.08)).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(t);

      final full = sweeps[i];
      final gap = sweeps.length > 1 ? math.min(_sliceGap, full * 0.35) : 0.0;
      final sweep = (full - gap) * eased;

      if (sweep > 0.001) {
        final lift = i == selected ? _popDistance * pop : 0.0;
        paint.color = colors[i];
        canvas.drawArc(
          Rect.fromCircle(center: g.centre, radius: g.radius + lift),
          start + gap / 2 * eased,
          sweep,
          false,
          paint,
        );
      }
      start += full;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress ||
      old.pop != pop ||
      old.selected != selected ||
      !listEquals(old.sweeps, sweeps) ||
      !listEquals(old.colors, colors);
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $value',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: AnimatedContainer(
          duration: Motion.quick,
          curve: Motion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.sm,
            vertical: Gap.xs,
          ),
          decoration: BoxDecoration(
            color: selected
                ? cs.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 5),
              Text(
                value,
                style: tt.labelMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Turns today's minutes into sweeps that sum to a full turn, with every slice
/// given at least [_minSweep].
///
/// The naive `value / total * 2π` hands a two-minute subject a hairline. Here
/// the small slices take the floor first and the large ones share out what is
/// left in proportion to their raw size — so the ordering never changes, only
/// the very small end is lifted into view.
///
/// Public because it is the whole of the chart's arithmetic and the painter is
/// not: a test can pin the distribution without rendering a canvas.
List<double> donutSweeps(List<double> values) {
  const full = 2 * math.pi;
  if (values.isEmpty) return const [];

  final total = values.fold<double>(0, (a, b) => a + b);
  if (total <= 0) {
    return List<double>.filled(values.length, full / values.length);
  }

  final raw = [for (final v in values) v / total * full];
  final small = [for (final s in raw) s < _minSweep];
  final floorTotal = small.where((s) => s).length * _minSweep;

  // More slices than the floor allows. Six subjects is the catalogue, so this
  // is unreachable today — but an equal split is a better failure than arcs
  // that wrap past a full turn.
  if (floorTotal >= full) {
    return List<double>.filled(values.length, full / values.length);
  }

  final bigTotal = [
    for (var i = 0; i < raw.length; i++)
      if (!small[i]) raw[i],
  ].fold<double>(0, (a, b) => a + b);

  final remaining = full - floorTotal;
  return [
    for (var i = 0; i < raw.length; i++)
      if (small[i])
        _minSweep
      else if (bigTotal <= 0)
        remaining / raw.length
      else
        raw[i] / bigTotal * remaining,
  ];
}

String _spokenMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final parts = <String>[
    if (h > 0) '$h ${h == 1 ? 'hour' : 'hours'}',
    if (m > 0) '$m ${m == 1 ? 'minute' : 'minutes'}',
  ];
  return parts.isEmpty ? 'no time' : parts.join(' ');
}

String _summary(List<Subject> subjects) {
  final parts = [
    for (final s in subjects) '${s.name} ${_spokenMinutes(s.minutesToday)}',
  ];
  return 'Subject breakdown. ${parts.join(', ')}.';
}
