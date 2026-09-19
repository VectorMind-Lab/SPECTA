import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3.x no longer re-exports `Override` from flutter_riverpod.
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:specta/core/extensions/contract/result_models.dart';
import 'package:specta/core/library/library_providers.dart';
import 'package:specta/core/library/watch_progress.dart';
import 'package:specta/features/library/library_view.dart';

import '../../support/in_memory_library_store.dart';

Future<void> _pumpLibrary(
  WidgetTester tester,
  InMemoryLibraryStore store,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        libraryStoreProvider.overrideWith((Ref ref) => store),
      ],
      child: const MaterialApp(home: Scaffold(body: LibraryView())),
    ),
  );
  await tester.pumpAndSettle();
}

WatchProgress _movie({
  String id = 'A|movie|2024',
  String title = 'A Movie',
  Duration position = const Duration(seconds: 30),
  Duration? duration = const Duration(minutes: 2),
  bool completed = false,
  DateTime? at,
}) =>
    WatchProgress(
      id: id,
      mediaKey: 'A|movie|2024',
      mediaType: MediaType.movie,
      title: title,
      position: position,
      duration: duration,
      completed: completed,
      updatedAt: at ?? DateTime(2026, 1, 1),
    );

void main() {
  testWidgets('an empty library states its real status, not fake content',
      (WidgetTester tester) async {
    await _pumpLibrary(tester, InMemoryLibraryStore());

    expect(find.textContaining('Nothing here yet'), findsOneWidget);
    expect(find.text('Continue Watching'), findsNothing);
  });

  testWidgets('renders Continue Watching and History from the store',
      (WidgetTester tester) async {
    final InMemoryLibraryStore store = InMemoryLibraryStore();
    await store.upsert(
      _movie(
        id: 'in-progress',
        title: 'Half Watched',
        position: const Duration(seconds: 30),
        at: DateTime(2026, 2, 1),
      ),
    );
    await store.upsert(
      _movie(
        id: 'finished',
        title: 'All Done',
        position: const Duration(minutes: 2),
        completed: true,
        at: DateTime(2026, 1, 1),
      ),
    );

    await _pumpLibrary(tester, store);

    expect(find.text('Continue Watching'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    // The in-progress item appears (in Continue Watching and History).
    expect(find.text('Half Watched'), findsNWidgets(2));
    // The completed item appears in History only, marked distinctly.
    expect(find.text('All Done'), findsOneWidget);
    expect(find.text('Watched'), findsOneWidget);
  });

  testWidgets('an episode shows its season/episode line', (WidgetTester tester) async {
    final InMemoryLibraryStore store = InMemoryLibraryStore();
    await store.upsert(
      WatchProgress(
        id: 'Show|series|2024|s2e5',
        mediaKey: 'Show|series|2024',
        mediaType: MediaType.series,
        title: 'Show',
        subtitleLine: 'Season 2 · Episode 5',
        seasonNumber: 2,
        episodeNumber: 5,
        position: const Duration(seconds: 40),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );

    await _pumpLibrary(tester, store);

    expect(find.textContaining('SERIES'), findsWidgets);
    expect(find.textContaining('Season 2 · Episode 5'), findsWidgets);
  });
}
