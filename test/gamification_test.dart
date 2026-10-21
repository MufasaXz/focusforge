import 'package:flutter_test/flutter_test.dart';
import 'package:focusforge/core/models/user.dart';

void main() {
  test('all 49 level boundaries consume exactly their required minutes', () {
    var previousCost = 0;
    for (var level = 1; level < GamificationStats.maxLevel; level++) {
      final stats = GamificationStats(level: level);
      final cost = stats.xpForNext;
      expect(cost, greaterThan(previousCost));
      expect(stats.withXp(cost - 1).level, level);
      final leveled = stats.withXp(cost);
      expect(leveled.level, level + 1);
      expect(leveled.xp, 0);
      previousCost = cost;
    }
    expect(const GamificationStats(level: 1).xpForNext, 25);
    expect(const GamificationStats(level: 5).xpForNext, 85);
    expect(const GamificationStats(level: 6).xpForNext, 120);
    expect(const GamificationStats(level: 10).xpForNext, 240);
    expect(const GamificationStats(level: 11).xpForNext, 300);
  });

  test('large awards stop at level 50 and retain all overflow XP', () {
    final total = [
      for (var level = 1; level < GamificationStats.maxLevel; level++)
        GamificationStats(level: level).xpForNext,
    ].fold(0, (sum, cost) => sum + cost);
    final max = const GamificationStats().withXp(total + 37);
    expect(max.level, 50);
    expect(max.xp, 37);
    expect(max.levelProgress, 1);
    expect(max.withXp(100).xp, 137);
    expect(max.withXp(100).level, 50);
  });

  test('saved progress, receipts and totals survive the new level curve', () {
    const old = GamificationStats(
      level: 7,
      xp: 2490,
      totalFocusHours: 123.5,
      totalSessions: 321,
      badges: ['first-focus'],
      creditedSessionIds: ['receipt'],
    );
    final restored = GamificationStats.fromJson(old.toJson());
    expect(restored.level, greaterThanOrEqualTo(old.level));
    var consumed = 0;
    for (var level = old.level; level < restored.level; level++) {
      consumed += GamificationStats(level: level).xpForNext;
    }
    expect(consumed + restored.xp, old.xp);
    expect(restored.totalFocusHours, old.totalFocusHours);
    expect(restored.totalSessions, old.totalSessions);
    expect(restored.badges, old.badges);
    expect(restored.creditedSessionIds, old.creditedSessionIds);
    expect(
      GamificationStats.fromJson(restored.toJson()).toJson(),
      restored.toJson(),
    );
  });

  test('legacy levels above 50 cap without deleting their saved XP', () {
    final restored = GamificationStats.fromJson({'level': 61, 'xp': 456});
    expect(restored.level, 50);
    expect(restored.xp, 456);
    expect(restored.isMaxLevel, isTrue);
  });
}
