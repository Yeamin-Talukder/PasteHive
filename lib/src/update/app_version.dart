/// A version such as `1.2.0` or `1.2.0-beta.1`, as release tags name them.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, [this.preRelease = '']);

  final int major;
  final int minor;
  final int patch;

  /// What follows the hyphen, such as `beta.1`; empty for a full release.
  final String preRelease;

  /// Reads `1.2.0`, `v1.2.0`, `1.2.0-beta.1` and `1.2.0+7` (the build number
  /// is ignored). Returns null for anything else.
  static AppVersion? tryParse(String text) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+.*)?$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    return AppVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      match[4] ?? '',
    );
  }

  bool get isPreRelease => preRelease.isNotEmpty;

  @override
  int compareTo(AppVersion other) {
    for (final (mine, theirs) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (mine != theirs) return mine.compareTo(theirs);
    }
    // A pre-release comes before the release it leads up to.
    if (isPreRelease != other.isPreRelease) return isPreRelease ? -1 : 1;
    return _comparePreRelease(preRelease, other.preRelease);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  // Part by part: numbers by value, words by spelling, numbers before words.
  static int _comparePreRelease(String a, String b) {
    final left = a.split('.');
    final right = b.split('.');
    for (var i = 0; i < left.length && i < right.length; i++) {
      final leftNumber = int.tryParse(left[i]);
      final rightNumber = int.tryParse(right[i]);
      final int order;
      if (leftNumber != null && rightNumber != null) {
        order = leftNumber.compareTo(rightNumber);
      } else if (leftNumber != null) {
        order = -1;
      } else if (rightNumber != null) {
        order = 1;
      } else {
        order = left[i].compareTo(right[i]);
      }
      if (order != 0) return order;
    }
    return left.length.compareTo(right.length);
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() =>
      '$major.$minor.$patch${isPreRelease ? '-$preRelease' : ''}';
}
