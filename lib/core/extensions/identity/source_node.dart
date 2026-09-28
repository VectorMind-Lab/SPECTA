/// Which numbering space an installed source's node label belongs to.
///
/// The two spaces are deliberately disjoint so an official label and a user
/// label can never collide, however many of each are installed:
///
/// * [official] -> `Node 0`, `Node A`, `Node B`, ... `Node Z`, `Node AA`, ...
/// * [user]     -> `Node 1`, `Node 2`, `Node 3`, ...
///
/// ## Space is decided by the INSTALL ROUTE, never by the signature
///
/// A source the user picked from their device, pasted as a link, or installed
/// from a repository they supplied is a [user] node EVEN IF it carries a valid
/// SPECTA signature. It keeps its green dot, because the dot reports
/// cryptographic provenance; but it is not an official *node*, and it is not
/// undeletable. Only sources that arrived through SPECTA's own official
/// distribution are [official].
///
/// Conflating the two is the bug this type exists to prevent: a user importing a
/// signed file must never end up holding the undeletable Node 0.
enum SourceNodeSpace {
  /// Sources delivered by SPECTA's own distribution. Labelled `Node 0`, then
  /// `Node A` onwards.
  official,

  /// Sources the user brought themselves by any route. Labelled `Node 1`
  /// onwards.
  user,
}

/// A node's identity: WHICH space it belongs to and its index WITHIN that
/// space.
///
/// [index] is the number the label is built from, and it is the value that must
/// be persisted. It is never recomputed from a list position, because deriving it
/// would renumber every later node the moment an earlier one is deleted.
final class SourceNode {
  const SourceNode({required this.space, required this.index});

  /// Builds a node from its persisted code strings, or null when either is
  /// absent or malformed. `null` means "not assigned yet", which is the state a
  /// pre-migration row is in.
  static SourceNode? fromCodes(String? spaceCode, String? indexCode) {
    if (spaceCode == null || indexCode == null) return null;
    final SourceNodeSpace? space = SourceNodeSpace.values
        .where((SourceNodeSpace s) => s.name == spaceCode)
        .firstOrNull;
    if (space == null) return null;
    final int? index = int.tryParse(indexCode);
    if (index == null || index < 0) return null;
    return SourceNode(space: space, index: index);
  }

  final SourceNodeSpace space;

  /// Position within [space]. Never negative.
  final int index;

  bool get isOfficial => space == SourceNodeSpace.official;

  /// The user-facing label, e.g. `Node 0`, `Node A`, `Node 1`.
  ///
  /// The official space is special at index 0 — the first official source is
  /// `Node 0`, not `Node A` — and then counts in letters. Past `Z` it continues
  /// in bijective base-26, so the 27th official source is `Node AA`.
  String get label {
    switch (space) {
      case SourceNodeSpace.user:
        return 'Node $index';
      case SourceNodeSpace.official:
        if (index == 0) return 'Node 0';
        if (index <= 26) {
          return 'Node ${String.fromCharCode(65 + index - 1)}';
        }
        // Bijective base-26 over (index - 26), two letters wide: 27 -> AA,
        // 28 -> AB, ... 52 -> AZ, 53 -> BA.
        final int n = index - 26;
        final int first = (n - 1) ~/ 26;
        final int second = (n - 1) % 26;
        return 'Node ${String.fromCharCode(65 + first)}'
            '${String.fromCharCode(65 + second)}';
    }
  }

  /// Stable codes for persistence.
  String get spaceCode => space.name;
  String get indexCode => '$index';

  @override
  bool operator ==(Object other) =>
      other is SourceNode && other.space == space && other.index == index;

  @override
  int get hashCode => Object.hash(space, index);

  @override
  String toString() => '$label ($spaceCode:$indexCode)';
}

/// Assigns node labels inside a space.
///
/// The one rule that matters: allocation takes the LOWEST FREE index in the
/// space, never `max + 1`. A compacted list would renumber survivors when an
/// earlier node is deleted; reading the assigned set cannot.
abstract final class SourceNodeAllocator {
  /// The lowest index in [space] that is not already taken.
  ///
  /// [assigned] is the set of indices currently in use in that space. Returns
  /// 0 for the official space and 1 for the user space when nothing is taken,
  /// because the two spaces start at different places.
  static int next(
    SourceNodeSpace space,
    Set<int> assigned,
  ) {
    int start = switch (space) {
      SourceNodeSpace.official => 0,
      SourceNodeSpace.user => 1,
    };
    int candidate = start;
    while (assigned.contains(candidate)) {
      candidate++;
    }
    return candidate;
  }
}
