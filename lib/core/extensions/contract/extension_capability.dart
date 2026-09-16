import '../../errors/specta_failure.dart';

/// A capability an extension must declare before SPECTA grants it.
///
/// Capabilities are declared in the manifest header (`// @capabilities`) and
/// not at run time. Two reasons:
///
/// * **Auditability.** What an extension asks for must be knowable *before* its
///   code is executed. A declaration that only arrives after the code has
///   started running is not a gate.
/// * **Enforcement point.** The runtime can install or withhold a host channel
///   when it loads the extension, so a capability that was never declared is
///   never reachable, rather than reachable-and-then-checked.
///
/// The list is deliberately short and closed. There is no filesystem, contacts,
/// SMS, photo, device-identifier, database, native-code or application-control
/// capability, and none may be added without an explicit product decision —
/// extensions are not granted Android permissions.
///
/// Absence is the default: an extension that declares nothing gets nothing.
enum ExtensionCapability {
  /// `request()` — the controlled host network channel.
  network('network'),

  /// `log()` — the controlled host logging channel.
  logging('logging'),

  /// The `search(query, page)` contract operation.
  search('search'),

  /// The `latest(page)` contract operation.
  latest('latest'),

  /// The `details(url)` contract operation.
  details('details'),

  /// The `getSources(reference)` / `refreshSource(reference)` operations.
  sources('sources');

  const ExtensionCapability(this.code);

  /// Stable identifier used in manifests and diagnostics.
  final String code;

  /// Whether this capability gates a host channel rather than a contract
  /// operation.
  bool get isRuntimeCapability =>
      this == ExtensionCapability.network ||
      this == ExtensionCapability.logging;

  /// Looks up a capability by [code], case-insensitively.
  static ExtensionCapability? fromCode(String code) {
    final String normalised = code.trim().toLowerCase();
    for (final ExtensionCapability capability in ExtensionCapability.values) {
      if (capability.code == normalised) return capability;
    }
    return null;
  }

  /// Parses a comma-separated manifest `@capabilities` value.
  ///
  /// Returns null when any token is unrecognised, so a manifest that asks for
  /// something SPECTA does not implement is rejected instead of being silently
  /// narrowed to the subset that happens to parse. Blank entries are ignored,
  /// which makes an empty declaration mean "no capabilities".
  static Set<ExtensionCapability>? parseDeclaration(String raw) {
    final List<String> tokens = raw
        .split(',')
        .map((String token) => token.trim())
        .where((String token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return <ExtensionCapability>{};

    final Set<ExtensionCapability> declared = <ExtensionCapability>{};
    for (final String token in tokens) {
      final ExtensionCapability? capability = fromCode(token);
      if (capability == null) return null;
      declared.add(capability);
    }
    return declared;
  }

  /// Renders a capability set as a stable, sorted, comma-separated string.
  ///
  /// Used for the canonical signed metadata, so the order a manifest happens to
  /// list capabilities in cannot change its signature.
  static String encodeDeclaration(Set<ExtensionCapability> capabilities) {
    final List<String> codes =
        capabilities
            .map((ExtensionCapability capability) => capability.code)
            .toList()
          ..sort();
    return codes.join(',');
  }
}

/// Builds the structured failure for a denied capability.
///
/// A denied capability is a controlled outcome, never an exception: the caller
/// (or the extension, over the message channel) receives the canonical
/// [ExtensionFailureType.capabilityError] code and the name of the capability
/// that was not declared.
CapabilityFailure capabilityDeniedFailure({
  required String extensionId,
  required ExtensionCapability capability,
  required String operation,
}) {
  return CapabilityFailure(
    extensionId: extensionId,
    capability: capability.code,
    message:
        'Extension did not declare the "${capability.code}" capability, '
        'so $operation was refused.',
  );
}
