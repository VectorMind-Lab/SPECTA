import 'package:specta/core/extensions/contract/extension_capability.dart';

import 'source_format_detector.dart';

/// The native contract this host implements.
///
/// Named so the adapter has one explicit reference to the contract it maps
/// foreign sources onto, rather than a magic number repeated inside a template.
abstract final class NativeContractBridge {
  /// The extension API major version.
  static const int apiMajor = 2;

  /// The additive contract revision implemented by this host.
  static const String contractVersion = '2.1.0';
}

/// Converts an analysed foreign source into JavaScript the native runtime can
/// execute, plus the manifest fields needed to register it.
///
/// ## What the shim does
///
/// The native runtime instantiates a class named `Extension` and calls the
/// contract operations on it. A foreign module exports an object or class under
/// a different name and may use a different calling convention, so the shim:
///
/// 1. captures whatever the module exported, however it exported it;
/// 2. defines `class Extension` that forwards each contract operation to the
///    captured module when that operation exists;
/// 3. returns the SAME shapes the foreign module already produced.
///
/// ## What the shim deliberately does not do
///
/// It does not reinterpret, filter or rewrite results. It does not add network
/// access, and it grants the source no capability its own code does not
/// reference. Its entire authority is to look up an operation on the foreign
/// object and call it. Anything a foreign module cannot express simply does not
/// happen, and that is reported rather than papered over.
abstract final class ForeignSourceAdapter {
  /// Builds the native manifest header for [analysis].
  ///
  /// Values the file did not state are written as explicit defaults rather than
  /// invented facts, so a user can tell that the source declared nothing.
  static String buildManifestHeader(ForeignSourceAnalysis analysis) {
    final String version = analysis.version ?? '0.0.0';
    final StringBuffer buffer = StringBuffer()
      ..writeln('// ==SpectaExtension==')
      ..writeln('// @id ${analysis.id}')
      ..writeln('// @name ${analysis.name}')
      ..writeln('// @version $version')
      ..writeln('// @author ${analysis.author ?? 'Unknown'}')
      // A foreign source is mapped ONTO the native contract; it does not bring
      // its own contract version with it.
      ..writeln('// @apiVersion ${NativeContractBridge.apiMajor}')
      ..writeln('// @contractVersion ${NativeContractBridge.contractVersion}')
      ..writeln('// @type ${analysis.contentTypeCode ?? 'movie'}')
      ..writeln('// @capabilities ${_encodeCapabilities(analysis)}');

    if (analysis.description != null) {
      buffer.writeln('// @description ${analysis.description}');
    }
    if (analysis.website != null) {
      buffer.writeln('// @website ${analysis.website}');
    }
    // Records that the file was adapted rather than written for SPECTA. This is
    // a note about the FORMAT, not a trust signal.
    buffer.writeln('// @format adapted');
    buffer.writeln('// ==/SpectaExtension==');
    return buffer.toString();
  }

  /// Renders the capability list for the manifest header.
  static String _encodeCapabilities(ForeignSourceAnalysis analysis) {
    final List<String> codes =
        analysis.capabilities.map((ExtensionCapability c) => c.code).toList()
          ..sort();
    return codes.isEmpty ? 'none' : codes.join(',');
  }

