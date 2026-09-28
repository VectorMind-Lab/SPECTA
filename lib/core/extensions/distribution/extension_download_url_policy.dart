/// URL policy for extension DISTRIBUTION.
///
/// Distribution is not trust: a URL that passes these rules says nothing about
/// whether the extension behind it is legitimate. Trust is the manifest
/// signature, verified by `ExtensionManager` after the bytes land.
library;

import 'package:specta/core/errors/specta_failure.dart';
import 'package:specta/core/errors/specta_result.dart';

/// Validates an extension download URL.
///
/// SPECTA fetches extensions over HTTPS from the public internet only:
///
/// * `http://` is REFUSED, not upgraded. Silently upgrading would mean trusting
///   content the user never saw served over TLS, and would let an attacker
///   hand out an `http` link that ends up fetched over `https` anyway.
/// * Embedded `user:password@` credentials are refused, so an extension link
///   can never smuggle a secret into a request.
/// * Loopback / private / link-local targets are refused, mirroring the sandbox
///   request policy so distribution cannot be aimed at the user's own network.
SpectaResult<Uri> validateExtensionUrl(Uri? uri) {
  if (uri == null || !uri.isAbsolute || uri.scheme.isEmpty) {
    return Err<Uri>(
      ExtensionDistributionFailure(
        type: ExtensionDistributionFailureType.invalidUrl,
        stage: 'validate',
        detail: 'URL is not absolute.',
      ),
    );
  }
  if (uri.scheme.toLowerCase() != 'https') {
    return Err<Uri>(
      ExtensionDistributionFailure(
        type: ExtensionDistributionFailureType.invalidUrl,
        stage: 'validate',
        detail: 'Only https:// extension links are accepted.',
      ),
    );
  }
  if (uri.host.isEmpty) {
    return Err<Uri>(
      ExtensionDistributionFailure(
        type: ExtensionDistributionFailureType.invalidUrl,
        stage: 'validate',
        detail: 'URL has no host.',
      ),
    );
  }
  if (uri.userInfo.isNotEmpty) {
    return Err<Uri>(
      ExtensionDistributionFailure(
        type: ExtensionDistributionFailureType.invalidUrl,
        stage: 'validate',
        detail: 'URL carries embedded credentials.',
      ),
    );
  }
  if (isBlockedExtensionHost(uri.host)) {
    return Err<Uri>(
      ExtensionDistributionFailure(
        type: ExtensionDistributionFailureType.hostBlocked,
        stage: 'validate',
        detail: 'Target is a loopback/private/link-local address.',
      ),
    );
  }
  return Ok<Uri>(uri);
}

/// True for hosts that must never be fetched for an extension: loopback,
/// private RFC1918, link-local, unique-local and unspecified addresses, in both
/// IPv4 and IPv6 including IPv4-mapped forms.
bool isBlockedExtensionHost(String host) {
  final String value = host.toLowerCase().trim();
  if (value.isEmpty) return true;
  if (value == 'localhost' || value.endsWith('.localhost')) return true;

  String candidate = value;
  final int zone = candidate.indexOf('%');
  if (zone > 0) candidate = candidate.substring(0, zone);

  // IPv4-mapped IPv6, e.g. ::ffff:127.0.0.1
  final RegExp mapped = RegExp(r'^::ffff:(\d+\.\d+\.\d+\.\d+)$');
  final RegExpMatch? mappedMatch = mapped.firstMatch(candidate);
  if (mappedMatch != null) candidate = mappedMatch.group(1)!;

  if (candidate == '::1' || candidate == '0:0:0:0:0:0:0:1') return true;
  if (candidate == '::' || candidate == '0:0:0:0:0:0:0:0') return true;

  final List<String> parts = candidate.split('.');
  if (parts.length == 4) {
    final List<int> octets = <int>[];
    for (final String part in parts) {
      final int? octet = int.tryParse(part);
      // Not a dotted quad; fall through to the IPv6 checks.
      if (octet == null || octet < 0 || octet > 255) {
        return _isBlockedIpv6(candidate);
      }
      octets.add(octet);
    }
    if (octets[0] == 127) return true; // loopback
    if (octets[0] == 10) return true; // private
    if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
    if (octets[0] == 192 && octets[1] == 168) return true; // private
    if (octets[0] == 169 && octets[1] == 254) {
      return true; // link-local
    }
    if (octets.every((int o) => o == 0)) return true; // unspecified
    return false;
  }

  return _isBlockedIpv6(candidate);
}

bool _isBlockedIpv6(String candidate) {
  if (candidate.startsWith('fc') || candidate.startsWith('fd')) {
    return true; // ULA
  }
  if (candidate.length >= 3) {
    final String head = candidate.substring(0, 3);
    if (const <String>{'fe8', 'fe9', 'fea', 'feb'}.contains(head)) {
      return true;
    }
  }
  return false;
}
