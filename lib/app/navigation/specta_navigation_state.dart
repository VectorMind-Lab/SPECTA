import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'specta_destination.dart';

/// Manages the current navigation destination for the app shell.
class SpectaNavigationNotifier extends Notifier<SpectaDestination> {
  @override
  SpectaDestination build() => SpectaDestination.home;

  void selectDestination(SpectaDestination destination) {
    state = destination;
  }

  void selectByIndex(int index) {
    if (index >= 0 && index < SpectaDestination.values.length) {
      state = SpectaDestination.values[index];
    }
  }
}

/// Current navigation destination state.
final NotifierProvider<SpectaNavigationNotifier, SpectaDestination>
spectaNavigationProvider =
    NotifierProvider<SpectaNavigationNotifier, SpectaDestination>(
      SpectaNavigationNotifier.new,
    );
