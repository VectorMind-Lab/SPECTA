// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'specta_database.dart';

// ignore_for_file: type=lint
class $SettingsEntriesTable extends SettingsEntries
    with TableInfo<$SettingsEntriesTable, SettingEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingEntry(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SettingsEntriesTable createAlias(String alias) {
    return $SettingsEntriesTable(attachedDatabase, alias);
  }
}

class SettingEntry extends DataClass implements Insertable<SettingEntry> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const SettingEntry({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SettingsEntriesCompanion toCompanion(bool nullToAbsent) {
    return SettingsEntriesCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory SettingEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingEntry(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SettingEntry copyWith({String? key, String? value, DateTime? updatedAt}) =>
      SettingEntry(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SettingEntry copyWithCompanion(SettingsEntriesCompanion data) {
    return SettingEntry(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingEntry(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingEntry &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class SettingsEntriesCompanion extends UpdateCompanion<SettingEntry> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SettingsEntriesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsEntriesCompanion.insert({
    required String key,
    required String value,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingEntry> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsEntriesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SettingsEntriesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsEntriesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExtensionsTable extends Extensions
    with TableInfo<$ExtensionsTable, Extension> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExtensionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _apiVersionMeta = const VerificationMeta(
    'apiVersion',
  );
  @override
  late final GeneratedColumn<int> apiVersion = GeneratedColumn<int>(
    'api_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentTypeMeta = const VerificationMeta(
    'contentType',
  );
  @override
  late final GeneratedColumn<String> contentType = GeneratedColumn<String>(
    'content_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _signatureMeta = const VerificationMeta(
    'signature',
  );
  @override
  late final GeneratedColumn<String> signature = GeneratedColumn<String>(
    'signature',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trustLevelMeta = const VerificationMeta(
    'trustLevel',
  );
  @override
  late final GeneratedColumn<String> trustLevel = GeneratedColumn<String>(
    'trust_level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<int> enabled = GeneratedColumn<int>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _installedAtMeta = const VerificationMeta(
    'installedAt',
  );
  @override
  late final GeneratedColumn<DateTime> installedAt = GeneratedColumn<DateTime>(
    'installed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  static const VerificationMeta _previousVersionPathMeta =
      const VerificationMeta('previousVersionPath');
  @override
  late final GeneratedColumn<String> previousVersionPath =
      GeneratedColumn<String>(
        'previous_version_path',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _previousVersionMeta = const VerificationMeta(
    'previousVersion',
  );
  @override
  late final GeneratedColumn<String> previousVersion = GeneratedColumn<String>(
    'previous_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    version,
    author,
    apiVersion,
    contentType,
    signature,
    trustLevel,
    enabled,
    filePath,
    installedAt,
    updatedAt,
    previousVersionPath,
    previousVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'extensions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Extension> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    } else if (isInserting) {
      context.missing(_authorMeta);
    }
    if (data.containsKey('api_version')) {
      context.handle(
        _apiVersionMeta,
        apiVersion.isAcceptableOrUnknown(data['api_version']!, _apiVersionMeta),
      );
    } else if (isInserting) {
      context.missing(_apiVersionMeta);
    }
    if (data.containsKey('content_type')) {
      context.handle(
        _contentTypeMeta,
        contentType.isAcceptableOrUnknown(
          data['content_type']!,
          _contentTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentTypeMeta);
    }
    if (data.containsKey('signature')) {
      context.handle(
        _signatureMeta,
        signature.isAcceptableOrUnknown(data['signature']!, _signatureMeta),
      );
    }
    if (data.containsKey('trust_level')) {
      context.handle(
        _trustLevelMeta,
        trustLevel.isAcceptableOrUnknown(data['trust_level']!, _trustLevelMeta),
      );
    } else if (isInserting) {
      context.missing(_trustLevelMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('installed_at')) {
      context.handle(
        _installedAtMeta,
        installedAt.isAcceptableOrUnknown(
          data['installed_at']!,
          _installedAtMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('previous_version_path')) {
      context.handle(
        _previousVersionPathMeta,
        previousVersionPath.isAcceptableOrUnknown(
          data['previous_version_path']!,
          _previousVersionPathMeta,
        ),
      );
    }
    if (data.containsKey('previous_version')) {
      context.handle(
        _previousVersionMeta,
        previousVersion.isAcceptableOrUnknown(
          data['previous_version']!,
          _previousVersionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Extension map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Extension(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      )!,
      apiVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}api_version'],
      )!,
      contentType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_type'],
      )!,
      signature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signature'],
      ),
      trustLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trust_level'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}enabled'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      installedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}installed_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      previousVersionPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}previous_version_path'],
      ),
      previousVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}previous_version'],
      ),
    );
  }

  @override
  $ExtensionsTable createAlias(String alias) {
    return $ExtensionsTable(attachedDatabase, alias);
  }
}

class Extension extends DataClass implements Insertable<Extension> {
  final String id;
  final String name;
  final String version;
  final String author;
  final int apiVersion;

  /// ExtensionContentType.code, e.g. `movies_series`.
  final String contentType;

  /// Raw signature string from the manifest, or null when unsigned.
  final String? signature;

  /// TrustLevel.code: `official` or `unverified`.
  final String trustLevel;

  /// Whether the extension is enabled.  Disabled extensions do not execute.
  final int enabled;

  /// On-disk path to the extension `.js` file.
  final String filePath;
  final DateTime installedAt;
  final DateTime updatedAt;

  /// File path of the previous known-good version, kept for rollback.
  final String? previousVersionPath;

  /// Version string of the previous known-good version.
  final String? previousVersion;
  const Extension({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.apiVersion,
    required this.contentType,
    this.signature,
    required this.trustLevel,
    required this.enabled,
    required this.filePath,
    required this.installedAt,
    required this.updatedAt,
    this.previousVersionPath,
    this.previousVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['version'] = Variable<String>(version);
    map['author'] = Variable<String>(author);
    map['api_version'] = Variable<int>(apiVersion);
    map['content_type'] = Variable<String>(contentType);
    if (!nullToAbsent || signature != null) {
      map['signature'] = Variable<String>(signature);
    }
    map['trust_level'] = Variable<String>(trustLevel);
    map['enabled'] = Variable<int>(enabled);
    map['file_path'] = Variable<String>(filePath);
    map['installed_at'] = Variable<DateTime>(installedAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || previousVersionPath != null) {
      map['previous_version_path'] = Variable<String>(previousVersionPath);
    }
    if (!nullToAbsent || previousVersion != null) {
      map['previous_version'] = Variable<String>(previousVersion);
    }
    return map;
  }

  ExtensionsCompanion toCompanion(bool nullToAbsent) {
    return ExtensionsCompanion(
      id: Value(id),
      name: Value(name),
      version: Value(version),
      author: Value(author),
      apiVersion: Value(apiVersion),
      contentType: Value(contentType),
      signature: signature == null && nullToAbsent
          ? const Value.absent()
          : Value(signature),
      trustLevel: Value(trustLevel),
      enabled: Value(enabled),
      filePath: Value(filePath),
      installedAt: Value(installedAt),
      updatedAt: Value(updatedAt),
      previousVersionPath: previousVersionPath == null && nullToAbsent
          ? const Value.absent()
          : Value(previousVersionPath),
      previousVersion: previousVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(previousVersion),
    );
  }

  factory Extension.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Extension(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      version: serializer.fromJson<String>(json['version']),
      author: serializer.fromJson<String>(json['author']),
      apiVersion: serializer.fromJson<int>(json['apiVersion']),
      contentType: serializer.fromJson<String>(json['contentType']),
      signature: serializer.fromJson<String?>(json['signature']),
      trustLevel: serializer.fromJson<String>(json['trustLevel']),
      enabled: serializer.fromJson<int>(json['enabled']),
      filePath: serializer.fromJson<String>(json['filePath']),
      installedAt: serializer.fromJson<DateTime>(json['installedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      previousVersionPath: serializer.fromJson<String?>(
        json['previousVersionPath'],
      ),
      previousVersion: serializer.fromJson<String?>(json['previousVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'version': serializer.toJson<String>(version),
      'author': serializer.toJson<String>(author),
      'apiVersion': serializer.toJson<int>(apiVersion),
      'contentType': serializer.toJson<String>(contentType),
      'signature': serializer.toJson<String?>(signature),
      'trustLevel': serializer.toJson<String>(trustLevel),
      'enabled': serializer.toJson<int>(enabled),
      'filePath': serializer.toJson<String>(filePath),
      'installedAt': serializer.toJson<DateTime>(installedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'previousVersionPath': serializer.toJson<String?>(previousVersionPath),
      'previousVersion': serializer.toJson<String?>(previousVersion),
    };
  }

  Extension copyWith({
    String? id,
    String? name,
    String? version,
    String? author,
    int? apiVersion,
    String? contentType,
    Value<String?> signature = const Value.absent(),
    String? trustLevel,
    int? enabled,
    String? filePath,
    DateTime? installedAt,
    DateTime? updatedAt,
    Value<String?> previousVersionPath = const Value.absent(),
    Value<String?> previousVersion = const Value.absent(),
  }) => Extension(
    id: id ?? this.id,
    name: name ?? this.name,
    version: version ?? this.version,
    author: author ?? this.author,
    apiVersion: apiVersion ?? this.apiVersion,
    contentType: contentType ?? this.contentType,
    signature: signature.present ? signature.value : this.signature,
    trustLevel: trustLevel ?? this.trustLevel,
    enabled: enabled ?? this.enabled,
    filePath: filePath ?? this.filePath,
    installedAt: installedAt ?? this.installedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    previousVersionPath: previousVersionPath.present
        ? previousVersionPath.value
        : this.previousVersionPath,
    previousVersion: previousVersion.present
        ? previousVersion.value
        : this.previousVersion,
  );
  Extension copyWithCompanion(ExtensionsCompanion data) {
    return Extension(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      version: data.version.present ? data.version.value : this.version,
      author: data.author.present ? data.author.value : this.author,
      apiVersion: data.apiVersion.present
          ? data.apiVersion.value
          : this.apiVersion,
      contentType: data.contentType.present
          ? data.contentType.value
          : this.contentType,
      signature: data.signature.present ? data.signature.value : this.signature,
      trustLevel: data.trustLevel.present
          ? data.trustLevel.value
          : this.trustLevel,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      installedAt: data.installedAt.present
          ? data.installedAt.value
          : this.installedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      previousVersionPath: data.previousVersionPath.present
          ? data.previousVersionPath.value
          : this.previousVersionPath,
      previousVersion: data.previousVersion.present
          ? data.previousVersion.value
          : this.previousVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Extension(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('version: $version, ')
          ..write('author: $author, ')
          ..write('apiVersion: $apiVersion, ')
          ..write('contentType: $contentType, ')
          ..write('signature: $signature, ')
          ..write('trustLevel: $trustLevel, ')
          ..write('enabled: $enabled, ')
          ..write('filePath: $filePath, ')
          ..write('installedAt: $installedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('previousVersionPath: $previousVersionPath, ')
          ..write('previousVersion: $previousVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    version,
    author,
    apiVersion,
    contentType,
    signature,
    trustLevel,
    enabled,
    filePath,
    installedAt,
    updatedAt,
    previousVersionPath,
    previousVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Extension &&
          other.id == this.id &&
          other.name == this.name &&
          other.version == this.version &&
          other.author == this.author &&
          other.apiVersion == this.apiVersion &&
          other.contentType == this.contentType &&
          other.signature == this.signature &&
          other.trustLevel == this.trustLevel &&
          other.enabled == this.enabled &&
          other.filePath == this.filePath &&
          other.installedAt == this.installedAt &&
          other.updatedAt == this.updatedAt &&
          other.previousVersionPath == this.previousVersionPath &&
          other.previousVersion == this.previousVersion);
}

class ExtensionsCompanion extends UpdateCompanion<Extension> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> version;
  final Value<String> author;
  final Value<int> apiVersion;
  final Value<String> contentType;
  final Value<String?> signature;
  final Value<String> trustLevel;
  final Value<int> enabled;
  final Value<String> filePath;
  final Value<DateTime> installedAt;
  final Value<DateTime> updatedAt;
  final Value<String?> previousVersionPath;
  final Value<String?> previousVersion;
  final Value<int> rowid;
  const ExtensionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.version = const Value.absent(),
    this.author = const Value.absent(),
    this.apiVersion = const Value.absent(),
    this.contentType = const Value.absent(),
    this.signature = const Value.absent(),
    this.trustLevel = const Value.absent(),
    this.enabled = const Value.absent(),
    this.filePath = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.previousVersionPath = const Value.absent(),
    this.previousVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExtensionsCompanion.insert({
    required String id,
    required String name,
    required String version,
    required String author,
    required int apiVersion,
    required String contentType,
    this.signature = const Value.absent(),
    required String trustLevel,
    this.enabled = const Value.absent(),
    required String filePath,
    this.installedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.previousVersionPath = const Value.absent(),
    this.previousVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       version = Value(version),
       author = Value(author),
       apiVersion = Value(apiVersion),
       contentType = Value(contentType),
       trustLevel = Value(trustLevel),
       filePath = Value(filePath);
  static Insertable<Extension> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? version,
    Expression<String>? author,
    Expression<int>? apiVersion,
    Expression<String>? contentType,
    Expression<String>? signature,
    Expression<String>? trustLevel,
    Expression<int>? enabled,
    Expression<String>? filePath,
    Expression<DateTime>? installedAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? previousVersionPath,
    Expression<String>? previousVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (version != null) 'version': version,
      if (author != null) 'author': author,
      if (apiVersion != null) 'api_version': apiVersion,
      if (contentType != null) 'content_type': contentType,
      if (signature != null) 'signature': signature,
      if (trustLevel != null) 'trust_level': trustLevel,
      if (enabled != null) 'enabled': enabled,
      if (filePath != null) 'file_path': filePath,
      if (installedAt != null) 'installed_at': installedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (previousVersionPath != null)
        'previous_version_path': previousVersionPath,
      if (previousVersion != null) 'previous_version': previousVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExtensionsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? version,
    Value<String>? author,
    Value<int>? apiVersion,
    Value<String>? contentType,
    Value<String?>? signature,
    Value<String>? trustLevel,
    Value<int>? enabled,
    Value<String>? filePath,
    Value<DateTime>? installedAt,
    Value<DateTime>? updatedAt,
    Value<String?>? previousVersionPath,
    Value<String?>? previousVersion,
    Value<int>? rowid,
  }) {
    return ExtensionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      author: author ?? this.author,
      apiVersion: apiVersion ?? this.apiVersion,
      contentType: contentType ?? this.contentType,
      signature: signature ?? this.signature,
      trustLevel: trustLevel ?? this.trustLevel,
      enabled: enabled ?? this.enabled,
      filePath: filePath ?? this.filePath,
      installedAt: installedAt ?? this.installedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      previousVersionPath: previousVersionPath ?? this.previousVersionPath,
      previousVersion: previousVersion ?? this.previousVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (apiVersion.present) {
      map['api_version'] = Variable<int>(apiVersion.value);
    }
    if (contentType.present) {
      map['content_type'] = Variable<String>(contentType.value);
    }
    if (signature.present) {
      map['signature'] = Variable<String>(signature.value);
    }
    if (trustLevel.present) {
      map['trust_level'] = Variable<String>(trustLevel.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<int>(enabled.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (installedAt.present) {
      map['installed_at'] = Variable<DateTime>(installedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (previousVersionPath.present) {
      map['previous_version_path'] = Variable<String>(
        previousVersionPath.value,
      );
    }
    if (previousVersion.present) {
      map['previous_version'] = Variable<String>(previousVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExtensionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('version: $version, ')
          ..write('author: $author, ')
          ..write('apiVersion: $apiVersion, ')
          ..write('contentType: $contentType, ')
          ..write('signature: $signature, ')
          ..write('trustLevel: $trustLevel, ')
          ..write('enabled: $enabled, ')
          ..write('filePath: $filePath, ')
          ..write('installedAt: $installedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('previousVersionPath: $previousVersionPath, ')
          ..write('previousVersion: $previousVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExtensionVersionsTable extends ExtensionVersions
    with TableInfo<$ExtensionVersionsTable, ExtensionVersion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExtensionVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _extensionIdMeta = const VerificationMeta(
    'extensionId',
  );
  @override
  late final GeneratedColumn<String> extensionId = GeneratedColumn<String>(
    'extension_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES extensions (id)',
    ),
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isCurrentMeta = const VerificationMeta(
    'isCurrent',
  );
  @override
  late final GeneratedColumn<int> isCurrent = GeneratedColumn<int>(
    'is_current',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isRollbackPointMeta = const VerificationMeta(
    'isRollbackPoint',
  );
  @override
  late final GeneratedColumn<int> isRollbackPoint = GeneratedColumn<int>(
    'is_rollback_point',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    extensionId,
    version,
    filePath,
    isCurrent,
    isRollbackPoint,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'extension_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExtensionVersion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('extension_id')) {
      context.handle(
        _extensionIdMeta,
        extensionId.isAcceptableOrUnknown(
          data['extension_id']!,
          _extensionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_extensionIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('is_current')) {
      context.handle(
        _isCurrentMeta,
        isCurrent.isAcceptableOrUnknown(data['is_current']!, _isCurrentMeta),
      );
    }
    if (data.containsKey('is_rollback_point')) {
      context.handle(
        _isRollbackPointMeta,
        isRollbackPoint.isAcceptableOrUnknown(
          data['is_rollback_point']!,
          _isRollbackPointMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExtensionVersion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExtensionVersion(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      extensionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extension_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      isCurrent: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_current'],
      )!,
      isRollbackPoint: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_rollback_point'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ExtensionVersionsTable createAlias(String alias) {
    return $ExtensionVersionsTable(attachedDatabase, alias);
  }
}

class ExtensionVersion extends DataClass
    implements Insertable<ExtensionVersion> {
  final String id;

  /// References [Extensions.id].
  final String extensionId;
  final String version;

  /// File path of this version's extension `.js` file.
  final String filePath;

  /// Whether this is the currently active version.
  final int isCurrent;

  /// Whether this version passed health checks (known-good).
  final int isRollbackPoint;
  final DateTime createdAt;
  const ExtensionVersion({
    required this.id,
    required this.extensionId,
    required this.version,
    required this.filePath,
    required this.isCurrent,
    required this.isRollbackPoint,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['extension_id'] = Variable<String>(extensionId);
    map['version'] = Variable<String>(version);
    map['file_path'] = Variable<String>(filePath);
    map['is_current'] = Variable<int>(isCurrent);
    map['is_rollback_point'] = Variable<int>(isRollbackPoint);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ExtensionVersionsCompanion toCompanion(bool nullToAbsent) {
    return ExtensionVersionsCompanion(
      id: Value(id),
      extensionId: Value(extensionId),
      version: Value(version),
      filePath: Value(filePath),
      isCurrent: Value(isCurrent),
      isRollbackPoint: Value(isRollbackPoint),
      createdAt: Value(createdAt),
    );
  }

  factory ExtensionVersion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExtensionVersion(
      id: serializer.fromJson<String>(json['id']),
      extensionId: serializer.fromJson<String>(json['extensionId']),
      version: serializer.fromJson<String>(json['version']),
      filePath: serializer.fromJson<String>(json['filePath']),
      isCurrent: serializer.fromJson<int>(json['isCurrent']),
      isRollbackPoint: serializer.fromJson<int>(json['isRollbackPoint']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'extensionId': serializer.toJson<String>(extensionId),
      'version': serializer.toJson<String>(version),
      'filePath': serializer.toJson<String>(filePath),
      'isCurrent': serializer.toJson<int>(isCurrent),
      'isRollbackPoint': serializer.toJson<int>(isRollbackPoint),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ExtensionVersion copyWith({
    String? id,
    String? extensionId,
    String? version,
    String? filePath,
    int? isCurrent,
    int? isRollbackPoint,
    DateTime? createdAt,
  }) => ExtensionVersion(
    id: id ?? this.id,
    extensionId: extensionId ?? this.extensionId,
    version: version ?? this.version,
    filePath: filePath ?? this.filePath,
    isCurrent: isCurrent ?? this.isCurrent,
    isRollbackPoint: isRollbackPoint ?? this.isRollbackPoint,
    createdAt: createdAt ?? this.createdAt,
  );
  ExtensionVersion copyWithCompanion(ExtensionVersionsCompanion data) {
    return ExtensionVersion(
      id: data.id.present ? data.id.value : this.id,
      extensionId: data.extensionId.present
          ? data.extensionId.value
          : this.extensionId,
      version: data.version.present ? data.version.value : this.version,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      isCurrent: data.isCurrent.present ? data.isCurrent.value : this.isCurrent,
      isRollbackPoint: data.isRollbackPoint.present
          ? data.isRollbackPoint.value
          : this.isRollbackPoint,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExtensionVersion(')
          ..write('id: $id, ')
          ..write('extensionId: $extensionId, ')
          ..write('version: $version, ')
          ..write('filePath: $filePath, ')
          ..write('isCurrent: $isCurrent, ')
          ..write('isRollbackPoint: $isRollbackPoint, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    extensionId,
    version,
    filePath,
    isCurrent,
    isRollbackPoint,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExtensionVersion &&
          other.id == this.id &&
          other.extensionId == this.extensionId &&
          other.version == this.version &&
          other.filePath == this.filePath &&
          other.isCurrent == this.isCurrent &&
          other.isRollbackPoint == this.isRollbackPoint &&
          other.createdAt == this.createdAt);
}

class ExtensionVersionsCompanion extends UpdateCompanion<ExtensionVersion> {
  final Value<String> id;
  final Value<String> extensionId;
  final Value<String> version;
  final Value<String> filePath;
  final Value<int> isCurrent;
  final Value<int> isRollbackPoint;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ExtensionVersionsCompanion({
    this.id = const Value.absent(),
    this.extensionId = const Value.absent(),
    this.version = const Value.absent(),
    this.filePath = const Value.absent(),
    this.isCurrent = const Value.absent(),
    this.isRollbackPoint = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExtensionVersionsCompanion.insert({
    required String id,
    required String extensionId,
    required String version,
    required String filePath,
    this.isCurrent = const Value.absent(),
    this.isRollbackPoint = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       extensionId = Value(extensionId),
       version = Value(version),
       filePath = Value(filePath);
  static Insertable<ExtensionVersion> custom({
    Expression<String>? id,
    Expression<String>? extensionId,
    Expression<String>? version,
    Expression<String>? filePath,
    Expression<int>? isCurrent,
    Expression<int>? isRollbackPoint,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (extensionId != null) 'extension_id': extensionId,
      if (version != null) 'version': version,
      if (filePath != null) 'file_path': filePath,
      if (isCurrent != null) 'is_current': isCurrent,
      if (isRollbackPoint != null) 'is_rollback_point': isRollbackPoint,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExtensionVersionsCompanion copyWith({
    Value<String>? id,
    Value<String>? extensionId,
    Value<String>? version,
    Value<String>? filePath,
    Value<int>? isCurrent,
    Value<int>? isRollbackPoint,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ExtensionVersionsCompanion(
      id: id ?? this.id,
      extensionId: extensionId ?? this.extensionId,
      version: version ?? this.version,
      filePath: filePath ?? this.filePath,
      isCurrent: isCurrent ?? this.isCurrent,
      isRollbackPoint: isRollbackPoint ?? this.isRollbackPoint,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (extensionId.present) {
      map['extension_id'] = Variable<String>(extensionId.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (isCurrent.present) {
      map['is_current'] = Variable<int>(isCurrent.value);
    }
    if (isRollbackPoint.present) {
      map['is_rollback_point'] = Variable<int>(isRollbackPoint.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExtensionVersionsCompanion(')
          ..write('id: $id, ')
          ..write('extensionId: $extensionId, ')
          ..write('version: $version, ')
          ..write('filePath: $filePath, ')
          ..write('isCurrent: $isCurrent, ')
          ..write('isRollbackPoint: $isRollbackPoint, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExtensionFailureLogsTable extends ExtensionFailureLogs
    with TableInfo<$ExtensionFailureLogsTable, ExtensionFailureLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExtensionFailureLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _extensionIdMeta = const VerificationMeta(
    'extensionId',
  );
  @override
  late final GeneratedColumn<String> extensionId = GeneratedColumn<String>(
    'extension_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES extensions (id)',
    ),
  );
  static const VerificationMeta _failureTypeMeta = const VerificationMeta(
    'failureType',
  );
  @override
  late final GeneratedColumn<String> failureType = GeneratedColumn<String>(
    'failure_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationMeta = const VerificationMeta(
    'operation',
  );
  @override
  late final GeneratedColumn<String> operation = GeneratedColumn<String>(
    'operation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
    'detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: () => DateTime.now(),
  );
  static const VerificationMeta _retryableMeta = const VerificationMeta(
    'retryable',
  );
  @override
  late final GeneratedColumn<int> retryable = GeneratedColumn<int>(
    'retryable',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    extensionId,
    failureType,
    operation,
    message,
    detail,
    timestamp,
    retryable,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'extension_failure_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExtensionFailureLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('extension_id')) {
      context.handle(
        _extensionIdMeta,
        extensionId.isAcceptableOrUnknown(
          data['extension_id']!,
          _extensionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_extensionIdMeta);
    }
    if (data.containsKey('failure_type')) {
      context.handle(
        _failureTypeMeta,
        failureType.isAcceptableOrUnknown(
          data['failure_type']!,
          _failureTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_failureTypeMeta);
    }
    if (data.containsKey('operation')) {
      context.handle(
        _operationMeta,
        operation.isAcceptableOrUnknown(data['operation']!, _operationMeta),
      );
    } else if (isInserting) {
      context.missing(_operationMeta);
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    } else if (isInserting) {
      context.missing(_messageMeta);
    }
    if (data.containsKey('detail')) {
      context.handle(
        _detailMeta,
        detail.isAcceptableOrUnknown(data['detail']!, _detailMeta),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    }
    if (data.containsKey('retryable')) {
      context.handle(
        _retryableMeta,
        retryable.isAcceptableOrUnknown(data['retryable']!, _retryableMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExtensionFailureLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExtensionFailureLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      extensionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extension_id'],
      )!,
      failureType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}failure_type'],
      )!,
      operation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      )!,
      detail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail'],
      ),
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      retryable: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retryable'],
      )!,
    );
  }

  @override
  $ExtensionFailureLogsTable createAlias(String alias) {
    return $ExtensionFailureLogsTable(attachedDatabase, alias);
  }
}

class ExtensionFailureLog extends DataClass
    implements Insertable<ExtensionFailureLog> {
  final String id;

  /// References [Extensions.id].
  final String extensionId;

  /// The ExtensionFailureType.code that was recorded.
  final String failureType;

  /// The contract operation that failed (search, getSources, ...).
  final String operation;

  /// Human-readable, non-technical summary.
  final String message;

  /// Developer-only diagnostics.  Never rendered on user screens.
  final String? detail;
  final DateTime timestamp;

  /// Whether retrying the same operation can plausibly succeed.
  final int retryable;
  const ExtensionFailureLog({
    required this.id,
    required this.extensionId,
    required this.failureType,
    required this.operation,
    required this.message,
    this.detail,
    required this.timestamp,
    required this.retryable,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['extension_id'] = Variable<String>(extensionId);
    map['failure_type'] = Variable<String>(failureType);
    map['operation'] = Variable<String>(operation);
    map['message'] = Variable<String>(message);
    if (!nullToAbsent || detail != null) {
      map['detail'] = Variable<String>(detail);
    }
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['retryable'] = Variable<int>(retryable);
    return map;
  }

  ExtensionFailureLogsCompanion toCompanion(bool nullToAbsent) {
    return ExtensionFailureLogsCompanion(
      id: Value(id),
      extensionId: Value(extensionId),
      failureType: Value(failureType),
      operation: Value(operation),
      message: Value(message),
      detail: detail == null && nullToAbsent
          ? const Value.absent()
          : Value(detail),
      timestamp: Value(timestamp),
      retryable: Value(retryable),
    );
  }

  factory ExtensionFailureLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExtensionFailureLog(
      id: serializer.fromJson<String>(json['id']),
      extensionId: serializer.fromJson<String>(json['extensionId']),
      failureType: serializer.fromJson<String>(json['failureType']),
      operation: serializer.fromJson<String>(json['operation']),
      message: serializer.fromJson<String>(json['message']),
      detail: serializer.fromJson<String?>(json['detail']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      retryable: serializer.fromJson<int>(json['retryable']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'extensionId': serializer.toJson<String>(extensionId),
      'failureType': serializer.toJson<String>(failureType),
      'operation': serializer.toJson<String>(operation),
      'message': serializer.toJson<String>(message),
      'detail': serializer.toJson<String?>(detail),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'retryable': serializer.toJson<int>(retryable),
    };
  }

  ExtensionFailureLog copyWith({
    String? id,
    String? extensionId,
    String? failureType,
    String? operation,
    String? message,
    Value<String?> detail = const Value.absent(),
    DateTime? timestamp,
    int? retryable,
  }) => ExtensionFailureLog(
    id: id ?? this.id,
    extensionId: extensionId ?? this.extensionId,
    failureType: failureType ?? this.failureType,
    operation: operation ?? this.operation,
    message: message ?? this.message,
    detail: detail.present ? detail.value : this.detail,
    timestamp: timestamp ?? this.timestamp,
    retryable: retryable ?? this.retryable,
  );
  ExtensionFailureLog copyWithCompanion(ExtensionFailureLogsCompanion data) {
    return ExtensionFailureLog(
      id: data.id.present ? data.id.value : this.id,
      extensionId: data.extensionId.present
          ? data.extensionId.value
          : this.extensionId,
      failureType: data.failureType.present
          ? data.failureType.value
          : this.failureType,
      operation: data.operation.present ? data.operation.value : this.operation,
      message: data.message.present ? data.message.value : this.message,
      detail: data.detail.present ? data.detail.value : this.detail,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      retryable: data.retryable.present ? data.retryable.value : this.retryable,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExtensionFailureLog(')
          ..write('id: $id, ')
          ..write('extensionId: $extensionId, ')
          ..write('failureType: $failureType, ')
          ..write('operation: $operation, ')
          ..write('message: $message, ')
          ..write('detail: $detail, ')
          ..write('timestamp: $timestamp, ')
          ..write('retryable: $retryable')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    extensionId,
    failureType,
    operation,
    message,
    detail,
    timestamp,
    retryable,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExtensionFailureLog &&
          other.id == this.id &&
          other.extensionId == this.extensionId &&
          other.failureType == this.failureType &&
          other.operation == this.operation &&
          other.message == this.message &&
          other.detail == this.detail &&
          other.timestamp == this.timestamp &&
          other.retryable == this.retryable);
}

class ExtensionFailureLogsCompanion
    extends UpdateCompanion<ExtensionFailureLog> {
  final Value<String> id;
  final Value<String> extensionId;
  final Value<String> failureType;
  final Value<String> operation;
  final Value<String> message;
  final Value<String?> detail;
  final Value<DateTime> timestamp;
  final Value<int> retryable;
  final Value<int> rowid;
  const ExtensionFailureLogsCompanion({
    this.id = const Value.absent(),
    this.extensionId = const Value.absent(),
    this.failureType = const Value.absent(),
    this.operation = const Value.absent(),
    this.message = const Value.absent(),
    this.detail = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.retryable = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExtensionFailureLogsCompanion.insert({
    required String id,
    required String extensionId,
    required String failureType,
    required String operation,
    required String message,
    this.detail = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.retryable = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       extensionId = Value(extensionId),
       failureType = Value(failureType),
       operation = Value(operation),
       message = Value(message);
  static Insertable<ExtensionFailureLog> custom({
    Expression<String>? id,
    Expression<String>? extensionId,
    Expression<String>? failureType,
    Expression<String>? operation,
    Expression<String>? message,
    Expression<String>? detail,
    Expression<DateTime>? timestamp,
    Expression<int>? retryable,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (extensionId != null) 'extension_id': extensionId,
      if (failureType != null) 'failure_type': failureType,
      if (operation != null) 'operation': operation,
      if (message != null) 'message': message,
      if (detail != null) 'detail': detail,
      if (timestamp != null) 'timestamp': timestamp,
      if (retryable != null) 'retryable': retryable,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExtensionFailureLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? extensionId,
    Value<String>? failureType,
    Value<String>? operation,
    Value<String>? message,
    Value<String?>? detail,
    Value<DateTime>? timestamp,
    Value<int>? retryable,
    Value<int>? rowid,
  }) {
    return ExtensionFailureLogsCompanion(
      id: id ?? this.id,
      extensionId: extensionId ?? this.extensionId,
      failureType: failureType ?? this.failureType,
      operation: operation ?? this.operation,
      message: message ?? this.message,
      detail: detail ?? this.detail,
      timestamp: timestamp ?? this.timestamp,
      retryable: retryable ?? this.retryable,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (extensionId.present) {
      map['extension_id'] = Variable<String>(extensionId.value);
    }
    if (failureType.present) {
      map['failure_type'] = Variable<String>(failureType.value);
    }
    if (operation.present) {
      map['operation'] = Variable<String>(operation.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (retryable.present) {
      map['retryable'] = Variable<int>(retryable.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExtensionFailureLogsCompanion(')
          ..write('id: $id, ')
          ..write('extensionId: $extensionId, ')
          ..write('failureType: $failureType, ')
          ..write('operation: $operation, ')
          ..write('message: $message, ')
          ..write('detail: $detail, ')
          ..write('timestamp: $timestamp, ')
          ..write('retryable: $retryable, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WatchProgressEntriesTable extends WatchProgressEntries
    with TableInfo<$WatchProgressEntriesTable, WatchProgressRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchProgressEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaKeyMeta = const VerificationMeta(
    'mediaKey',
  );
  @override
  late final GeneratedColumn<String> mediaKey = GeneratedColumn<String>(
    'media_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaTypeMeta = const VerificationMeta(
    'mediaType',
  );
  @override
  late final GeneratedColumn<String> mediaType = GeneratedColumn<String>(
    'media_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subtitleLineMeta = const VerificationMeta(
    'subtitleLine',
  );
  @override
  late final GeneratedColumn<String> subtitleLine = GeneratedColumn<String>(
    'subtitle_line',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seasonNumberMeta = const VerificationMeta(
    'seasonNumber',
  );
  @override
  late final GeneratedColumn<int> seasonNumber = GeneratedColumn<int>(
    'season_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _episodeNumberMeta = const VerificationMeta(
    'episodeNumber',
  );
  @override
  late final GeneratedColumn<int> episodeNumber = GeneratedColumn<int>(
    'episode_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _elapsedMsMeta = const VerificationMeta(
    'elapsedMs',
  );
  @override
  late final GeneratedColumn<int> elapsedMs = GeneratedColumn<int>(
    'elapsed_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<int> completed = GeneratedColumn<int>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mediaKey,
    mediaType,
    title,
    subtitleLine,
    seasonNumber,
    episodeNumber,
    positionMs,
    durationMs,
    elapsedMs,
    completed,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watch_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<WatchProgressRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('media_key')) {
      context.handle(
        _mediaKeyMeta,
        mediaKey.isAcceptableOrUnknown(data['media_key']!, _mediaKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaKeyMeta);
    }
    if (data.containsKey('media_type')) {
      context.handle(
        _mediaTypeMeta,
        mediaType.isAcceptableOrUnknown(data['media_type']!, _mediaTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaTypeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('subtitle_line')) {
      context.handle(
        _subtitleLineMeta,
        subtitleLine.isAcceptableOrUnknown(
          data['subtitle_line']!,
          _subtitleLineMeta,
        ),
      );
    }
    if (data.containsKey('season_number')) {
      context.handle(
        _seasonNumberMeta,
        seasonNumber.isAcceptableOrUnknown(
          data['season_number']!,
          _seasonNumberMeta,
        ),
      );
    }
    if (data.containsKey('episode_number')) {
      context.handle(
        _episodeNumberMeta,
        episodeNumber.isAcceptableOrUnknown(
          data['episode_number']!,
          _episodeNumberMeta,
        ),
      );
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('elapsed_ms')) {
      context.handle(
        _elapsedMsMeta,
        elapsedMs.isAcceptableOrUnknown(data['elapsed_ms']!, _elapsedMsMeta),
      );
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WatchProgressRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchProgressRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      mediaKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_key'],
      )!,
      mediaType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_type'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      subtitleLine: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subtitle_line'],
      ),
      seasonNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season_number'],
      ),
      episodeNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_number'],
      ),
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      elapsedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}elapsed_ms'],
      )!,
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WatchProgressEntriesTable createAlias(String alias) {
    return $WatchProgressEntriesTable(attachedDatabase, alias);
  }
}

class WatchProgressRow extends DataClass
    implements Insertable<WatchProgressRow> {
  /// Stable playback identity (see the class comment). Primary key.
  final String id;

  /// The parent work's canonical 2C metadata key (normalized title|type|year).
  final String mediaKey;

  /// `MediaType.code` from the extension contract: `movie` or `series`.
  final String mediaType;

  /// Display title as the player knew it. Never a provider URL or extension id.
  final String title;

  /// Optional second display line, e.g. `Season 1 · Episode 2`.
  final String? subtitleLine;

  /// Season / episode numbers for a series episode; null for a movie.
  final int? seasonNumber;
  final int? episodeNumber;

  /// Last observed playback position.
  final int positionMs;

  /// Total media duration when the engine reported one.
  final int? durationMs;

  /// Accumulated watch time the player measured this session.
  final int elapsedMs;

  /// 0/1 — the player reported playback reached the end.
  final int completed;

  /// Last time the player reported progress for this identity.
  final DateTime updatedAt;
  const WatchProgressRow({
    required this.id,
    required this.mediaKey,
    required this.mediaType,
    required this.title,
    this.subtitleLine,
    this.seasonNumber,
    this.episodeNumber,
    required this.positionMs,
    this.durationMs,
    required this.elapsedMs,
    required this.completed,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['media_key'] = Variable<String>(mediaKey);
    map['media_type'] = Variable<String>(mediaType);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || subtitleLine != null) {
      map['subtitle_line'] = Variable<String>(subtitleLine);
    }
    if (!nullToAbsent || seasonNumber != null) {
      map['season_number'] = Variable<int>(seasonNumber);
    }
    if (!nullToAbsent || episodeNumber != null) {
      map['episode_number'] = Variable<int>(episodeNumber);
    }
    map['position_ms'] = Variable<int>(positionMs);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['elapsed_ms'] = Variable<int>(elapsedMs);
    map['completed'] = Variable<int>(completed);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  WatchProgressEntriesCompanion toCompanion(bool nullToAbsent) {
    return WatchProgressEntriesCompanion(
      id: Value(id),
      mediaKey: Value(mediaKey),
      mediaType: Value(mediaType),
      title: Value(title),
      subtitleLine: subtitleLine == null && nullToAbsent
          ? const Value.absent()
          : Value(subtitleLine),
      seasonNumber: seasonNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(seasonNumber),
      episodeNumber: episodeNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeNumber),
      positionMs: Value(positionMs),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      elapsedMs: Value(elapsedMs),
      completed: Value(completed),
      updatedAt: Value(updatedAt),
    );
  }

  factory WatchProgressRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchProgressRow(
      id: serializer.fromJson<String>(json['id']),
      mediaKey: serializer.fromJson<String>(json['mediaKey']),
      mediaType: serializer.fromJson<String>(json['mediaType']),
      title: serializer.fromJson<String>(json['title']),
      subtitleLine: serializer.fromJson<String?>(json['subtitleLine']),
      seasonNumber: serializer.fromJson<int?>(json['seasonNumber']),
      episodeNumber: serializer.fromJson<int?>(json['episodeNumber']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      elapsedMs: serializer.fromJson<int>(json['elapsedMs']),
      completed: serializer.fromJson<int>(json['completed']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'mediaKey': serializer.toJson<String>(mediaKey),
      'mediaType': serializer.toJson<String>(mediaType),
      'title': serializer.toJson<String>(title),
      'subtitleLine': serializer.toJson<String?>(subtitleLine),
      'seasonNumber': serializer.toJson<int?>(seasonNumber),
      'episodeNumber': serializer.toJson<int?>(episodeNumber),
      'positionMs': serializer.toJson<int>(positionMs),
      'durationMs': serializer.toJson<int?>(durationMs),
      'elapsedMs': serializer.toJson<int>(elapsedMs),
      'completed': serializer.toJson<int>(completed),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  WatchProgressRow copyWith({
    String? id,
    String? mediaKey,
    String? mediaType,
    String? title,
    Value<String?> subtitleLine = const Value.absent(),
    Value<int?> seasonNumber = const Value.absent(),
    Value<int?> episodeNumber = const Value.absent(),
    int? positionMs,
    Value<int?> durationMs = const Value.absent(),
    int? elapsedMs,
    int? completed,
    DateTime? updatedAt,
  }) => WatchProgressRow(
    id: id ?? this.id,
    mediaKey: mediaKey ?? this.mediaKey,
    mediaType: mediaType ?? this.mediaType,
    title: title ?? this.title,
    subtitleLine: subtitleLine.present ? subtitleLine.value : this.subtitleLine,
    seasonNumber: seasonNumber.present ? seasonNumber.value : this.seasonNumber,
    episodeNumber: episodeNumber.present
        ? episodeNumber.value
        : this.episodeNumber,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    completed: completed ?? this.completed,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WatchProgressRow copyWithCompanion(WatchProgressEntriesCompanion data) {
    return WatchProgressRow(
      id: data.id.present ? data.id.value : this.id,
      mediaKey: data.mediaKey.present ? data.mediaKey.value : this.mediaKey,
      mediaType: data.mediaType.present ? data.mediaType.value : this.mediaType,
      title: data.title.present ? data.title.value : this.title,
      subtitleLine: data.subtitleLine.present
          ? data.subtitleLine.value
          : this.subtitleLine,
      seasonNumber: data.seasonNumber.present
          ? data.seasonNumber.value
          : this.seasonNumber,
      episodeNumber: data.episodeNumber.present
          ? data.episodeNumber.value
          : this.episodeNumber,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      elapsedMs: data.elapsedMs.present ? data.elapsedMs.value : this.elapsedMs,
      completed: data.completed.present ? data.completed.value : this.completed,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchProgressRow(')
          ..write('id: $id, ')
          ..write('mediaKey: $mediaKey, ')
          ..write('mediaType: $mediaType, ')
          ..write('title: $title, ')
          ..write('subtitleLine: $subtitleLine, ')
          ..write('seasonNumber: $seasonNumber, ')
          ..write('episodeNumber: $episodeNumber, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('elapsedMs: $elapsedMs, ')
          ..write('completed: $completed, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    mediaKey,
    mediaType,
    title,
    subtitleLine,
    seasonNumber,
    episodeNumber,
    positionMs,
    durationMs,
    elapsedMs,
    completed,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchProgressRow &&
          other.id == this.id &&
          other.mediaKey == this.mediaKey &&
          other.mediaType == this.mediaType &&
          other.title == this.title &&
          other.subtitleLine == this.subtitleLine &&
          other.seasonNumber == this.seasonNumber &&
          other.episodeNumber == this.episodeNumber &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.elapsedMs == this.elapsedMs &&
          other.completed == this.completed &&
          other.updatedAt == this.updatedAt);
}

class WatchProgressEntriesCompanion extends UpdateCompanion<WatchProgressRow> {
  final Value<String> id;
  final Value<String> mediaKey;
  final Value<String> mediaType;
  final Value<String> title;
  final Value<String?> subtitleLine;
  final Value<int?> seasonNumber;
  final Value<int?> episodeNumber;
  final Value<int> positionMs;
  final Value<int?> durationMs;
  final Value<int> elapsedMs;
  final Value<int> completed;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const WatchProgressEntriesCompanion({
    this.id = const Value.absent(),
    this.mediaKey = const Value.absent(),
    this.mediaType = const Value.absent(),
    this.title = const Value.absent(),
    this.subtitleLine = const Value.absent(),
    this.seasonNumber = const Value.absent(),
    this.episodeNumber = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.elapsedMs = const Value.absent(),
    this.completed = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchProgressEntriesCompanion.insert({
    required String id,
    required String mediaKey,
    required String mediaType,
    required String title,
    this.subtitleLine = const Value.absent(),
    this.seasonNumber = const Value.absent(),
    this.episodeNumber = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.elapsedMs = const Value.absent(),
    this.completed = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       mediaKey = Value(mediaKey),
       mediaType = Value(mediaType),
       title = Value(title),
       updatedAt = Value(updatedAt);
  static Insertable<WatchProgressRow> custom({
    Expression<String>? id,
    Expression<String>? mediaKey,
    Expression<String>? mediaType,
    Expression<String>? title,
    Expression<String>? subtitleLine,
    Expression<int>? seasonNumber,
    Expression<int>? episodeNumber,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<int>? elapsedMs,
    Expression<int>? completed,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mediaKey != null) 'media_key': mediaKey,
      if (mediaType != null) 'media_type': mediaType,
      if (title != null) 'title': title,
      if (subtitleLine != null) 'subtitle_line': subtitleLine,
      if (seasonNumber != null) 'season_number': seasonNumber,
      if (episodeNumber != null) 'episode_number': episodeNumber,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (elapsedMs != null) 'elapsed_ms': elapsedMs,
      if (completed != null) 'completed': completed,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchProgressEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? mediaKey,
    Value<String>? mediaType,
    Value<String>? title,
    Value<String?>? subtitleLine,
    Value<int?>? seasonNumber,
    Value<int?>? episodeNumber,
    Value<int>? positionMs,
    Value<int?>? durationMs,
    Value<int>? elapsedMs,
    Value<int>? completed,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return WatchProgressEntriesCompanion(
      id: id ?? this.id,
      mediaKey: mediaKey ?? this.mediaKey,
      mediaType: mediaType ?? this.mediaType,
      title: title ?? this.title,
      subtitleLine: subtitleLine ?? this.subtitleLine,
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      completed: completed ?? this.completed,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (mediaKey.present) {
      map['media_key'] = Variable<String>(mediaKey.value);
    }
    if (mediaType.present) {
      map['media_type'] = Variable<String>(mediaType.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (subtitleLine.present) {
      map['subtitle_line'] = Variable<String>(subtitleLine.value);
    }
    if (seasonNumber.present) {
      map['season_number'] = Variable<int>(seasonNumber.value);
    }
    if (episodeNumber.present) {
      map['episode_number'] = Variable<int>(episodeNumber.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (elapsedMs.present) {
      map['elapsed_ms'] = Variable<int>(elapsedMs.value);
    }
    if (completed.present) {
      map['completed'] = Variable<int>(completed.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchProgressEntriesCompanion(')
          ..write('id: $id, ')
          ..write('mediaKey: $mediaKey, ')
          ..write('mediaType: $mediaType, ')
          ..write('title: $title, ')
          ..write('subtitleLine: $subtitleLine, ')
          ..write('seasonNumber: $seasonNumber, ')
          ..write('episodeNumber: $episodeNumber, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('elapsedMs: $elapsedMs, ')
          ..write('completed: $completed, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaReferencesTable extends MediaReferences
    with TableInfo<$MediaReferencesTable, MediaReferenceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaReferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _mediaKeyMeta = const VerificationMeta(
    'mediaKey',
  );
  @override
  late final GeneratedColumn<String> mediaKey = GeneratedColumn<String>(
    'media_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ordinalMeta = const VerificationMeta(
    'ordinal',
  );
  @override
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
    'ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _extensionIdMeta = const VerificationMeta(
    'extensionId',
  );
  @override
  late final GeneratedColumn<String> extensionId = GeneratedColumn<String>(
    'extension_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _referenceUrlMeta = const VerificationMeta(
    'referenceUrl',
  );
  @override
  late final GeneratedColumn<String> referenceUrl = GeneratedColumn<String>(
    'reference_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    mediaKey,
    ordinal,
    extensionId,
    referenceUrl,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_references';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaReferenceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('media_key')) {
      context.handle(
        _mediaKeyMeta,
        mediaKey.isAcceptableOrUnknown(data['media_key']!, _mediaKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaKeyMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(
        _ordinalMeta,
        ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta),
      );
    } else if (isInserting) {
      context.missing(_ordinalMeta);
    }
    if (data.containsKey('extension_id')) {
      context.handle(
        _extensionIdMeta,
        extensionId.isAcceptableOrUnknown(
          data['extension_id']!,
          _extensionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_extensionIdMeta);
    }
    if (data.containsKey('reference_url')) {
      context.handle(
        _referenceUrlMeta,
        referenceUrl.isAcceptableOrUnknown(
          data['reference_url']!,
          _referenceUrlMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_referenceUrlMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {mediaKey, ordinal};
  @override
  MediaReferenceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaReferenceRow(
      mediaKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_key'],
      )!,
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordinal'],
      )!,
      extensionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extension_id'],
      )!,
      referenceUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference_url'],
      )!,
    );
  }

  @override
  $MediaReferencesTable createAlias(String alias) {
    return $MediaReferencesTable(attachedDatabase, alias);
  }
}

class MediaReferenceRow extends DataClass
    implements Insertable<MediaReferenceRow> {
  /// The work's canonical metadata key (the same identity watch progress uses).
  final String mediaKey;

  /// First-seen order, preserved so resume re-queries references in the same
  /// order discovery observed them.
  final int ordinal;

  /// The contributing extension's registry id.
  final String extensionId;

  /// The extension-internal reference the extension expects back through
  /// `details(url)`. Never a playback URL.
  final String referenceUrl;
  const MediaReferenceRow({
    required this.mediaKey,
    required this.ordinal,
    required this.extensionId,
    required this.referenceUrl,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['media_key'] = Variable<String>(mediaKey);
    map['ordinal'] = Variable<int>(ordinal);
    map['extension_id'] = Variable<String>(extensionId);
    map['reference_url'] = Variable<String>(referenceUrl);
    return map;
  }

  MediaReferencesCompanion toCompanion(bool nullToAbsent) {
    return MediaReferencesCompanion(
      mediaKey: Value(mediaKey),
      ordinal: Value(ordinal),
      extensionId: Value(extensionId),
      referenceUrl: Value(referenceUrl),
    );
  }

  factory MediaReferenceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaReferenceRow(
      mediaKey: serializer.fromJson<String>(json['mediaKey']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      extensionId: serializer.fromJson<String>(json['extensionId']),
      referenceUrl: serializer.fromJson<String>(json['referenceUrl']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'mediaKey': serializer.toJson<String>(mediaKey),
      'ordinal': serializer.toJson<int>(ordinal),
      'extensionId': serializer.toJson<String>(extensionId),
      'referenceUrl': serializer.toJson<String>(referenceUrl),
    };
  }

  MediaReferenceRow copyWith({
    String? mediaKey,
    int? ordinal,
    String? extensionId,
    String? referenceUrl,
  }) => MediaReferenceRow(
    mediaKey: mediaKey ?? this.mediaKey,
    ordinal: ordinal ?? this.ordinal,
    extensionId: extensionId ?? this.extensionId,
    referenceUrl: referenceUrl ?? this.referenceUrl,
  );
  MediaReferenceRow copyWithCompanion(MediaReferencesCompanion data) {
    return MediaReferenceRow(
      mediaKey: data.mediaKey.present ? data.mediaKey.value : this.mediaKey,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      extensionId: data.extensionId.present
          ? data.extensionId.value
          : this.extensionId,
      referenceUrl: data.referenceUrl.present
          ? data.referenceUrl.value
          : this.referenceUrl,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaReferenceRow(')
          ..write('mediaKey: $mediaKey, ')
          ..write('ordinal: $ordinal, ')
          ..write('extensionId: $extensionId, ')
          ..write('referenceUrl: $referenceUrl')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(mediaKey, ordinal, extensionId, referenceUrl);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaReferenceRow &&
          other.mediaKey == this.mediaKey &&
          other.ordinal == this.ordinal &&
          other.extensionId == this.extensionId &&
          other.referenceUrl == this.referenceUrl);
}

class MediaReferencesCompanion extends UpdateCompanion<MediaReferenceRow> {
  final Value<String> mediaKey;
  final Value<int> ordinal;
  final Value<String> extensionId;
  final Value<String> referenceUrl;
  final Value<int> rowid;
  const MediaReferencesCompanion({
    this.mediaKey = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.extensionId = const Value.absent(),
    this.referenceUrl = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaReferencesCompanion.insert({
    required String mediaKey,
    required int ordinal,
    required String extensionId,
    required String referenceUrl,
    this.rowid = const Value.absent(),
  }) : mediaKey = Value(mediaKey),
       ordinal = Value(ordinal),
       extensionId = Value(extensionId),
       referenceUrl = Value(referenceUrl);
  static Insertable<MediaReferenceRow> custom({
    Expression<String>? mediaKey,
    Expression<int>? ordinal,
    Expression<String>? extensionId,
    Expression<String>? referenceUrl,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (mediaKey != null) 'media_key': mediaKey,
      if (ordinal != null) 'ordinal': ordinal,
      if (extensionId != null) 'extension_id': extensionId,
      if (referenceUrl != null) 'reference_url': referenceUrl,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaReferencesCompanion copyWith({
    Value<String>? mediaKey,
    Value<int>? ordinal,
    Value<String>? extensionId,
    Value<String>? referenceUrl,
    Value<int>? rowid,
  }) {
    return MediaReferencesCompanion(
      mediaKey: mediaKey ?? this.mediaKey,
      ordinal: ordinal ?? this.ordinal,
      extensionId: extensionId ?? this.extensionId,
      referenceUrl: referenceUrl ?? this.referenceUrl,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (mediaKey.present) {
      map['media_key'] = Variable<String>(mediaKey.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (extensionId.present) {
      map['extension_id'] = Variable<String>(extensionId.value);
    }
    if (referenceUrl.present) {
      map['reference_url'] = Variable<String>(referenceUrl.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaReferencesCompanion(')
          ..write('mediaKey: $mediaKey, ')
          ..write('ordinal: $ordinal, ')
          ..write('extensionId: $extensionId, ')
          ..write('referenceUrl: $referenceUrl, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SpectaDatabase extends GeneratedDatabase {
  _$SpectaDatabase(QueryExecutor e) : super(e);
  $SpectaDatabaseManager get managers => $SpectaDatabaseManager(this);
  late final $SettingsEntriesTable settingsEntries = $SettingsEntriesTable(
    this,
  );
  late final $ExtensionsTable extensions = $ExtensionsTable(this);
  late final $ExtensionVersionsTable extensionVersions =
      $ExtensionVersionsTable(this);
  late final $ExtensionFailureLogsTable extensionFailureLogs =
      $ExtensionFailureLogsTable(this);
  late final $WatchProgressEntriesTable watchProgressEntries =
      $WatchProgressEntriesTable(this);
  late final $MediaReferencesTable mediaReferences = $MediaReferencesTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    settingsEntries,
    extensions,
    extensionVersions,
    extensionFailureLogs,
    watchProgressEntries,
    mediaReferences,
  ];
}

typedef $$SettingsEntriesTableCreateCompanionBuilder =
    SettingsEntriesCompanion Function({
      required String key,
      required String value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$SettingsEntriesTableUpdateCompanionBuilder =
    SettingsEntriesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SettingsEntriesTableFilterComposer
    extends Composer<_$SpectaDatabase, $SettingsEntriesTable> {
  $$SettingsEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsEntriesTableOrderingComposer
    extends Composer<_$SpectaDatabase, $SettingsEntriesTable> {
  $$SettingsEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsEntriesTableAnnotationComposer
    extends Composer<_$SpectaDatabase, $SettingsEntriesTable> {
  $$SettingsEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SettingsEntriesTableTableManager
    extends
        RootTableManager<
          _$SpectaDatabase,
          $SettingsEntriesTable,
          SettingEntry,
          $$SettingsEntriesTableFilterComposer,
          $$SettingsEntriesTableOrderingComposer,
          $$SettingsEntriesTableAnnotationComposer,
          $$SettingsEntriesTableCreateCompanionBuilder,
          $$SettingsEntriesTableUpdateCompanionBuilder,
          (
            SettingEntry,
            BaseReferences<
              _$SpectaDatabase,
              $SettingsEntriesTable,
              SettingEntry
            >,
          ),
          SettingEntry,
          PrefetchHooks Function()
        > {
  $$SettingsEntriesTableTableManager(
    _$SpectaDatabase db,
    $SettingsEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsEntriesCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsEntriesCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsEntriesTable, SettingEntry>(table),
                  BaseReferences<
                    _$SpectaDatabase,
                    $SettingsEntriesTable,
                    SettingEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$SpectaDatabase,
      $SettingsEntriesTable,
      SettingEntry,
      $$SettingsEntriesTableFilterComposer,
      $$SettingsEntriesTableOrderingComposer,
      $$SettingsEntriesTableAnnotationComposer,
      $$SettingsEntriesTableCreateCompanionBuilder,
      $$SettingsEntriesTableUpdateCompanionBuilder,
      (
        SettingEntry,
        BaseReferences<_$SpectaDatabase, $SettingsEntriesTable, SettingEntry>,
      ),
      SettingEntry,
      PrefetchHooks Function()
    >;
typedef $$ExtensionsTableCreateCompanionBuilder = ExtensionsCompanion Function({
  required String id,
  required String name,
  required String version,
  required String author,
  required int apiVersion,
  required String contentType,
  Value<String?> signature,
  required String trustLevel,
  Value<int> enabled,
  required String filePath,
  Value<DateTime> installedAt,
  Value<DateTime> updatedAt,
  Value<String?> previousVersionPath,
  Value<String?> previousVersion,
  Value<int> rowid,
});
typedef $$ExtensionsTableUpdateCompanionBuilder = ExtensionsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> version,
  Value<String> author,
  Value<int> apiVersion,
  Value<String> contentType,
  Value<String?> signature,
  Value<String> trustLevel,
  Value<int> enabled,
  Value<String> filePath,
  Value<DateTime> installedAt,
  Value<DateTime> updatedAt,
  Value<String?> previousVersionPath,
  Value<String?> previousVersion,
  Value<int> rowid,
});

final class $$ExtensionsTableReferences
    extends BaseReferences<_$SpectaDatabase, $ExtensionsTable, Extension> {
  $$ExtensionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ExtensionVersionsTable, List<ExtensionVersion>>
  _extensionVersionsRefsTable(_$SpectaDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.extensionVersions,
        aliasName: 'extensions__id__extension_versions__extension_id',
      );

  $$ExtensionVersionsTableProcessedTableManager get extensionVersionsRefs {
    final manager = $$ExtensionVersionsTableTableManager(
      $_db,
      $_db.extensionVersions,
    ).filter((f) => f.extensionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _extensionVersionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ExtensionFailureLogsTable,
    List<ExtensionFailureLog>
  >
  _extensionFailureLogsRefsTable(_$SpectaDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.extensionFailureLogs,
        aliasName: 'extensions__id__extension_failure_logs__extension_id',
      );

  $$ExtensionFailureLogsTableProcessedTableManager
  get extensionFailureLogsRefs {
    final manager = $$ExtensionFailureLogsTableTableManager(
      $_db,
      $_db.extensionFailureLogs,
    ).filter((f) => f.extensionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _extensionFailureLogsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ExtensionsTableFilterComposer
    extends Composer<_$SpectaDatabase, $ExtensionsTable> {
  $$ExtensionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get apiVersion => $composableBuilder(
    column: $table.apiVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trustLevel => $composableBuilder(
    column: $table.trustLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get previousVersionPath => $composableBuilder(
    column: $table.previousVersionPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get previousVersion => $composableBuilder(
    column: $table.previousVersion,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> extensionVersionsRefs(
    Expression<bool> Function($$ExtensionVersionsTableFilterComposer f) f,
  ) {
    final $$ExtensionVersionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.extensionVersions,
      getReferencedColumn: (t) => t.extensionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExtensionVersionsTableFilterComposer(
            $db: $db,
            $table: $db.extensionVersions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> extensionFailureLogsRefs(
    Expression<bool> Function($$ExtensionFailureLogsTableFilterComposer f) f,
  ) {
    final $$ExtensionFailureLogsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.extensionFailureLogs,
      getReferencedColumn: (t) => t.extensionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExtensionFailureLogsTableFilterComposer(
            $db: $db,
            $table: $db.extensionFailureLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ExtensionsTableOrderingComposer
    extends Composer<_$SpectaDatabase, $ExtensionsTable> {
  $$ExtensionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get apiVersion => $composableBuilder(
    column: $table.apiVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trustLevel => $composableBuilder(
    column: $table.trustLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get previousVersionPath => $composableBuilder(
    column: $table.previousVersionPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get previousVersion => $composableBuilder(
    column: $table.previousVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExtensionsTableAnnotationComposer
    extends Composer<_$SpectaDatabase, $ExtensionsTable> {
  $$ExtensionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<int> get apiVersion => $composableBuilder(
    column: $table.apiVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contentType => $composableBuilder(
    column: $table.contentType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get signature =>
      $composableBuilder(column: $table.signature, builder: (column) => column);

  GeneratedColumn<String> get trustLevel => $composableBuilder(
    column: $table.trustLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get previousVersionPath => $composableBuilder(
    column: $table.previousVersionPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get previousVersion => $composableBuilder(
    column: $table.previousVersion,
    builder: (column) => column,
  );

  Expression<T> extensionVersionsRefs<T extends Object>(
    Expression<T> Function($$ExtensionVersionsTableAnnotationComposer a) f,
  ) {
    final $$ExtensionVersionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.extensionVersions,
          getReferencedColumn: (t) => t.extensionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ExtensionVersionsTableAnnotationComposer(
                $db: $db,
                $table: $db.extensionVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> extensionFailureLogsRefs<T extends Object>(
    Expression<T> Function($$ExtensionFailureLogsTableAnnotationComposer a) f,
  ) {
    final $$ExtensionFailureLogsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.extensionFailureLogs,
          getReferencedColumn: (t) => t.extensionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ExtensionFailureLogsTableAnnotationComposer(
                $db: $db,
                $table: $db.extensionFailureLogs,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ExtensionsTableTableManager
    extends
        RootTableManager<
          _$SpectaDatabase,
          $ExtensionsTable,
          Extension,
          $$ExtensionsTableFilterComposer,
          $$ExtensionsTableOrderingComposer,
          $$ExtensionsTableAnnotationComposer,
          $$ExtensionsTableCreateCompanionBuilder,
          $$ExtensionsTableUpdateCompanionBuilder,
          (Extension, $$ExtensionsTableReferences),
          Extension,
          PrefetchHooks Function({
            bool extensionVersionsRefs,
            bool extensionFailureLogsRefs,
          })
        > {
  $$ExtensionsTableTableManager(_$SpectaDatabase db, $ExtensionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExtensionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExtensionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExtensionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String> author = const Value.absent(),
                Value<int> apiVersion = const Value.absent(),
                Value<String> contentType = const Value.absent(),
                Value<String?> signature = const Value.absent(),
                Value<String> trustLevel = const Value.absent(),
                Value<int> enabled = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<DateTime> installedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> previousVersionPath = const Value.absent(),
                Value<String?> previousVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExtensionsCompanion(
                id: id,
                name: name,
                version: version,
                author: author,
                apiVersion: apiVersion,
                contentType: contentType,
                signature: signature,
                trustLevel: trustLevel,
                enabled: enabled,
                filePath: filePath,
                installedAt: installedAt,
                updatedAt: updatedAt,
                previousVersionPath: previousVersionPath,
                previousVersion: previousVersion,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String version,
                required String author,
                required int apiVersion,
                required String contentType,
                Value<String?> signature = const Value.absent(),
                required String trustLevel,
                Value<int> enabled = const Value.absent(),
                required String filePath,
                Value<DateTime> installedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> previousVersionPath = const Value.absent(),
                Value<String?> previousVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExtensionsCompanion.insert(
                id: id,
                name: name,
                version: version,
                author: author,
                apiVersion: apiVersion,
                contentType: contentType,
                signature: signature,
                trustLevel: trustLevel,
                enabled: enabled,
                filePath: filePath,
                installedAt: installedAt,
                updatedAt: updatedAt,
                previousVersionPath: previousVersionPath,
                previousVersion: previousVersion,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ExtensionsTable, Extension>(table),
                  $$ExtensionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                extensionVersionsRefs = false,
                extensionFailureLogsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (extensionVersionsRefs) db.extensionVersions,
                    if (extensionFailureLogsRefs) db.extensionFailureLogs,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (extensionVersionsRefs)
                        await $_getPrefetchedData<
                          Extension,
                          $ExtensionsTable,
                          ExtensionVersion
                        >(
                          currentTable: table,
                          referencedTable: $$ExtensionsTableReferences
                              ._extensionVersionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ExtensionsTableReferences(
                                db,
                                table,
                                p0,
                              ).extensionVersionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.extensionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (extensionFailureLogsRefs)
                        await $_getPrefetchedData<
                          Extension,
                          $ExtensionsTable,
                          ExtensionFailureLog
                        >(
                          currentTable: table,
                          referencedTable: $$ExtensionsTableReferences
                              ._extensionFailureLogsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ExtensionsTableReferences(
                                db,
                                table,
                                p0,
                              ).extensionFailureLogsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.extensionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ExtensionsTableProcessedTableManager =
    ProcessedTableManager<
      _$SpectaDatabase,
      $ExtensionsTable,
      Extension,
      $$ExtensionsTableFilterComposer,
      $$ExtensionsTableOrderingComposer,
      $$ExtensionsTableAnnotationComposer,
      $$ExtensionsTableCreateCompanionBuilder,
      $$ExtensionsTableUpdateCompanionBuilder,
      (Extension, $$ExtensionsTableReferences),
      Extension,
      PrefetchHooks Function({
        bool extensionVersionsRefs,
        bool extensionFailureLogsRefs,
      })
    >;
typedef $$ExtensionVersionsTableCreateCompanionBuilder =
    ExtensionVersionsCompanion Function({
      required String id,
      required String extensionId,
      required String version,
      required String filePath,
      Value<int> isCurrent,
      Value<int> isRollbackPoint,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$ExtensionVersionsTableUpdateCompanionBuilder =
    ExtensionVersionsCompanion Function({
      Value<String> id,
      Value<String> extensionId,
      Value<String> version,
      Value<String> filePath,
      Value<int> isCurrent,
      Value<int> isRollbackPoint,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$ExtensionVersionsTableReferences
    extends
        BaseReferences<
          _$SpectaDatabase,
          $ExtensionVersionsTable,
          ExtensionVersion
        > {
  $$ExtensionVersionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ExtensionsTable _extensionIdTable(_$SpectaDatabase db) => db
      .extensions
      .createAlias('extension_versions__extension_id__extensions__id');

  $$ExtensionsTableProcessedTableManager get extensionId {
    final $_column = $_itemColumn<String>('extension_id')!;

    final manager = $$ExtensionsTableTableManager(
      $_db,
      $_db.extensions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_extensionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ExtensionVersionsTableFilterComposer
    extends Composer<_$SpectaDatabase, $ExtensionVersionsTable> {
  $$ExtensionVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isCurrent => $composableBuilder(
    column: $table.isCurrent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isRollbackPoint => $composableBuilder(
    column: $table.isRollbackPoint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$ExtensionsTableFilterComposer get extensionId {
    final $$ExtensionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.extensionId,
      referencedTable: $db.extensions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExtensionsTableFilterComposer(
            $db: $db,
            $table: $db.extensions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExtensionVersionsTableOrderingComposer
    extends Composer<_$SpectaDatabase, $ExtensionVersionsTable> {
  $$ExtensionVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isCurrent => $composableBuilder(
    column: $table.isCurrent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isRollbackPoint => $composableBuilder(
    column: $table.isRollbackPoint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$ExtensionsTableOrderingComposer get extensionId {
    final $$ExtensionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.extensionId,
      referencedTable: $db.extensions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExtensionsTableOrderingComposer(
            $db: $db,
            $table: $db.extensions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExtensionVersionsTableAnnotationComposer
    extends Composer<_$SpectaDatabase, $ExtensionVersionsTable> {
  $$ExtensionVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get isCurrent =>
      $composableBuilder(column: $table.isCurrent, builder: (column) => column);

  GeneratedColumn<int> get isRollbackPoint => $composableBuilder(
    column: $table.isRollbackPoint,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ExtensionsTableAnnotationComposer get extensionId {
    final $$ExtensionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.extensionId,
      referencedTable: $db.extensions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExtensionsTableAnnotationComposer(
            $db: $db,
            $table: $db.extensions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExtensionVersionsTableTableManager
    extends
        RootTableManager<
          _$SpectaDatabase,
          $ExtensionVersionsTable,
          ExtensionVersion,
          $$ExtensionVersionsTableFilterComposer,
          $$ExtensionVersionsTableOrderingComposer,
          $$ExtensionVersionsTableAnnotationComposer,
          $$ExtensionVersionsTableCreateCompanionBuilder,
          $$ExtensionVersionsTableUpdateCompanionBuilder,
          (ExtensionVersion, $$ExtensionVersionsTableReferences),
          ExtensionVersion,
          PrefetchHooks Function({bool extensionId})
        > {
  $$ExtensionVersionsTableTableManager(
    _$SpectaDatabase db,
    $ExtensionVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExtensionVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExtensionVersionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExtensionVersionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> extensionId = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<int> isCurrent = const Value.absent(),
                Value<int> isRollbackPoint = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExtensionVersionsCompanion(
                id: id,
                extensionId: extensionId,
                version: version,
                filePath: filePath,
                isCurrent: isCurrent,
                isRollbackPoint: isRollbackPoint,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String extensionId,
                required String version,
                required String filePath,
                Value<int> isCurrent = const Value.absent(),
                Value<int> isRollbackPoint = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExtensionVersionsCompanion.insert(
                id: id,
                extensionId: extensionId,
                version: version,
                filePath: filePath,
                isCurrent: isCurrent,
                isRollbackPoint: isRollbackPoint,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ExtensionVersionsTable, ExtensionVersion>(table),
                  $$ExtensionVersionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({extensionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (extensionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.extensionId,
                        referencedTable: $$ExtensionVersionsTableReferences
                            ._extensionIdTable(db),
                        referencedColumn: $$ExtensionVersionsTableReferences
                            ._extensionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ExtensionVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$SpectaDatabase,
      $ExtensionVersionsTable,
      ExtensionVersion,
      $$ExtensionVersionsTableFilterComposer,
      $$ExtensionVersionsTableOrderingComposer,
      $$ExtensionVersionsTableAnnotationComposer,
      $$ExtensionVersionsTableCreateCompanionBuilder,
      $$ExtensionVersionsTableUpdateCompanionBuilder,
      (ExtensionVersion, $$ExtensionVersionsTableReferences),
      ExtensionVersion,
      PrefetchHooks Function({bool extensionId})
    >;
typedef $$ExtensionFailureLogsTableCreateCompanionBuilder =
    ExtensionFailureLogsCompanion Function({
      required String id,
      required String extensionId,
      required String failureType,
      required String operation,
      required String message,
      Value<String?> detail,
      Value<DateTime> timestamp,
      Value<int> retryable,
      Value<int> rowid,
    });
typedef $$ExtensionFailureLogsTableUpdateCompanionBuilder =
    ExtensionFailureLogsCompanion Function({
      Value<String> id,
      Value<String> extensionId,
      Value<String> failureType,
      Value<String> operation,
      Value<String> message,
      Value<String?> detail,
      Value<DateTime> timestamp,
      Value<int> retryable,
      Value<int> rowid,
    });

final class $$ExtensionFailureLogsTableReferences
    extends
        BaseReferences<
          _$SpectaDatabase,
          $ExtensionFailureLogsTable,
          ExtensionFailureLog
        > {
  $$ExtensionFailureLogsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ExtensionsTable _extensionIdTable(_$SpectaDatabase db) => db
      .extensions
      .createAlias('extension_failure_logs__extension_id__extensions__id');

  $$ExtensionsTableProcessedTableManager get extensionId {
    final $_column = $_itemColumn<String>('extension_id')!;

    final manager = $$ExtensionsTableTableManager(
      $_db,
      $_db.extensions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_extensionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ExtensionFailureLogsTableFilterComposer
    extends Composer<_$SpectaDatabase, $ExtensionFailureLogsTable> {
  $$ExtensionFailureLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get failureType => $composableBuilder(
    column: $table.failureType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryable => $composableBuilder(
    column: $table.retryable,
    builder: (column) => ColumnFilters(column),
  );

  $$ExtensionsTableFilterComposer get extensionId {
    final $$ExtensionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.extensionId,
      referencedTable: $db.extensions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExtensionsTableFilterComposer(
            $db: $db,
            $table: $db.extensions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExtensionFailureLogsTableOrderingComposer
    extends Composer<_$SpectaDatabase, $ExtensionFailureLogsTable> {
  $$ExtensionFailureLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get failureType => $composableBuilder(
    column: $table.failureType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operation => $composableBuilder(
    column: $table.operation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryable => $composableBuilder(
    column: $table.retryable,
    builder: (column) => ColumnOrderings(column),
  );

  $$ExtensionsTableOrderingComposer get extensionId {
    final $$ExtensionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.extensionId,
      referencedTable: $db.extensions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExtensionsTableOrderingComposer(
            $db: $db,
            $table: $db.extensions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExtensionFailureLogsTableAnnotationComposer
    extends Composer<_$SpectaDatabase, $ExtensionFailureLogsTable> {
  $$ExtensionFailureLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get failureType => $composableBuilder(
    column: $table.failureType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get operation =>
      $composableBuilder(column: $table.operation, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get retryable =>
      $composableBuilder(column: $table.retryable, builder: (column) => column);

  $$ExtensionsTableAnnotationComposer get extensionId {
    final $$ExtensionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.extensionId,
      referencedTable: $db.extensions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExtensionsTableAnnotationComposer(
            $db: $db,
            $table: $db.extensions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExtensionFailureLogsTableTableManager
    extends
        RootTableManager<
          _$SpectaDatabase,
          $ExtensionFailureLogsTable,
          ExtensionFailureLog,
          $$ExtensionFailureLogsTableFilterComposer,
          $$ExtensionFailureLogsTableOrderingComposer,
          $$ExtensionFailureLogsTableAnnotationComposer,
          $$ExtensionFailureLogsTableCreateCompanionBuilder,
          $$ExtensionFailureLogsTableUpdateCompanionBuilder,
          (ExtensionFailureLog, $$ExtensionFailureLogsTableReferences),
          ExtensionFailureLog,
          PrefetchHooks Function({bool extensionId})
        > {
  $$ExtensionFailureLogsTableTableManager(
    _$SpectaDatabase db,
    $ExtensionFailureLogsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExtensionFailureLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExtensionFailureLogsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ExtensionFailureLogsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> extensionId = const Value.absent(),
                Value<String> failureType = const Value.absent(),
                Value<String> operation = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<String?> detail = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<int> retryable = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExtensionFailureLogsCompanion(
                id: id,
                extensionId: extensionId,
                failureType: failureType,
                operation: operation,
                message: message,
                detail: detail,
                timestamp: timestamp,
                retryable: retryable,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String extensionId,
                required String failureType,
                required String operation,
                required String message,
                Value<String?> detail = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<int> retryable = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExtensionFailureLogsCompanion.insert(
                id: id,
                extensionId: extensionId,
                failureType: failureType,
                operation: operation,
                message: message,
                detail: detail,
                timestamp: timestamp,
                retryable: retryable,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ExtensionFailureLogsTable, ExtensionFailureLog>(
                    table,
                  ),
                  $$ExtensionFailureLogsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({extensionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (extensionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.extensionId,
                        referencedTable: $$ExtensionFailureLogsTableReferences
                            ._extensionIdTable(db),
                        referencedColumn: $$ExtensionFailureLogsTableReferences
                            ._extensionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ExtensionFailureLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$SpectaDatabase,
      $ExtensionFailureLogsTable,
      ExtensionFailureLog,
      $$ExtensionFailureLogsTableFilterComposer,
      $$ExtensionFailureLogsTableOrderingComposer,
      $$ExtensionFailureLogsTableAnnotationComposer,
      $$ExtensionFailureLogsTableCreateCompanionBuilder,
      $$ExtensionFailureLogsTableUpdateCompanionBuilder,
      (ExtensionFailureLog, $$ExtensionFailureLogsTableReferences),
      ExtensionFailureLog,
      PrefetchHooks Function({bool extensionId})
    >;
typedef $$WatchProgressEntriesTableCreateCompanionBuilder =
    WatchProgressEntriesCompanion Function({
      required String id,
      required String mediaKey,
      required String mediaType,
      required String title,
      Value<String?> subtitleLine,
      Value<int?> seasonNumber,
      Value<int?> episodeNumber,
      Value<int> positionMs,
      Value<int?> durationMs,
      Value<int> elapsedMs,
      Value<int> completed,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$WatchProgressEntriesTableUpdateCompanionBuilder =
    WatchProgressEntriesCompanion Function({
      Value<String> id,
      Value<String> mediaKey,
      Value<String> mediaType,
      Value<String> title,
      Value<String?> subtitleLine,
      Value<int?> seasonNumber,
      Value<int?> episodeNumber,
      Value<int> positionMs,
      Value<int?> durationMs,
      Value<int> elapsedMs,
      Value<int> completed,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$WatchProgressEntriesTableFilterComposer
    extends Composer<_$SpectaDatabase, $WatchProgressEntriesTable> {
  $$WatchProgressEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaKey => $composableBuilder(
    column: $table.mediaKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subtitleLine => $composableBuilder(
    column: $table.subtitleLine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get elapsedMs => $composableBuilder(
    column: $table.elapsedMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WatchProgressEntriesTableOrderingComposer
    extends Composer<_$SpectaDatabase, $WatchProgressEntriesTable> {
  $$WatchProgressEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaKey => $composableBuilder(
    column: $table.mediaKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaType => $composableBuilder(
    column: $table.mediaType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subtitleLine => $composableBuilder(
    column: $table.subtitleLine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get elapsedMs => $composableBuilder(
    column: $table.elapsedMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WatchProgressEntriesTableAnnotationComposer
    extends Composer<_$SpectaDatabase, $WatchProgressEntriesTable> {
  $$WatchProgressEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mediaKey =>
      $composableBuilder(column: $table.mediaKey, builder: (column) => column);

  GeneratedColumn<String> get mediaType =>
      $composableBuilder(column: $table.mediaType, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get subtitleLine => $composableBuilder(
    column: $table.subtitleLine,
    builder: (column) => column,
  );

  GeneratedColumn<int> get seasonNumber => $composableBuilder(
    column: $table.seasonNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get episodeNumber => $composableBuilder(
    column: $table.episodeNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get elapsedMs =>
      $composableBuilder(column: $table.elapsedMs, builder: (column) => column);

  GeneratedColumn<int> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$WatchProgressEntriesTableTableManager
    extends
        RootTableManager<
          _$SpectaDatabase,
          $WatchProgressEntriesTable,
          WatchProgressRow,
          $$WatchProgressEntriesTableFilterComposer,
          $$WatchProgressEntriesTableOrderingComposer,
          $$WatchProgressEntriesTableAnnotationComposer,
          $$WatchProgressEntriesTableCreateCompanionBuilder,
          $$WatchProgressEntriesTableUpdateCompanionBuilder,
          (
            WatchProgressRow,
            BaseReferences<
              _$SpectaDatabase,
              $WatchProgressEntriesTable,
              WatchProgressRow
            >,
          ),
          WatchProgressRow,
          PrefetchHooks Function()
        > {
  $$WatchProgressEntriesTableTableManager(
    _$SpectaDatabase db,
    $WatchProgressEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchProgressEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchProgressEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$WatchProgressEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> mediaKey = const Value.absent(),
                Value<String> mediaType = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> subtitleLine = const Value.absent(),
                Value<int?> seasonNumber = const Value.absent(),
                Value<int?> episodeNumber = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int> elapsedMs = const Value.absent(),
                Value<int> completed = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WatchProgressEntriesCompanion(
                id: id,
                mediaKey: mediaKey,
                mediaType: mediaType,
                title: title,
                subtitleLine: subtitleLine,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                positionMs: positionMs,
                durationMs: durationMs,
                elapsedMs: elapsedMs,
                completed: completed,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String mediaKey,
                required String mediaType,
                required String title,
                Value<String?> subtitleLine = const Value.absent(),
                Value<int?> seasonNumber = const Value.absent(),
                Value<int?> episodeNumber = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<int> elapsedMs = const Value.absent(),
                Value<int> completed = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => WatchProgressEntriesCompanion.insert(
                id: id,
                mediaKey: mediaKey,
                mediaType: mediaType,
                title: title,
                subtitleLine: subtitleLine,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                positionMs: positionMs,
                durationMs: durationMs,
                elapsedMs: elapsedMs,
                completed: completed,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WatchProgressEntriesTable, WatchProgressRow>(
                    table,
                  ),
                  BaseReferences<
                    _$SpectaDatabase,
                    $WatchProgressEntriesTable,
                    WatchProgressRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WatchProgressEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$SpectaDatabase,
      $WatchProgressEntriesTable,
      WatchProgressRow,
      $$WatchProgressEntriesTableFilterComposer,
      $$WatchProgressEntriesTableOrderingComposer,
      $$WatchProgressEntriesTableAnnotationComposer,
      $$WatchProgressEntriesTableCreateCompanionBuilder,
      $$WatchProgressEntriesTableUpdateCompanionBuilder,
      (
        WatchProgressRow,
        BaseReferences<
          _$SpectaDatabase,
          $WatchProgressEntriesTable,
          WatchProgressRow
        >,
      ),
      WatchProgressRow,
      PrefetchHooks Function()
    >;
typedef $$MediaReferencesTableCreateCompanionBuilder =
    MediaReferencesCompanion Function({
      required String mediaKey,
      required int ordinal,
      required String extensionId,
      required String referenceUrl,
      Value<int> rowid,
    });
typedef $$MediaReferencesTableUpdateCompanionBuilder =
    MediaReferencesCompanion Function({
      Value<String> mediaKey,
      Value<int> ordinal,
      Value<String> extensionId,
      Value<String> referenceUrl,
      Value<int> rowid,
    });

class $$MediaReferencesTableFilterComposer
    extends Composer<_$SpectaDatabase, $MediaReferencesTable> {
  $$MediaReferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get mediaKey => $composableBuilder(
    column: $table.mediaKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extensionId => $composableBuilder(
    column: $table.extensionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referenceUrl => $composableBuilder(
    column: $table.referenceUrl,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MediaReferencesTableOrderingComposer
    extends Composer<_$SpectaDatabase, $MediaReferencesTable> {
  $$MediaReferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get mediaKey => $composableBuilder(
    column: $table.mediaKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extensionId => $composableBuilder(
    column: $table.extensionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referenceUrl => $composableBuilder(
    column: $table.referenceUrl,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MediaReferencesTableAnnotationComposer
    extends Composer<_$SpectaDatabase, $MediaReferencesTable> {
  $$MediaReferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get mediaKey =>
      $composableBuilder(column: $table.mediaKey, builder: (column) => column);

  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<String> get extensionId => $composableBuilder(
    column: $table.extensionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get referenceUrl => $composableBuilder(
    column: $table.referenceUrl,
    builder: (column) => column,
  );
}

class $$MediaReferencesTableTableManager
    extends
        RootTableManager<
          _$SpectaDatabase,
          $MediaReferencesTable,
          MediaReferenceRow,
          $$MediaReferencesTableFilterComposer,
          $$MediaReferencesTableOrderingComposer,
          $$MediaReferencesTableAnnotationComposer,
          $$MediaReferencesTableCreateCompanionBuilder,
          $$MediaReferencesTableUpdateCompanionBuilder,
          (
            MediaReferenceRow,
            BaseReferences<
              _$SpectaDatabase,
              $MediaReferencesTable,
              MediaReferenceRow
            >,
          ),
          MediaReferenceRow,
          PrefetchHooks Function()
        > {
  $$MediaReferencesTableTableManager(
    _$SpectaDatabase db,
    $MediaReferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaReferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaReferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaReferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> mediaKey = const Value.absent(),
                Value<int> ordinal = const Value.absent(),
                Value<String> extensionId = const Value.absent(),
                Value<String> referenceUrl = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaReferencesCompanion(
                mediaKey: mediaKey,
                ordinal: ordinal,
                extensionId: extensionId,
                referenceUrl: referenceUrl,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String mediaKey,
                required int ordinal,
                required String extensionId,
                required String referenceUrl,
                Value<int> rowid = const Value.absent(),
              }) => MediaReferencesCompanion.insert(
                mediaKey: mediaKey,
                ordinal: ordinal,
                extensionId: extensionId,
                referenceUrl: referenceUrl,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MediaReferencesTable, MediaReferenceRow>(table),
                  BaseReferences<
                    _$SpectaDatabase,
                    $MediaReferencesTable,
                    MediaReferenceRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MediaReferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$SpectaDatabase,
      $MediaReferencesTable,
      MediaReferenceRow,
      $$MediaReferencesTableFilterComposer,
      $$MediaReferencesTableOrderingComposer,
      $$MediaReferencesTableAnnotationComposer,
      $$MediaReferencesTableCreateCompanionBuilder,
      $$MediaReferencesTableUpdateCompanionBuilder,
      (
        MediaReferenceRow,
        BaseReferences<
          _$SpectaDatabase,
          $MediaReferencesTable,
          MediaReferenceRow
        >,
      ),
      MediaReferenceRow,
      PrefetchHooks Function()
    >;

class $SpectaDatabaseManager {
  final _$SpectaDatabase _db;
  $SpectaDatabaseManager(this._db);
  $$SettingsEntriesTableTableManager get settingsEntries =>
      $$SettingsEntriesTableTableManager(_db, _db.settingsEntries);
  $$ExtensionsTableTableManager get extensions =>
      $$ExtensionsTableTableManager(_db, _db.extensions);
  $$ExtensionVersionsTableTableManager get extensionVersions =>
      $$ExtensionVersionsTableTableManager(_db, _db.extensionVersions);
  $$ExtensionFailureLogsTableTableManager get extensionFailureLogs =>
      $$ExtensionFailureLogsTableTableManager(_db, _db.extensionFailureLogs);
  $$WatchProgressEntriesTableTableManager get watchProgressEntries =>
      $$WatchProgressEntriesTableTableManager(_db, _db.watchProgressEntries);
  $$MediaReferencesTableTableManager get mediaReferences =>
      $$MediaReferencesTableTableManager(_db, _db.mediaReferences);
}
