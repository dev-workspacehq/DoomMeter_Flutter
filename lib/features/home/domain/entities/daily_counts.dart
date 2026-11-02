/// Immutable counters and independent activity timestamps for one local day.
class DailyCounts {
  const DailyCounts({
    required this.date,
    required this.instagramCount,
    required this.youtubeCount,
    this.lastInstagramActivityAt,
    this.lastYoutubeActivityAt,
  }) : assert(instagramCount >= 0),
       assert(youtubeCount >= 0);

  final DateTime date;
  final int instagramCount;
  final int youtubeCount;
  final DateTime? lastInstagramActivityAt;
  final DateTime? lastYoutubeActivityAt;

  int get totalCount => instagramCount + youtubeCount;
}
