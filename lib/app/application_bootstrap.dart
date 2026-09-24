import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/downloads/download_providers.dart';
import '../core/extensions/manager/extension_providers.dart';

/// The core services that must be LIVE from launch — not from the first time a
/// screen happens to need them.
///
/// Exists as its own provider so the launch wiring is one explicit, testable
/// fact rather than an accident of which surface the user opens first. Both
/// services below do recovery work in their constructors:
///
/// * the extension manager builds the registry and lets a persisted
///   extension's runtime become available;
/// * the download manager runs its restart reconciliation — adopting a
///   transfer that survived under the engine, marking an interrupted one
///   honestly failed, and pumping the persisted queue back into the schedule.
///
/// Before this existed, that download recovery only ran when something read
/// [downloadManagerProvider], i.e. only after the user opened Downloads (or
/// started a download). A user who queued downloads and relaunched the app saw
/// nothing happen at all. Watching this provider from the app's entry point
/// makes the queue resume on launch, which is what "queue persistence"
/// actually promises.
///
/// Reading it is the whole contract: a provider that must run does its work
/// when constructed, so nothing here returns a value.
final Provider<void> applicationBootstrapProvider = Provider<void>((Ref ref) {
  ref.watch(extensionManagerProvider);
  ref.watch(downloadManagerProvider);
});
