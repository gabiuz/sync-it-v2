import 'package:flutter_test/flutter_test.dart';
import 'package:gpx_lab/core/core_engine.dart';

Activity _activityWithRange(String title, DateTime start, DateTime end) {
  final points = start == end
      ? [Trackpoint(timestamp: start)]
      : [Trackpoint(timestamp: start), Trackpoint(timestamp: end)];
  return Activity(
    title: title,
    description: '',
    sportType: SportType.running,
    trackpoints: points,
    laps: [Lap(startTime: start, endTime: end)],
    availableChannels: const {},
  );
}

void main() {
  group('CoreEngine Multi-File Mode Suggestion Seam', () {
    test('recommends Channel Blending when timestamp ranges overlap', () {
      final watch = _activityWithRange(
        'Watch',
        DateTime.utc(2026, 11, 20, 6, 0, 0),
        DateTime.utc(2026, 11, 20, 6, 45, 0),
      );
      final strap = _activityWithRange(
        'Strap',
        DateTime.utc(2026, 11, 20, 6, 10, 0),
        DateTime.utc(2026, 11, 20, 6, 40, 0),
      );

      final suggestion = CoreEngine.suggestMultiFileMode([watch, strap]);

      expect(suggestion.recommendedMode, MultiFileCombinationMode.channelBlending);
      expect(suggestion.timestampsOverlap, isTrue);
      expect(suggestion.overlapDuration, const Duration(minutes: 30));
    });

    test('recommends Sequential Stitching when timestamp ranges are sequential or touching', () {
      final part1 = _activityWithRange(
        'Part 1',
        DateTime.utc(2026, 11, 20, 6, 0, 0),
        DateTime.utc(2026, 11, 20, 6, 30, 0),
      );
      final part2WithGap = _activityWithRange(
        'Part 2',
        DateTime.utc(2026, 11, 20, 6, 35, 0),
        DateTime.utc(2026, 11, 20, 7, 0, 0),
      );
      final part2Touching = _activityWithRange(
        'Part 2 Touching',
        DateTime.utc(2026, 11, 20, 6, 30, 0),
        DateTime.utc(2026, 11, 20, 7, 0, 0),
      );

      final gapSuggestion =
          CoreEngine.suggestMultiFileMode([part1, part2WithGap]);
      expect(
        gapSuggestion.recommendedMode,
        MultiFileCombinationMode.sequentialStitching,
      );
      expect(gapSuggestion.timestampsOverlap, isFalse);
      expect(gapSuggestion.overlapDuration, Duration.zero);

      final touchingSuggestion =
          CoreEngine.suggestMultiFileMode([part1, part2Touching]);
      expect(
        touchingSuggestion.recommendedMode,
        MultiFileCombinationMode.sequentialStitching,
      );
      expect(touchingSuggestion.timestampsOverlap, isFalse);
    });

    test('handles unsorted activities and 3+ files accurately', () {
      final part3 = _activityWithRange(
        'Part 3',
        DateTime.utc(2026, 11, 20, 8, 0, 0),
        DateTime.utc(2026, 11, 20, 8, 20, 0),
      );
      final part1 = _activityWithRange(
        'Part 1',
        DateTime.utc(2026, 11, 20, 6, 0, 0),
        DateTime.utc(2026, 11, 20, 6, 20, 0),
      );
      final part2 = _activityWithRange(
        'Part 2',
        DateTime.utc(2026, 11, 20, 7, 0, 0),
        DateTime.utc(2026, 11, 20, 7, 20, 0),
      );

      final sequential =
          CoreEngine.suggestMultiFileMode([part3, part1, part2]);
      expect(
        sequential.recommendedMode,
        MultiFileCombinationMode.sequentialStitching,
      );

      final overlappingPart2 = _activityWithRange(
        'Overlap',
        DateTime.utc(2026, 11, 20, 6, 15, 0),
        DateTime.utc(2026, 11, 20, 7, 20, 0),
      );
      final overlapping =
          CoreEngine.suggestMultiFileMode([part3, part1, overlappingPart2]);
      expect(
        overlapping.recommendedMode,
        MultiFileCombinationMode.channelBlending,
      );
      expect(overlapping.overlapDuration, const Duration(minutes: 5));
    });
  });
}
