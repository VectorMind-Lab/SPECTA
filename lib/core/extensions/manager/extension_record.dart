import 'package:specta/core/extensions/identity/trust_level.dart';

/// Immutable snapshot of an installed extension's metadata.
///
/// This is the SPECTA-side model — independent of the JS manifest.  The
/// manifest is the raw source; [ExtensionRecord] is the trusted, validated,
/// persisted form.
final class ExtensionRecord {
  const ExtensionRecord({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.apiVersion,
    required this.contentType,
    this.contractVersion = '2.0.0',
    this.signature,
    required this.trustLevel,
    required this.enabled,
    required this.filePath,
    required this.installedAt,
    required this.updatedAt,
    this.previousVersionPath,
    this.previousVersion,
  });

  final String id;
  final String name;
  final String version;
  final String author;
  final int apiVersion;
  final String contentType;
  final String contractVersion;
  final String? signature;
  final TrustLevel trustLevel;
  final bool enabled;
  final String filePath;
  final DateTime installedAt;
  final DateTime updatedAt;
  final String? previousVersionPath;
  final String? previousVersion;

  ExtensionRecord copyWith({
    String? id,
    String? name,
    String? version,
    String? author,
    int? apiVersion,
    String? contentType,
    String? contractVersion,
    String? Function()? signature,
    TrustLevel? trustLevel,
    bool? enabled,
    String? filePath,
    DateTime? installedAt,
    DateTime? updatedAt,
    String? Function()? previousVersionPath,
    String? Function()? previousVersion,
  }) {
    return ExtensionRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      author: author ?? this.author,
      apiVersion: apiVersion ?? this.apiVersion,
      contentType: contentType ?? this.contentType,
      contractVersion: contractVersion ?? this.contractVersion,
      signature: signature != null ? signature() : this.signature,
      trustLevel: trustLevel ?? this.trustLevel,
      enabled: enabled ?? this.enabled,
      filePath: filePath ?? this.filePath,
      installedAt: installedAt ?? this.installedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      previousVersionPath: previousVersionPath != null
          ? previousVersionPath()
          : this.previousVersionPath,
      previousVersion: previousVersion != null
          ? previousVersion()
          : this.previousVersion,
    );
  }

  @override
  String toString() =>
      'ExtensionRecord(id: $id, version: $version, enabled: $enabled, '
      'trust: ${trustLevel.code})';
}

/// A historical version of an extension, kept for rollback.
final class ExtensionVersionRecord {
  const ExtensionVersionRecord({
    required this.id,
    required this.extensionId,
    required this.version,
    required this.filePath,
    required this.isCurrent,
    required this.isRollbackPoint,
    required this.createdAt,
    this.contractVersion = '2.0.0',
  });

  final String id;
  final String extensionId;
  final String version;
  final String filePath;
  final bool isCurrent;
  final bool isRollbackPoint;
  final DateTime createdAt;
  final String contractVersion;
}

/// A single recorded failure for health tracking.
final class ExtensionFailureRecord {
  const ExtensionFailureRecord({
    required this.id,
    required this.extensionId,
    required this.failureType,
    required this.operation,
    required this.message,
    this.detail,
    required this.timestamp,
    required this.retryable,
  });

  final String id;
  final String extensionId;
  final String failureType;
  final String operation;
  final String message;
  final String? detail;
  final DateTime timestamp;
  final bool retryable;
}