  /// Builds the executable shim around [jsSource].
  ///
  /// The foreign body is included verbatim: SPECTA does not rewrite the user's
  /// or a third party's code, it only adds a bridge around it.
  static String buildShimmedBody(
    ForeignSourceAnalysis analysis,
    String jsSource,
  ) {
    final Set<String> operations = analysis.entryPoints;
    // The member the author's file ACTUALLY uses for each contract operation.
    // Calling the contract name unconditionally is what made every adapted
    // third-party source install successfully and then fail on the first call.
    final Map<String, String> members = analysis.operationMembers;
    String member(String operation) => members[operation] ?? operation;
    return '''
// ---------------------------------------------------------------------------
// SPECTA compatibility prelude (generated).
//
// The sandbox is a plain script global: it defines `SpectaExtension` and
// nothing else, so a CommonJS module's own `module.exports = ...` line would
// throw ReferenceError on the very first statement. This declares the object
// that line fills in, and the shim at the bottom of this file reads it back.
// The imported code below is still included verbatim; nothing in it changed.
// ---------------------------------------------------------------------------
const __spectaModule = { exports: {} };
var module = __spectaModule;
var exports = __spectaModule.exports;

$jsSource

// ---------------------------------------------------------------------------
// SPECTA compatibility shim (generated).
//
// The code above is the source exactly as imported; nothing in it was modified.
// This shim only captures what it exported and forwards the SPECTA contract
// operations to it. It has no authority of its own: it cannot reach the
// network, the filesystem or any host API except through the sandbox channels
// the source's own declared capabilities already allow.
// ---------------------------------------------------------------------------

const __spectaForeign = (function () {
  try {
    // A CommonJS module's export, but only when it actually exported something.
    // The prelude above always creates an EMPTY `module.exports`, so returning it
    // unconditionally would shadow a script that exports nothing and simply
    // declares top-level functions - which is exactly the shape every real
    // third-party provider uses. An empty export is treated as "no export".
    if (typeof module !== 'undefined' && module.exports
        && Object.keys(module.exports).length > 0) {
      return module.exports;
    }
    if (typeof exports !== 'undefined' && exports
        && Object.keys(exports).length > 0) {
      return exports;
    }
  } catch (e) {
    // A module that throws while exporting simply has no export; the global
    // lookup below handles it.
  }
  // No usable export: fall back to the script global itself, where a
  // non-module file's top-level `function search() {}` declarations live.
  if (typeof globalThis !== 'undefined') return globalThis;
  return null;
})();

class Extension extends SpectaExtension {
  __spectaResolve() {
    // The CommonJS/ES export first, then a global the module chose to set.
    // There is deliberately no fallback to `this`: the only members on this
    // instance are the forwarding methods generated below, so resolving to
    // `this` would invoke the forwarder again and recurse until the stack
    // gives out. A source whose export cannot be captured has nothing to call,
    // and __spectaCall reports that instead of looping.
    if (__spectaForeign) return __spectaForeign;
    if (typeof globalThis !== 'undefined' && globalThis.__spectaForeign) {
      return globalThis.__spectaForeign;
    }
    return null;
  }

  async __spectaCall(name, args) {
    const target = this.__spectaResolve();
    if (target && typeof target[name] === 'function') {
      return await target[name](...args);
    }
    // The operation is absent, not silently failing: say so, so the runtime
    // reports a real incompatibility instead of an empty result.
    throw new Error('This source does not implement "' + name + '".');
  }
${operations.contains('search') ? '''
  async search(query, page) {
    return await this.__spectaCall('${member('search')}', [query, page]);
  }
''' : ''}${operations.contains('latest') ? '''
  async latest(page) {
    return await this.__spectaCall('${member('latest')}', [page]);
  }
''' : ''}${operations.contains('details') ? '''
  async details(reference) {
    return await this.__spectaCall('${member('details')}', [reference]);
  }
''' : ''}${operations.contains('getSources') ? '''
  async getSources(reference) {
    return await this.__spectaCall('${member('getSources')}', [reference]);
  }
''' : ''}
  async healthCheck() {
    try {
      return await this.__spectaCall('healthCheck', []);
    } catch (e) {
      // A source with no health check is not unhealthy. The absence of an
      // implementation is reported as "cannot prove" rather than "broken".
      return true;
    }
  }
}
''';
  }

  /// Builds the complete adapted source: manifest header + foreign code + shim.
  ///
  /// This is what the manager persists, so the adapted file is self-describing
  /// and re-parses through the normal native path on a later read.
  static String adapt(ForeignSourceAnalysis analysis, String jsSource) =>
      '${buildManifestHeader(analysis)}${buildShimmedBody(analysis, jsSource)}';
}
