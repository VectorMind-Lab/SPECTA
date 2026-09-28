@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:specta/core/extensions/identity/source_node.dart';

/// Slice 2 — the node identity model. Pure, no I/O, no database.
///
/// These tests exist because the numbering rules are easy to get subtly wrong
/// and impossible to eyeball once real data is involved. The two that matter
/// most are at the bottom: deleting a node must NOT renumber the ones after it,
/// and the two numbering spaces must never collide.
void main() {
  group('official labels', () {
    String labelAt(int i) =>
        SourceNode(space: SourceNodeSpace.official, index: i).label;

    test('the first official source is Node 0, not Node A', () {
      expect(labelAt(0), 'Node 0');
    });

    test('then letters A, B, C in order', () {
      expect(labelAt(1), 'Node A');
      expect(labelAt(2), 'Node B');
      expect(labelAt(3), 'Node C');
    });

    test('Z is the last single-letter label', () {
      expect(labelAt(25), 'Node Y');
      expect(labelAt(26), 'Node Z');
    });

    test('past Z it continues AA, AB, AC', () {
      expect(labelAt(27), 'Node AA');
      expect(labelAt(28), 'Node AB');
      expect(labelAt(29), 'Node AC');
    });

    test('the AA block runs through AZ then rolls to BA', () {
      expect(labelAt(52), 'Node AZ');
      expect(labelAt(53), 'Node BA');
      expect(labelAt(78), 'Node BZ');
      expect(labelAt(79), 'Node CA');
    });
  });

  group('user labels', () {
    test('count from 1, not 0', () {
      expect(
        const SourceNode(space: SourceNodeSpace.user, index: 1).label,
        'Node 1',
      );
      expect(
        const SourceNode(space: SourceNodeSpace.user, index: 2).label,
        'Node 2',
      );
      expect(
        const SourceNode(space: SourceNodeSpace.user, index: 13).label,
        'Node 13',
      );
    });
  });

  group('the two spaces never collide', () {
    test('no official label equals any user label', () {
      final Set<String> official = <String>{
        for (int i = 0; i <= 60; i++)
          SourceNode(space: SourceNodeSpace.official, index: i).label,
      };
      final Set<String> user = <String>{
        for (int i = 1; i <= 60; i++)
          SourceNode(space: SourceNodeSpace.user, index: i).label,
      };
      expect(official.intersection(user), isEmpty);
    });

    test('every label within a space is unique', () {
      final Set<String> official = <String>{
        for (int i = 0; i <= 300; i++)
          SourceNode(space: SourceNodeSpace.official, index: i).label,
      };
      expect(official.length, 301);
    });
  });

  group('allocation', () {
    test('an empty official space starts at 0', () {
      expect(SourceNodeAllocator.next(SourceNodeSpace.official, <int>{}), 0);
    });

    test('an empty user space starts at 1', () {
      expect(SourceNodeAllocator.next(SourceNodeSpace.user, <int>{}), 1);
    });

    test('it fills the first FREE slot, not the highest plus one', () {
      // Node 0 and Node A exist; Node B is the first free official slot.
      expect(
        SourceNodeAllocator.next(SourceNodeSpace.official, <int>{0, 1}),
        2,
      );
    });

    test('a gap in the middle is reused', () {
      expect(
        SourceNodeAllocator.next(SourceNodeSpace.user, <int>{1, 3, 4}),
        2,
      );
    });
  });

  group('the load-bearing rule — deleting does not renumber', () {
    test('if Node 2 is removed, Node 3 is still Node 3', () {
      // This is the exact scenario the owner specified. Node 3 exists and holds
      // index 3; removing Node 2 changes nothing about it, because the label is
      // a stored value rather than a computed position.
      const SourceNode node2 = SourceNode(
        space: SourceNodeSpace.user,
        index: 2,
      );
      const SourceNode node3 = SourceNode(
        space: SourceNodeSpace.user,
        index: 3,
      );
      expect(node2.label, 'Node 2');
      expect(node3.label, 'Node 3');

      // Node 2 is gone; Node 3 is untouched.
      final Set<SourceNode> survivors = <SourceNode>{node3};
      expect(survivors.single.label, 'Node 3');
    });

    test('a survivor is never renumbered by a later allocation', () {
      const SourceNode node3 = SourceNode(
        space: SourceNodeSpace.user,
        index: 3,
      );
      final Set<int> afterDeletingNode2 = <int>{1, 3};
      // The allocator reuses the freed slot 2 for the NEXT new source, so the
      // existing Node 3 keeps both its index and its label.
      final int nextNew = SourceNodeAllocator.next(
        SourceNodeSpace.user,
        afterDeletingNode2,
      );
      expect(nextNew, 2);
      expect(node3.index, 3);
      expect(node3.label, 'Node 3');
    });
  });

  group('persistence codes', () {
    test('round-trip through codes', () {
      for (final SourceNode node in <SourceNode>[
        const SourceNode(space: SourceNodeSpace.official, index: 0),
        const SourceNode(space: SourceNodeSpace.official, index: 26),
        const SourceNode(space: SourceNodeSpace.user, index: 7),
      ]) {
        final SourceNode? back = SourceNode.fromCodes(
          node.spaceCode,
          node.indexCode,
        );
        expect(back, node);
      }
    });

    test('a missing or malformed row decodes to null, not a guess', () {
      expect(SourceNode.fromCodes(null, '0'), isNull);
      expect(SourceNode.fromCodes('user', null), isNull);
      expect(SourceNode.fromCodes('nonsense', '1'), isNull);
      expect(SourceNode.fromCodes('user', 'not-a-number'), isNull);
      expect(SourceNode.fromCodes('user', '-1'), isNull);
    });
  });

  group('equality', () {
    test('two nodes with the same space and index are equal', () {
      expect(
        const SourceNode(space: SourceNodeSpace.user, index: 2),
        const SourceNode(space: SourceNodeSpace.user, index: 2),
      );
    });

    test('the same index in different spaces is NOT equal', () {
      expect(
        const SourceNode(space: SourceNodeSpace.official, index: 1),
        isNot(const SourceNode(space: SourceNodeSpace.user, index: 1)),
      );
    });
  });
}

