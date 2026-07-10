// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CachedSessionsTable extends CachedSessions
    with TableInfo<$CachedSessionsTable, CachedSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _gatewayIdMeta = const VerificationMeta(
    'gatewayId',
  );
  @override
  late final GeneratedColumn<String> gatewayId = GeneratedColumn<String>(
    'gateway_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<String> startedAt = GeneratedColumn<String>(
    'started_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<String> endedAt = GeneratedColumn<String>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endReasonMeta = const VerificationMeta(
    'endReason',
  );
  @override
  late final GeneratedColumn<String> endReason = GeneratedColumn<String>(
    'end_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _messageCountMeta = const VerificationMeta(
    'messageCount',
  );
  @override
  late final GeneratedColumn<int> messageCount = GeneratedColumn<int>(
    'message_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toolCallCountMeta = const VerificationMeta(
    'toolCallCount',
  );
  @override
  late final GeneratedColumn<int> toolCallCount = GeneratedColumn<int>(
    'tool_call_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastActiveMeta = const VerificationMeta(
    'lastActive',
  );
  @override
  late final GeneratedColumn<String> lastActive = GeneratedColumn<String>(
    'last_active',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _previewMeta = const VerificationMeta(
    'preview',
  );
  @override
  late final GeneratedColumn<String> preview = GeneratedColumn<String>(
    'preview',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentSessionIdMeta = const VerificationMeta(
    'parentSessionId',
  );
  @override
  late final GeneratedColumn<String> parentSessionId = GeneratedColumn<String>(
    'parent_session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
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
    gatewayId,
    id,
    source,
    userId,
    model,
    title,
    startedAt,
    endedAt,
    endReason,
    messageCount,
    toolCallCount,
    lastActive,
    preview,
    parentSessionId,
    syncStatus,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('gateway_id')) {
      context.handle(
        _gatewayIdMeta,
        gatewayId.isAcceptableOrUnknown(data['gateway_id']!, _gatewayIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gatewayIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('end_reason')) {
      context.handle(
        _endReasonMeta,
        endReason.isAcceptableOrUnknown(data['end_reason']!, _endReasonMeta),
      );
    }
    if (data.containsKey('message_count')) {
      context.handle(
        _messageCountMeta,
        messageCount.isAcceptableOrUnknown(
          data['message_count']!,
          _messageCountMeta,
        ),
      );
    }
    if (data.containsKey('tool_call_count')) {
      context.handle(
        _toolCallCountMeta,
        toolCallCount.isAcceptableOrUnknown(
          data['tool_call_count']!,
          _toolCallCountMeta,
        ),
      );
    }
    if (data.containsKey('last_active')) {
      context.handle(
        _lastActiveMeta,
        lastActive.isAcceptableOrUnknown(data['last_active']!, _lastActiveMeta),
      );
    }
    if (data.containsKey('preview')) {
      context.handle(
        _previewMeta,
        preview.isAcceptableOrUnknown(data['preview']!, _previewMeta),
      );
    }
    if (data.containsKey('parent_session_id')) {
      context.handle(
        _parentSessionIdMeta,
        parentSessionId.isAcceptableOrUnknown(
          data['parent_session_id']!,
          _parentSessionIdMeta,
        ),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
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
  Set<GeneratedColumn> get $primaryKey => {gatewayId, id};
  @override
  CachedSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedSession(
      gatewayId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gateway_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      ),
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      ),
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}started_at'],
      ),
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ended_at'],
      ),
      endReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}end_reason'],
      ),
      messageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}message_count'],
      ),
      toolCallCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tool_call_count'],
      ),
      lastActive: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_active'],
      ),
      preview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preview'],
      ),
      parentSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_session_id'],
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedSessionsTable createAlias(String alias) {
    return $CachedSessionsTable(attachedDatabase, alias);
  }
}

class CachedSession extends DataClass implements Insertable<CachedSession> {
  final String gatewayId;
  final String id;
  final String? source;
  final String? userId;
  final String? model;
  final String? title;
  final String? startedAt;
  final String? endedAt;
  final String? endReason;
  final int? messageCount;
  final int? toolCallCount;
  final String? lastActive;
  final String? preview;
  final String? parentSessionId;

  /// pending | synced | deleted_pending
  final String syncStatus;
  final DateTime updatedAt;
  const CachedSession({
    required this.gatewayId,
    required this.id,
    this.source,
    this.userId,
    this.model,
    this.title,
    this.startedAt,
    this.endedAt,
    this.endReason,
    this.messageCount,
    this.toolCallCount,
    this.lastActive,
    this.preview,
    this.parentSessionId,
    required this.syncStatus,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['gateway_id'] = Variable<String>(gatewayId);
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    if (!nullToAbsent || model != null) {
      map['model'] = Variable<String>(model);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<String>(startedAt);
    }
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<String>(endedAt);
    }
    if (!nullToAbsent || endReason != null) {
      map['end_reason'] = Variable<String>(endReason);
    }
    if (!nullToAbsent || messageCount != null) {
      map['message_count'] = Variable<int>(messageCount);
    }
    if (!nullToAbsent || toolCallCount != null) {
      map['tool_call_count'] = Variable<int>(toolCallCount);
    }
    if (!nullToAbsent || lastActive != null) {
      map['last_active'] = Variable<String>(lastActive);
    }
    if (!nullToAbsent || preview != null) {
      map['preview'] = Variable<String>(preview);
    }
    if (!nullToAbsent || parentSessionId != null) {
      map['parent_session_id'] = Variable<String>(parentSessionId);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedSessionsCompanion toCompanion(bool nullToAbsent) {
    return CachedSessionsCompanion(
      gatewayId: Value(gatewayId),
      id: Value(id),
      source: source == null && nullToAbsent
          ? const Value.absent()
          : Value(source),
      userId: userId == null && nullToAbsent
          ? const Value.absent()
          : Value(userId),
      model: model == null && nullToAbsent
          ? const Value.absent()
          : Value(model),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      endReason: endReason == null && nullToAbsent
          ? const Value.absent()
          : Value(endReason),
      messageCount: messageCount == null && nullToAbsent
          ? const Value.absent()
          : Value(messageCount),
      toolCallCount: toolCallCount == null && nullToAbsent
          ? const Value.absent()
          : Value(toolCallCount),
      lastActive: lastActive == null && nullToAbsent
          ? const Value.absent()
          : Value(lastActive),
      preview: preview == null && nullToAbsent
          ? const Value.absent()
          : Value(preview),
      parentSessionId: parentSessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentSessionId),
      syncStatus: Value(syncStatus),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedSession(
      gatewayId: serializer.fromJson<String>(json['gatewayId']),
      id: serializer.fromJson<String>(json['id']),
      source: serializer.fromJson<String?>(json['source']),
      userId: serializer.fromJson<String?>(json['userId']),
      model: serializer.fromJson<String?>(json['model']),
      title: serializer.fromJson<String?>(json['title']),
      startedAt: serializer.fromJson<String?>(json['startedAt']),
      endedAt: serializer.fromJson<String?>(json['endedAt']),
      endReason: serializer.fromJson<String?>(json['endReason']),
      messageCount: serializer.fromJson<int?>(json['messageCount']),
      toolCallCount: serializer.fromJson<int?>(json['toolCallCount']),
      lastActive: serializer.fromJson<String?>(json['lastActive']),
      preview: serializer.fromJson<String?>(json['preview']),
      parentSessionId: serializer.fromJson<String?>(json['parentSessionId']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'gatewayId': serializer.toJson<String>(gatewayId),
      'id': serializer.toJson<String>(id),
      'source': serializer.toJson<String?>(source),
      'userId': serializer.toJson<String?>(userId),
      'model': serializer.toJson<String?>(model),
      'title': serializer.toJson<String?>(title),
      'startedAt': serializer.toJson<String?>(startedAt),
      'endedAt': serializer.toJson<String?>(endedAt),
      'endReason': serializer.toJson<String?>(endReason),
      'messageCount': serializer.toJson<int?>(messageCount),
      'toolCallCount': serializer.toJson<int?>(toolCallCount),
      'lastActive': serializer.toJson<String?>(lastActive),
      'preview': serializer.toJson<String?>(preview),
      'parentSessionId': serializer.toJson<String?>(parentSessionId),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedSession copyWith({
    String? gatewayId,
    String? id,
    Value<String?> source = const Value.absent(),
    Value<String?> userId = const Value.absent(),
    Value<String?> model = const Value.absent(),
    Value<String?> title = const Value.absent(),
    Value<String?> startedAt = const Value.absent(),
    Value<String?> endedAt = const Value.absent(),
    Value<String?> endReason = const Value.absent(),
    Value<int?> messageCount = const Value.absent(),
    Value<int?> toolCallCount = const Value.absent(),
    Value<String?> lastActive = const Value.absent(),
    Value<String?> preview = const Value.absent(),
    Value<String?> parentSessionId = const Value.absent(),
    String? syncStatus,
    DateTime? updatedAt,
  }) => CachedSession(
    gatewayId: gatewayId ?? this.gatewayId,
    id: id ?? this.id,
    source: source.present ? source.value : this.source,
    userId: userId.present ? userId.value : this.userId,
    model: model.present ? model.value : this.model,
    title: title.present ? title.value : this.title,
    startedAt: startedAt.present ? startedAt.value : this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    endReason: endReason.present ? endReason.value : this.endReason,
    messageCount: messageCount.present ? messageCount.value : this.messageCount,
    toolCallCount: toolCallCount.present
        ? toolCallCount.value
        : this.toolCallCount,
    lastActive: lastActive.present ? lastActive.value : this.lastActive,
    preview: preview.present ? preview.value : this.preview,
    parentSessionId: parentSessionId.present
        ? parentSessionId.value
        : this.parentSessionId,
    syncStatus: syncStatus ?? this.syncStatus,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedSession copyWithCompanion(CachedSessionsCompanion data) {
    return CachedSession(
      gatewayId: data.gatewayId.present ? data.gatewayId.value : this.gatewayId,
      id: data.id.present ? data.id.value : this.id,
      source: data.source.present ? data.source.value : this.source,
      userId: data.userId.present ? data.userId.value : this.userId,
      model: data.model.present ? data.model.value : this.model,
      title: data.title.present ? data.title.value : this.title,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      endReason: data.endReason.present ? data.endReason.value : this.endReason,
      messageCount: data.messageCount.present
          ? data.messageCount.value
          : this.messageCount,
      toolCallCount: data.toolCallCount.present
          ? data.toolCallCount.value
          : this.toolCallCount,
      lastActive: data.lastActive.present
          ? data.lastActive.value
          : this.lastActive,
      preview: data.preview.present ? data.preview.value : this.preview,
      parentSessionId: data.parentSessionId.present
          ? data.parentSessionId.value
          : this.parentSessionId,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedSession(')
          ..write('gatewayId: $gatewayId, ')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('userId: $userId, ')
          ..write('model: $model, ')
          ..write('title: $title, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('endReason: $endReason, ')
          ..write('messageCount: $messageCount, ')
          ..write('toolCallCount: $toolCallCount, ')
          ..write('lastActive: $lastActive, ')
          ..write('preview: $preview, ')
          ..write('parentSessionId: $parentSessionId, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    gatewayId,
    id,
    source,
    userId,
    model,
    title,
    startedAt,
    endedAt,
    endReason,
    messageCount,
    toolCallCount,
    lastActive,
    preview,
    parentSessionId,
    syncStatus,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedSession &&
          other.gatewayId == this.gatewayId &&
          other.id == this.id &&
          other.source == this.source &&
          other.userId == this.userId &&
          other.model == this.model &&
          other.title == this.title &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.endReason == this.endReason &&
          other.messageCount == this.messageCount &&
          other.toolCallCount == this.toolCallCount &&
          other.lastActive == this.lastActive &&
          other.preview == this.preview &&
          other.parentSessionId == this.parentSessionId &&
          other.syncStatus == this.syncStatus &&
          other.updatedAt == this.updatedAt);
}

class CachedSessionsCompanion extends UpdateCompanion<CachedSession> {
  final Value<String> gatewayId;
  final Value<String> id;
  final Value<String?> source;
  final Value<String?> userId;
  final Value<String?> model;
  final Value<String?> title;
  final Value<String?> startedAt;
  final Value<String?> endedAt;
  final Value<String?> endReason;
  final Value<int?> messageCount;
  final Value<int?> toolCallCount;
  final Value<String?> lastActive;
  final Value<String?> preview;
  final Value<String?> parentSessionId;
  final Value<String> syncStatus;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedSessionsCompanion({
    this.gatewayId = const Value.absent(),
    this.id = const Value.absent(),
    this.source = const Value.absent(),
    this.userId = const Value.absent(),
    this.model = const Value.absent(),
    this.title = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.endReason = const Value.absent(),
    this.messageCount = const Value.absent(),
    this.toolCallCount = const Value.absent(),
    this.lastActive = const Value.absent(),
    this.preview = const Value.absent(),
    this.parentSessionId = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedSessionsCompanion.insert({
    required String gatewayId,
    required String id,
    this.source = const Value.absent(),
    this.userId = const Value.absent(),
    this.model = const Value.absent(),
    this.title = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.endReason = const Value.absent(),
    this.messageCount = const Value.absent(),
    this.toolCallCount = const Value.absent(),
    this.lastActive = const Value.absent(),
    this.preview = const Value.absent(),
    this.parentSessionId = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : gatewayId = Value(gatewayId),
       id = Value(id),
       updatedAt = Value(updatedAt);
  static Insertable<CachedSession> custom({
    Expression<String>? gatewayId,
    Expression<String>? id,
    Expression<String>? source,
    Expression<String>? userId,
    Expression<String>? model,
    Expression<String>? title,
    Expression<String>? startedAt,
    Expression<String>? endedAt,
    Expression<String>? endReason,
    Expression<int>? messageCount,
    Expression<int>? toolCallCount,
    Expression<String>? lastActive,
    Expression<String>? preview,
    Expression<String>? parentSessionId,
    Expression<String>? syncStatus,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (gatewayId != null) 'gateway_id': gatewayId,
      if (id != null) 'id': id,
      if (source != null) 'source': source,
      if (userId != null) 'user_id': userId,
      if (model != null) 'model': model,
      if (title != null) 'title': title,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (endReason != null) 'end_reason': endReason,
      if (messageCount != null) 'message_count': messageCount,
      if (toolCallCount != null) 'tool_call_count': toolCallCount,
      if (lastActive != null) 'last_active': lastActive,
      if (preview != null) 'preview': preview,
      if (parentSessionId != null) 'parent_session_id': parentSessionId,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedSessionsCompanion copyWith({
    Value<String>? gatewayId,
    Value<String>? id,
    Value<String?>? source,
    Value<String?>? userId,
    Value<String?>? model,
    Value<String?>? title,
    Value<String?>? startedAt,
    Value<String?>? endedAt,
    Value<String?>? endReason,
    Value<int?>? messageCount,
    Value<int?>? toolCallCount,
    Value<String?>? lastActive,
    Value<String?>? preview,
    Value<String?>? parentSessionId,
    Value<String>? syncStatus,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedSessionsCompanion(
      gatewayId: gatewayId ?? this.gatewayId,
      id: id ?? this.id,
      source: source ?? this.source,
      userId: userId ?? this.userId,
      model: model ?? this.model,
      title: title ?? this.title,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      endReason: endReason ?? this.endReason,
      messageCount: messageCount ?? this.messageCount,
      toolCallCount: toolCallCount ?? this.toolCallCount,
      lastActive: lastActive ?? this.lastActive,
      preview: preview ?? this.preview,
      parentSessionId: parentSessionId ?? this.parentSessionId,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (gatewayId.present) {
      map['gateway_id'] = Variable<String>(gatewayId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<String>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<String>(endedAt.value);
    }
    if (endReason.present) {
      map['end_reason'] = Variable<String>(endReason.value);
    }
    if (messageCount.present) {
      map['message_count'] = Variable<int>(messageCount.value);
    }
    if (toolCallCount.present) {
      map['tool_call_count'] = Variable<int>(toolCallCount.value);
    }
    if (lastActive.present) {
      map['last_active'] = Variable<String>(lastActive.value);
    }
    if (preview.present) {
      map['preview'] = Variable<String>(preview.value);
    }
    if (parentSessionId.present) {
      map['parent_session_id'] = Variable<String>(parentSessionId.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
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
    return (StringBuffer('CachedSessionsCompanion(')
          ..write('gatewayId: $gatewayId, ')
          ..write('id: $id, ')
          ..write('source: $source, ')
          ..write('userId: $userId, ')
          ..write('model: $model, ')
          ..write('title: $title, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('endReason: $endReason, ')
          ..write('messageCount: $messageCount, ')
          ..write('toolCallCount: $toolCallCount, ')
          ..write('lastActive: $lastActive, ')
          ..write('preview: $preview, ')
          ..write('parentSessionId: $parentSessionId, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedMessagesTable extends CachedMessages
    with TableInfo<$CachedMessagesTable, CachedMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _gatewayIdMeta = const VerificationMeta(
    'gatewayId',
  );
  @override
  late final GeneratedColumn<String> gatewayId = GeneratedColumn<String>(
    'gateway_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toolCallIdMeta = const VerificationMeta(
    'toolCallId',
  );
  @override
  late final GeneratedColumn<String> toolCallId = GeneratedColumn<String>(
    'tool_call_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toolNameMeta = const VerificationMeta(
    'toolName',
  );
  @override
  late final GeneratedColumn<String> toolName = GeneratedColumn<String>(
    'tool_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<String> timestamp = GeneratedColumn<String>(
    'timestamp',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tokenCountMeta = const VerificationMeta(
    'tokenCount',
  );
  @override
  late final GeneratedColumn<int> tokenCount = GeneratedColumn<int>(
    'token_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _finishReasonMeta = const VerificationMeta(
    'finishReason',
  );
  @override
  late final GeneratedColumn<String> finishReason = GeneratedColumn<String>(
    'finish_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reasoningMeta = const VerificationMeta(
    'reasoning',
  );
  @override
  late final GeneratedColumn<String> reasoning = GeneratedColumn<String>(
    'reasoning',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toolCallsJsonMeta = const VerificationMeta(
    'toolCallsJson',
  );
  @override
  late final GeneratedColumn<String> toolCallsJson = GeneratedColumn<String>(
    'tool_calls_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortIndexMeta = const VerificationMeta(
    'sortIndex',
  );
  @override
  late final GeneratedColumn<int> sortIndex = GeneratedColumn<int>(
    'sort_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    gatewayId,
    sessionId,
    id,
    role,
    content,
    toolCallId,
    toolName,
    timestamp,
    tokenCount,
    finishReason,
    reasoning,
    toolCallsJson,
    sortIndex,
    syncStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('gateway_id')) {
      context.handle(
        _gatewayIdMeta,
        gatewayId.isAcceptableOrUnknown(data['gateway_id']!, _gatewayIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gatewayIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('tool_call_id')) {
      context.handle(
        _toolCallIdMeta,
        toolCallId.isAcceptableOrUnknown(
          data['tool_call_id']!,
          _toolCallIdMeta,
        ),
      );
    }
    if (data.containsKey('tool_name')) {
      context.handle(
        _toolNameMeta,
        toolName.isAcceptableOrUnknown(data['tool_name']!, _toolNameMeta),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    }
    if (data.containsKey('token_count')) {
      context.handle(
        _tokenCountMeta,
        tokenCount.isAcceptableOrUnknown(data['token_count']!, _tokenCountMeta),
      );
    }
    if (data.containsKey('finish_reason')) {
      context.handle(
        _finishReasonMeta,
        finishReason.isAcceptableOrUnknown(
          data['finish_reason']!,
          _finishReasonMeta,
        ),
      );
    }
    if (data.containsKey('reasoning')) {
      context.handle(
        _reasoningMeta,
        reasoning.isAcceptableOrUnknown(data['reasoning']!, _reasoningMeta),
      );
    }
    if (data.containsKey('tool_calls_json')) {
      context.handle(
        _toolCallsJsonMeta,
        toolCallsJson.isAcceptableOrUnknown(
          data['tool_calls_json']!,
          _toolCallsJsonMeta,
        ),
      );
    }
    if (data.containsKey('sort_index')) {
      context.handle(
        _sortIndexMeta,
        sortIndex.isAcceptableOrUnknown(data['sort_index']!, _sortIndexMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {gatewayId, sessionId, id};
  @override
  CachedMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedMessage(
      gatewayId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gateway_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      ),
      toolCallId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool_call_id'],
      ),
      toolName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool_name'],
      ),
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timestamp'],
      ),
      tokenCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}token_count'],
      ),
      finishReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}finish_reason'],
      ),
      reasoning: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reasoning'],
      ),
      toolCallsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tool_calls_json'],
      ),
      sortIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_index'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
    );
  }

  @override
  $CachedMessagesTable createAlias(String alias) {
    return $CachedMessagesTable(attachedDatabase, alias);
  }
}

class CachedMessage extends DataClass implements Insertable<CachedMessage> {
  final String gatewayId;
  final String sessionId;
  final String id;
  final String role;
  final String? content;
  final String? toolCallId;
  final String? toolName;
  final String? timestamp;
  final int? tokenCount;
  final String? finishReason;
  final String? reasoning;

  /// Opaque JSON for tool_calls when present.
  final String? toolCallsJson;
  final int sortIndex;

  /// pending | synced
  final String syncStatus;
  const CachedMessage({
    required this.gatewayId,
    required this.sessionId,
    required this.id,
    required this.role,
    this.content,
    this.toolCallId,
    this.toolName,
    this.timestamp,
    this.tokenCount,
    this.finishReason,
    this.reasoning,
    this.toolCallsJson,
    required this.sortIndex,
    required this.syncStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['gateway_id'] = Variable<String>(gatewayId);
    map['session_id'] = Variable<String>(sessionId);
    map['id'] = Variable<String>(id);
    map['role'] = Variable<String>(role);
    if (!nullToAbsent || content != null) {
      map['content'] = Variable<String>(content);
    }
    if (!nullToAbsent || toolCallId != null) {
      map['tool_call_id'] = Variable<String>(toolCallId);
    }
    if (!nullToAbsent || toolName != null) {
      map['tool_name'] = Variable<String>(toolName);
    }
    if (!nullToAbsent || timestamp != null) {
      map['timestamp'] = Variable<String>(timestamp);
    }
    if (!nullToAbsent || tokenCount != null) {
      map['token_count'] = Variable<int>(tokenCount);
    }
    if (!nullToAbsent || finishReason != null) {
      map['finish_reason'] = Variable<String>(finishReason);
    }
    if (!nullToAbsent || reasoning != null) {
      map['reasoning'] = Variable<String>(reasoning);
    }
    if (!nullToAbsent || toolCallsJson != null) {
      map['tool_calls_json'] = Variable<String>(toolCallsJson);
    }
    map['sort_index'] = Variable<int>(sortIndex);
    map['sync_status'] = Variable<String>(syncStatus);
    return map;
  }

  CachedMessagesCompanion toCompanion(bool nullToAbsent) {
    return CachedMessagesCompanion(
      gatewayId: Value(gatewayId),
      sessionId: Value(sessionId),
      id: Value(id),
      role: Value(role),
      content: content == null && nullToAbsent
          ? const Value.absent()
          : Value(content),
      toolCallId: toolCallId == null && nullToAbsent
          ? const Value.absent()
          : Value(toolCallId),
      toolName: toolName == null && nullToAbsent
          ? const Value.absent()
          : Value(toolName),
      timestamp: timestamp == null && nullToAbsent
          ? const Value.absent()
          : Value(timestamp),
      tokenCount: tokenCount == null && nullToAbsent
          ? const Value.absent()
          : Value(tokenCount),
      finishReason: finishReason == null && nullToAbsent
          ? const Value.absent()
          : Value(finishReason),
      reasoning: reasoning == null && nullToAbsent
          ? const Value.absent()
          : Value(reasoning),
      toolCallsJson: toolCallsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(toolCallsJson),
      sortIndex: Value(sortIndex),
      syncStatus: Value(syncStatus),
    );
  }

  factory CachedMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedMessage(
      gatewayId: serializer.fromJson<String>(json['gatewayId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      id: serializer.fromJson<String>(json['id']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String?>(json['content']),
      toolCallId: serializer.fromJson<String?>(json['toolCallId']),
      toolName: serializer.fromJson<String?>(json['toolName']),
      timestamp: serializer.fromJson<String?>(json['timestamp']),
      tokenCount: serializer.fromJson<int?>(json['tokenCount']),
      finishReason: serializer.fromJson<String?>(json['finishReason']),
      reasoning: serializer.fromJson<String?>(json['reasoning']),
      toolCallsJson: serializer.fromJson<String?>(json['toolCallsJson']),
      sortIndex: serializer.fromJson<int>(json['sortIndex']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'gatewayId': serializer.toJson<String>(gatewayId),
      'sessionId': serializer.toJson<String>(sessionId),
      'id': serializer.toJson<String>(id),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String?>(content),
      'toolCallId': serializer.toJson<String?>(toolCallId),
      'toolName': serializer.toJson<String?>(toolName),
      'timestamp': serializer.toJson<String?>(timestamp),
      'tokenCount': serializer.toJson<int?>(tokenCount),
      'finishReason': serializer.toJson<String?>(finishReason),
      'reasoning': serializer.toJson<String?>(reasoning),
      'toolCallsJson': serializer.toJson<String?>(toolCallsJson),
      'sortIndex': serializer.toJson<int>(sortIndex),
      'syncStatus': serializer.toJson<String>(syncStatus),
    };
  }

  CachedMessage copyWith({
    String? gatewayId,
    String? sessionId,
    String? id,
    String? role,
    Value<String?> content = const Value.absent(),
    Value<String?> toolCallId = const Value.absent(),
    Value<String?> toolName = const Value.absent(),
    Value<String?> timestamp = const Value.absent(),
    Value<int?> tokenCount = const Value.absent(),
    Value<String?> finishReason = const Value.absent(),
    Value<String?> reasoning = const Value.absent(),
    Value<String?> toolCallsJson = const Value.absent(),
    int? sortIndex,
    String? syncStatus,
  }) => CachedMessage(
    gatewayId: gatewayId ?? this.gatewayId,
    sessionId: sessionId ?? this.sessionId,
    id: id ?? this.id,
    role: role ?? this.role,
    content: content.present ? content.value : this.content,
    toolCallId: toolCallId.present ? toolCallId.value : this.toolCallId,
    toolName: toolName.present ? toolName.value : this.toolName,
    timestamp: timestamp.present ? timestamp.value : this.timestamp,
    tokenCount: tokenCount.present ? tokenCount.value : this.tokenCount,
    finishReason: finishReason.present ? finishReason.value : this.finishReason,
    reasoning: reasoning.present ? reasoning.value : this.reasoning,
    toolCallsJson: toolCallsJson.present
        ? toolCallsJson.value
        : this.toolCallsJson,
    sortIndex: sortIndex ?? this.sortIndex,
    syncStatus: syncStatus ?? this.syncStatus,
  );
  CachedMessage copyWithCompanion(CachedMessagesCompanion data) {
    return CachedMessage(
      gatewayId: data.gatewayId.present ? data.gatewayId.value : this.gatewayId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      id: data.id.present ? data.id.value : this.id,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      toolCallId: data.toolCallId.present
          ? data.toolCallId.value
          : this.toolCallId,
      toolName: data.toolName.present ? data.toolName.value : this.toolName,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      tokenCount: data.tokenCount.present
          ? data.tokenCount.value
          : this.tokenCount,
      finishReason: data.finishReason.present
          ? data.finishReason.value
          : this.finishReason,
      reasoning: data.reasoning.present ? data.reasoning.value : this.reasoning,
      toolCallsJson: data.toolCallsJson.present
          ? data.toolCallsJson.value
          : this.toolCallsJson,
      sortIndex: data.sortIndex.present ? data.sortIndex.value : this.sortIndex,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedMessage(')
          ..write('gatewayId: $gatewayId, ')
          ..write('sessionId: $sessionId, ')
          ..write('id: $id, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('toolCallId: $toolCallId, ')
          ..write('toolName: $toolName, ')
          ..write('timestamp: $timestamp, ')
          ..write('tokenCount: $tokenCount, ')
          ..write('finishReason: $finishReason, ')
          ..write('reasoning: $reasoning, ')
          ..write('toolCallsJson: $toolCallsJson, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('syncStatus: $syncStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    gatewayId,
    sessionId,
    id,
    role,
    content,
    toolCallId,
    toolName,
    timestamp,
    tokenCount,
    finishReason,
    reasoning,
    toolCallsJson,
    sortIndex,
    syncStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedMessage &&
          other.gatewayId == this.gatewayId &&
          other.sessionId == this.sessionId &&
          other.id == this.id &&
          other.role == this.role &&
          other.content == this.content &&
          other.toolCallId == this.toolCallId &&
          other.toolName == this.toolName &&
          other.timestamp == this.timestamp &&
          other.tokenCount == this.tokenCount &&
          other.finishReason == this.finishReason &&
          other.reasoning == this.reasoning &&
          other.toolCallsJson == this.toolCallsJson &&
          other.sortIndex == this.sortIndex &&
          other.syncStatus == this.syncStatus);
}

class CachedMessagesCompanion extends UpdateCompanion<CachedMessage> {
  final Value<String> gatewayId;
  final Value<String> sessionId;
  final Value<String> id;
  final Value<String> role;
  final Value<String?> content;
  final Value<String?> toolCallId;
  final Value<String?> toolName;
  final Value<String?> timestamp;
  final Value<int?> tokenCount;
  final Value<String?> finishReason;
  final Value<String?> reasoning;
  final Value<String?> toolCallsJson;
  final Value<int> sortIndex;
  final Value<String> syncStatus;
  final Value<int> rowid;
  const CachedMessagesCompanion({
    this.gatewayId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.id = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.toolCallId = const Value.absent(),
    this.toolName = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.tokenCount = const Value.absent(),
    this.finishReason = const Value.absent(),
    this.reasoning = const Value.absent(),
    this.toolCallsJson = const Value.absent(),
    this.sortIndex = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedMessagesCompanion.insert({
    required String gatewayId,
    required String sessionId,
    required String id,
    required String role,
    this.content = const Value.absent(),
    this.toolCallId = const Value.absent(),
    this.toolName = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.tokenCount = const Value.absent(),
    this.finishReason = const Value.absent(),
    this.reasoning = const Value.absent(),
    this.toolCallsJson = const Value.absent(),
    this.sortIndex = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : gatewayId = Value(gatewayId),
       sessionId = Value(sessionId),
       id = Value(id),
       role = Value(role);
  static Insertable<CachedMessage> custom({
    Expression<String>? gatewayId,
    Expression<String>? sessionId,
    Expression<String>? id,
    Expression<String>? role,
    Expression<String>? content,
    Expression<String>? toolCallId,
    Expression<String>? toolName,
    Expression<String>? timestamp,
    Expression<int>? tokenCount,
    Expression<String>? finishReason,
    Expression<String>? reasoning,
    Expression<String>? toolCallsJson,
    Expression<int>? sortIndex,
    Expression<String>? syncStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (gatewayId != null) 'gateway_id': gatewayId,
      if (sessionId != null) 'session_id': sessionId,
      if (id != null) 'id': id,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (toolCallId != null) 'tool_call_id': toolCallId,
      if (toolName != null) 'tool_name': toolName,
      if (timestamp != null) 'timestamp': timestamp,
      if (tokenCount != null) 'token_count': tokenCount,
      if (finishReason != null) 'finish_reason': finishReason,
      if (reasoning != null) 'reasoning': reasoning,
      if (toolCallsJson != null) 'tool_calls_json': toolCallsJson,
      if (sortIndex != null) 'sort_index': sortIndex,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedMessagesCompanion copyWith({
    Value<String>? gatewayId,
    Value<String>? sessionId,
    Value<String>? id,
    Value<String>? role,
    Value<String?>? content,
    Value<String?>? toolCallId,
    Value<String?>? toolName,
    Value<String?>? timestamp,
    Value<int?>? tokenCount,
    Value<String?>? finishReason,
    Value<String?>? reasoning,
    Value<String?>? toolCallsJson,
    Value<int>? sortIndex,
    Value<String>? syncStatus,
    Value<int>? rowid,
  }) {
    return CachedMessagesCompanion(
      gatewayId: gatewayId ?? this.gatewayId,
      sessionId: sessionId ?? this.sessionId,
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      timestamp: timestamp ?? this.timestamp,
      tokenCount: tokenCount ?? this.tokenCount,
      finishReason: finishReason ?? this.finishReason,
      reasoning: reasoning ?? this.reasoning,
      toolCallsJson: toolCallsJson ?? this.toolCallsJson,
      sortIndex: sortIndex ?? this.sortIndex,
      syncStatus: syncStatus ?? this.syncStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (gatewayId.present) {
      map['gateway_id'] = Variable<String>(gatewayId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (toolCallId.present) {
      map['tool_call_id'] = Variable<String>(toolCallId.value);
    }
    if (toolName.present) {
      map['tool_name'] = Variable<String>(toolName.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<String>(timestamp.value);
    }
    if (tokenCount.present) {
      map['token_count'] = Variable<int>(tokenCount.value);
    }
    if (finishReason.present) {
      map['finish_reason'] = Variable<String>(finishReason.value);
    }
    if (reasoning.present) {
      map['reasoning'] = Variable<String>(reasoning.value);
    }
    if (toolCallsJson.present) {
      map['tool_calls_json'] = Variable<String>(toolCallsJson.value);
    }
    if (sortIndex.present) {
      map['sort_index'] = Variable<int>(sortIndex.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedMessagesCompanion(')
          ..write('gatewayId: $gatewayId, ')
          ..write('sessionId: $sessionId, ')
          ..write('id: $id, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('toolCallId: $toolCallId, ')
          ..write('toolName: $toolName, ')
          ..write('timestamp: $timestamp, ')
          ..write('tokenCount: $tokenCount, ')
          ..write('finishReason: $finishReason, ')
          ..write('reasoning: $reasoning, ')
          ..write('toolCallsJson: $toolCallsJson, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingOpsTable extends PendingOps
    with TableInfo<$PendingOpsTable, PendingOp> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingOpsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gatewayIdMeta = const VerificationMeta(
    'gatewayId',
  );
  @override
  late final GeneratedColumn<String> gatewayId = GeneratedColumn<String>(
    'gateway_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opTypeMeta = const VerificationMeta('opType');
  @override
  late final GeneratedColumn<String> opType = GeneratedColumn<String>(
    'op_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    gatewayId,
    opType,
    sessionId,
    payloadJson,
    attemptCount,
    lastError,
    createdAt,
    nextAttemptAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_ops';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingOp> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('gateway_id')) {
      context.handle(
        _gatewayIdMeta,
        gatewayId.isAcceptableOrUnknown(data['gateway_id']!, _gatewayIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gatewayIdMeta);
    }
    if (data.containsKey('op_type')) {
      context.handle(
        _opTypeMeta,
        opType.isAcceptableOrUnknown(data['op_type']!, _opTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_opTypeMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingOp map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingOp(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      gatewayId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gateway_id'],
      )!,
      opType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op_type'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
    );
  }

  @override
  $PendingOpsTable createAlias(String alias) {
    return $PendingOpsTable(attachedDatabase, alias);
  }
}

class PendingOp extends DataClass implements Insertable<PendingOp> {
  final String id;
  final String gatewayId;

  /// create_session | delete_session | patch_session | chat
  final String opType;
  final String? sessionId;
  final String payloadJson;
  final int attemptCount;
  final String lastError;
  final DateTime createdAt;
  final DateTime? nextAttemptAt;
  const PendingOp({
    required this.id,
    required this.gatewayId,
    required this.opType,
    this.sessionId,
    required this.payloadJson,
    required this.attemptCount,
    required this.lastError,
    required this.createdAt,
    this.nextAttemptAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['gateway_id'] = Variable<String>(gatewayId);
    map['op_type'] = Variable<String>(opType);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    map['payload_json'] = Variable<String>(payloadJson);
    map['attempt_count'] = Variable<int>(attemptCount);
    map['last_error'] = Variable<String>(lastError);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    return map;
  }

  PendingOpsCompanion toCompanion(bool nullToAbsent) {
    return PendingOpsCompanion(
      id: Value(id),
      gatewayId: Value(gatewayId),
      opType: Value(opType),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      payloadJson: Value(payloadJson),
      attemptCount: Value(attemptCount),
      lastError: Value(lastError),
      createdAt: Value(createdAt),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
    );
  }

  factory PendingOp.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingOp(
      id: serializer.fromJson<String>(json['id']),
      gatewayId: serializer.fromJson<String>(json['gatewayId']),
      opType: serializer.fromJson<String>(json['opType']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      lastError: serializer.fromJson<String>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'gatewayId': serializer.toJson<String>(gatewayId),
      'opType': serializer.toJson<String>(opType),
      'sessionId': serializer.toJson<String?>(sessionId),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'lastError': serializer.toJson<String>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
    };
  }

  PendingOp copyWith({
    String? id,
    String? gatewayId,
    String? opType,
    Value<String?> sessionId = const Value.absent(),
    String? payloadJson,
    int? attemptCount,
    String? lastError,
    DateTime? createdAt,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
  }) => PendingOp(
    id: id ?? this.id,
    gatewayId: gatewayId ?? this.gatewayId,
    opType: opType ?? this.opType,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    payloadJson: payloadJson ?? this.payloadJson,
    attemptCount: attemptCount ?? this.attemptCount,
    lastError: lastError ?? this.lastError,
    createdAt: createdAt ?? this.createdAt,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
  );
  PendingOp copyWithCompanion(PendingOpsCompanion data) {
    return PendingOp(
      id: data.id.present ? data.id.value : this.id,
      gatewayId: data.gatewayId.present ? data.gatewayId.value : this.gatewayId,
      opType: data.opType.present ? data.opType.value : this.opType,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingOp(')
          ..write('id: $id, ')
          ..write('gatewayId: $gatewayId, ')
          ..write('opType: $opType, ')
          ..write('sessionId: $sessionId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('nextAttemptAt: $nextAttemptAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    gatewayId,
    opType,
    sessionId,
    payloadJson,
    attemptCount,
    lastError,
    createdAt,
    nextAttemptAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingOp &&
          other.id == this.id &&
          other.gatewayId == this.gatewayId &&
          other.opType == this.opType &&
          other.sessionId == this.sessionId &&
          other.payloadJson == this.payloadJson &&
          other.attemptCount == this.attemptCount &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt &&
          other.nextAttemptAt == this.nextAttemptAt);
}

class PendingOpsCompanion extends UpdateCompanion<PendingOp> {
  final Value<String> id;
  final Value<String> gatewayId;
  final Value<String> opType;
  final Value<String?> sessionId;
  final Value<String> payloadJson;
  final Value<int> attemptCount;
  final Value<String> lastError;
  final Value<DateTime> createdAt;
  final Value<DateTime?> nextAttemptAt;
  final Value<int> rowid;
  const PendingOpsCompanion({
    this.id = const Value.absent(),
    this.gatewayId = const Value.absent(),
    this.opType = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingOpsCompanion.insert({
    required String id,
    required String gatewayId,
    required String opType,
    this.sessionId = const Value.absent(),
    required String payloadJson,
    this.attemptCount = const Value.absent(),
    this.lastError = const Value.absent(),
    required DateTime createdAt,
    this.nextAttemptAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       gatewayId = Value(gatewayId),
       opType = Value(opType),
       payloadJson = Value(payloadJson),
       createdAt = Value(createdAt);
  static Insertable<PendingOp> custom({
    Expression<String>? id,
    Expression<String>? gatewayId,
    Expression<String>? opType,
    Expression<String>? sessionId,
    Expression<String>? payloadJson,
    Expression<int>? attemptCount,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? nextAttemptAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (gatewayId != null) 'gateway_id': gatewayId,
      if (opType != null) 'op_type': opType,
      if (sessionId != null) 'session_id': sessionId,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingOpsCompanion copyWith({
    Value<String>? id,
    Value<String>? gatewayId,
    Value<String>? opType,
    Value<String?>? sessionId,
    Value<String>? payloadJson,
    Value<int>? attemptCount,
    Value<String>? lastError,
    Value<DateTime>? createdAt,
    Value<DateTime?>? nextAttemptAt,
    Value<int>? rowid,
  }) {
    return PendingOpsCompanion(
      id: id ?? this.id,
      gatewayId: gatewayId ?? this.gatewayId,
      opType: opType ?? this.opType,
      sessionId: sessionId ?? this.sessionId,
      payloadJson: payloadJson ?? this.payloadJson,
      attemptCount: attemptCount ?? this.attemptCount,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (gatewayId.present) {
      map['gateway_id'] = Variable<String>(gatewayId.value);
    }
    if (opType.present) {
      map['op_type'] = Variable<String>(opType.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingOpsCompanion(')
          ..write('id: $id, ')
          ..write('gatewayId: $gatewayId, ')
          ..write('opType: $opType, ')
          ..write('sessionId: $sessionId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedJobsTable extends CachedJobs
    with TableInfo<$CachedJobsTable, CachedJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _gatewayIdMeta = const VerificationMeta(
    'gatewayId',
  );
  @override
  late final GeneratedColumn<String> gatewayId = GeneratedColumn<String>(
    'gateway_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scheduleMeta = const VerificationMeta(
    'schedule',
  );
  @override
  late final GeneratedColumn<String> schedule = GeneratedColumn<String>(
    'schedule',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _promptMeta = const VerificationMeta('prompt');
  @override
  late final GeneratedColumn<String> prompt = GeneratedColumn<String>(
    'prompt',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deliverMeta = const VerificationMeta(
    'deliver',
  );
  @override
  late final GeneratedColumn<String> deliver = GeneratedColumn<String>(
    'deliver',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastRunAtMeta = const VerificationMeta(
    'lastRunAt',
  );
  @override
  late final GeneratedColumn<String> lastRunAt = GeneratedColumn<String>(
    'last_run_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastStatusMeta = const VerificationMeta(
    'lastStatus',
  );
  @override
  late final GeneratedColumn<String> lastStatus = GeneratedColumn<String>(
    'last_status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nextRunAtMeta = const VerificationMeta(
    'nextRunAt',
  );
  @override
  late final GeneratedColumn<String> nextRunAt = GeneratedColumn<String>(
    'next_run_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('synced'),
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
    gatewayId,
    id,
    name,
    schedule,
    prompt,
    deliver,
    enabled,
    state,
    lastRunAt,
    lastStatus,
    nextRunAt,
    syncStatus,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedJob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('gateway_id')) {
      context.handle(
        _gatewayIdMeta,
        gatewayId.isAcceptableOrUnknown(data['gateway_id']!, _gatewayIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gatewayIdMeta);
    }
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
    }
    if (data.containsKey('schedule')) {
      context.handle(
        _scheduleMeta,
        schedule.isAcceptableOrUnknown(data['schedule']!, _scheduleMeta),
      );
    }
    if (data.containsKey('prompt')) {
      context.handle(
        _promptMeta,
        prompt.isAcceptableOrUnknown(data['prompt']!, _promptMeta),
      );
    }
    if (data.containsKey('deliver')) {
      context.handle(
        _deliverMeta,
        deliver.isAcceptableOrUnknown(data['deliver']!, _deliverMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('last_run_at')) {
      context.handle(
        _lastRunAtMeta,
        lastRunAt.isAcceptableOrUnknown(data['last_run_at']!, _lastRunAtMeta),
      );
    }
    if (data.containsKey('last_status')) {
      context.handle(
        _lastStatusMeta,
        lastStatus.isAcceptableOrUnknown(data['last_status']!, _lastStatusMeta),
      );
    }
    if (data.containsKey('next_run_at')) {
      context.handle(
        _nextRunAtMeta,
        nextRunAt.isAcceptableOrUnknown(data['next_run_at']!, _nextRunAtMeta),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
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
  Set<GeneratedColumn> get $primaryKey => {gatewayId, id};
  @override
  CachedJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedJob(
      gatewayId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gateway_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      schedule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}schedule'],
      ),
      prompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt'],
      ),
      deliver: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deliver'],
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      ),
      lastRunAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_run_at'],
      ),
      lastStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_status'],
      ),
      nextRunAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}next_run_at'],
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedJobsTable createAlias(String alias) {
    return $CachedJobsTable(attachedDatabase, alias);
  }
}

class CachedJob extends DataClass implements Insertable<CachedJob> {
  final String gatewayId;
  final String id;
  final String? name;
  final String? schedule;
  final String? prompt;
  final String? deliver;
  final bool? enabled;
  final String? state;
  final String? lastRunAt;
  final String? lastStatus;
  final String? nextRunAt;

  /// synced | deleted_pending
  final String syncStatus;
  final DateTime updatedAt;
  const CachedJob({
    required this.gatewayId,
    required this.id,
    this.name,
    this.schedule,
    this.prompt,
    this.deliver,
    this.enabled,
    this.state,
    this.lastRunAt,
    this.lastStatus,
    this.nextRunAt,
    required this.syncStatus,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['gateway_id'] = Variable<String>(gatewayId);
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || schedule != null) {
      map['schedule'] = Variable<String>(schedule);
    }
    if (!nullToAbsent || prompt != null) {
      map['prompt'] = Variable<String>(prompt);
    }
    if (!nullToAbsent || deliver != null) {
      map['deliver'] = Variable<String>(deliver);
    }
    if (!nullToAbsent || enabled != null) {
      map['enabled'] = Variable<bool>(enabled);
    }
    if (!nullToAbsent || state != null) {
      map['state'] = Variable<String>(state);
    }
    if (!nullToAbsent || lastRunAt != null) {
      map['last_run_at'] = Variable<String>(lastRunAt);
    }
    if (!nullToAbsent || lastStatus != null) {
      map['last_status'] = Variable<String>(lastStatus);
    }
    if (!nullToAbsent || nextRunAt != null) {
      map['next_run_at'] = Variable<String>(nextRunAt);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedJobsCompanion toCompanion(bool nullToAbsent) {
    return CachedJobsCompanion(
      gatewayId: Value(gatewayId),
      id: Value(id),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      schedule: schedule == null && nullToAbsent
          ? const Value.absent()
          : Value(schedule),
      prompt: prompt == null && nullToAbsent
          ? const Value.absent()
          : Value(prompt),
      deliver: deliver == null && nullToAbsent
          ? const Value.absent()
          : Value(deliver),
      enabled: enabled == null && nullToAbsent
          ? const Value.absent()
          : Value(enabled),
      state: state == null && nullToAbsent
          ? const Value.absent()
          : Value(state),
      lastRunAt: lastRunAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRunAt),
      lastStatus: lastStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(lastStatus),
      nextRunAt: nextRunAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRunAt),
      syncStatus: Value(syncStatus),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedJob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedJob(
      gatewayId: serializer.fromJson<String>(json['gatewayId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String?>(json['name']),
      schedule: serializer.fromJson<String?>(json['schedule']),
      prompt: serializer.fromJson<String?>(json['prompt']),
      deliver: serializer.fromJson<String?>(json['deliver']),
      enabled: serializer.fromJson<bool?>(json['enabled']),
      state: serializer.fromJson<String?>(json['state']),
      lastRunAt: serializer.fromJson<String?>(json['lastRunAt']),
      lastStatus: serializer.fromJson<String?>(json['lastStatus']),
      nextRunAt: serializer.fromJson<String?>(json['nextRunAt']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'gatewayId': serializer.toJson<String>(gatewayId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String?>(name),
      'schedule': serializer.toJson<String?>(schedule),
      'prompt': serializer.toJson<String?>(prompt),
      'deliver': serializer.toJson<String?>(deliver),
      'enabled': serializer.toJson<bool?>(enabled),
      'state': serializer.toJson<String?>(state),
      'lastRunAt': serializer.toJson<String?>(lastRunAt),
      'lastStatus': serializer.toJson<String?>(lastStatus),
      'nextRunAt': serializer.toJson<String?>(nextRunAt),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedJob copyWith({
    String? gatewayId,
    String? id,
    Value<String?> name = const Value.absent(),
    Value<String?> schedule = const Value.absent(),
    Value<String?> prompt = const Value.absent(),
    Value<String?> deliver = const Value.absent(),
    Value<bool?> enabled = const Value.absent(),
    Value<String?> state = const Value.absent(),
    Value<String?> lastRunAt = const Value.absent(),
    Value<String?> lastStatus = const Value.absent(),
    Value<String?> nextRunAt = const Value.absent(),
    String? syncStatus,
    DateTime? updatedAt,
  }) => CachedJob(
    gatewayId: gatewayId ?? this.gatewayId,
    id: id ?? this.id,
    name: name.present ? name.value : this.name,
    schedule: schedule.present ? schedule.value : this.schedule,
    prompt: prompt.present ? prompt.value : this.prompt,
    deliver: deliver.present ? deliver.value : this.deliver,
    enabled: enabled.present ? enabled.value : this.enabled,
    state: state.present ? state.value : this.state,
    lastRunAt: lastRunAt.present ? lastRunAt.value : this.lastRunAt,
    lastStatus: lastStatus.present ? lastStatus.value : this.lastStatus,
    nextRunAt: nextRunAt.present ? nextRunAt.value : this.nextRunAt,
    syncStatus: syncStatus ?? this.syncStatus,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedJob copyWithCompanion(CachedJobsCompanion data) {
    return CachedJob(
      gatewayId: data.gatewayId.present ? data.gatewayId.value : this.gatewayId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      schedule: data.schedule.present ? data.schedule.value : this.schedule,
      prompt: data.prompt.present ? data.prompt.value : this.prompt,
      deliver: data.deliver.present ? data.deliver.value : this.deliver,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      state: data.state.present ? data.state.value : this.state,
      lastRunAt: data.lastRunAt.present ? data.lastRunAt.value : this.lastRunAt,
      lastStatus: data.lastStatus.present
          ? data.lastStatus.value
          : this.lastStatus,
      nextRunAt: data.nextRunAt.present ? data.nextRunAt.value : this.nextRunAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedJob(')
          ..write('gatewayId: $gatewayId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('schedule: $schedule, ')
          ..write('prompt: $prompt, ')
          ..write('deliver: $deliver, ')
          ..write('enabled: $enabled, ')
          ..write('state: $state, ')
          ..write('lastRunAt: $lastRunAt, ')
          ..write('lastStatus: $lastStatus, ')
          ..write('nextRunAt: $nextRunAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    gatewayId,
    id,
    name,
    schedule,
    prompt,
    deliver,
    enabled,
    state,
    lastRunAt,
    lastStatus,
    nextRunAt,
    syncStatus,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedJob &&
          other.gatewayId == this.gatewayId &&
          other.id == this.id &&
          other.name == this.name &&
          other.schedule == this.schedule &&
          other.prompt == this.prompt &&
          other.deliver == this.deliver &&
          other.enabled == this.enabled &&
          other.state == this.state &&
          other.lastRunAt == this.lastRunAt &&
          other.lastStatus == this.lastStatus &&
          other.nextRunAt == this.nextRunAt &&
          other.syncStatus == this.syncStatus &&
          other.updatedAt == this.updatedAt);
}

class CachedJobsCompanion extends UpdateCompanion<CachedJob> {
  final Value<String> gatewayId;
  final Value<String> id;
  final Value<String?> name;
  final Value<String?> schedule;
  final Value<String?> prompt;
  final Value<String?> deliver;
  final Value<bool?> enabled;
  final Value<String?> state;
  final Value<String?> lastRunAt;
  final Value<String?> lastStatus;
  final Value<String?> nextRunAt;
  final Value<String> syncStatus;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedJobsCompanion({
    this.gatewayId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.schedule = const Value.absent(),
    this.prompt = const Value.absent(),
    this.deliver = const Value.absent(),
    this.enabled = const Value.absent(),
    this.state = const Value.absent(),
    this.lastRunAt = const Value.absent(),
    this.lastStatus = const Value.absent(),
    this.nextRunAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedJobsCompanion.insert({
    required String gatewayId,
    required String id,
    this.name = const Value.absent(),
    this.schedule = const Value.absent(),
    this.prompt = const Value.absent(),
    this.deliver = const Value.absent(),
    this.enabled = const Value.absent(),
    this.state = const Value.absent(),
    this.lastRunAt = const Value.absent(),
    this.lastStatus = const Value.absent(),
    this.nextRunAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : gatewayId = Value(gatewayId),
       id = Value(id),
       updatedAt = Value(updatedAt);
  static Insertable<CachedJob> custom({
    Expression<String>? gatewayId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? schedule,
    Expression<String>? prompt,
    Expression<String>? deliver,
    Expression<bool>? enabled,
    Expression<String>? state,
    Expression<String>? lastRunAt,
    Expression<String>? lastStatus,
    Expression<String>? nextRunAt,
    Expression<String>? syncStatus,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (gatewayId != null) 'gateway_id': gatewayId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (schedule != null) 'schedule': schedule,
      if (prompt != null) 'prompt': prompt,
      if (deliver != null) 'deliver': deliver,
      if (enabled != null) 'enabled': enabled,
      if (state != null) 'state': state,
      if (lastRunAt != null) 'last_run_at': lastRunAt,
      if (lastStatus != null) 'last_status': lastStatus,
      if (nextRunAt != null) 'next_run_at': nextRunAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedJobsCompanion copyWith({
    Value<String>? gatewayId,
    Value<String>? id,
    Value<String?>? name,
    Value<String?>? schedule,
    Value<String?>? prompt,
    Value<String?>? deliver,
    Value<bool?>? enabled,
    Value<String?>? state,
    Value<String?>? lastRunAt,
    Value<String?>? lastStatus,
    Value<String?>? nextRunAt,
    Value<String>? syncStatus,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedJobsCompanion(
      gatewayId: gatewayId ?? this.gatewayId,
      id: id ?? this.id,
      name: name ?? this.name,
      schedule: schedule ?? this.schedule,
      prompt: prompt ?? this.prompt,
      deliver: deliver ?? this.deliver,
      enabled: enabled ?? this.enabled,
      state: state ?? this.state,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      lastStatus: lastStatus ?? this.lastStatus,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      syncStatus: syncStatus ?? this.syncStatus,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (gatewayId.present) {
      map['gateway_id'] = Variable<String>(gatewayId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (schedule.present) {
      map['schedule'] = Variable<String>(schedule.value);
    }
    if (prompt.present) {
      map['prompt'] = Variable<String>(prompt.value);
    }
    if (deliver.present) {
      map['deliver'] = Variable<String>(deliver.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (lastRunAt.present) {
      map['last_run_at'] = Variable<String>(lastRunAt.value);
    }
    if (lastStatus.present) {
      map['last_status'] = Variable<String>(lastStatus.value);
    }
    if (nextRunAt.present) {
      map['next_run_at'] = Variable<String>(nextRunAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
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
    return (StringBuffer('CachedJobsCompanion(')
          ..write('gatewayId: $gatewayId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('schedule: $schedule, ')
          ..write('prompt: $prompt, ')
          ..write('deliver: $deliver, ')
          ..write('enabled: $enabled, ')
          ..write('state: $state, ')
          ..write('lastRunAt: $lastRunAt, ')
          ..write('lastStatus: $lastStatus, ')
          ..write('nextRunAt: $nextRunAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedSkillsTable extends CachedSkills
    with TableInfo<$CachedSkillsTable, CachedSkill> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedSkillsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _gatewayIdMeta = const VerificationMeta(
    'gatewayId',
  );
  @override
  late final GeneratedColumn<String> gatewayId = GeneratedColumn<String>(
    'gateway_id',
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
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _provenanceMeta = const VerificationMeta(
    'provenance',
  );
  @override
  late final GeneratedColumn<String> provenance = GeneratedColumn<String>(
    'provenance',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _usageMeta = const VerificationMeta('usage');
  @override
  late final GeneratedColumn<int> usage = GeneratedColumn<int>(
    'usage',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
    gatewayId,
    name,
    description,
    category,
    enabled,
    provenance,
    usage,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_skills';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedSkill> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('gateway_id')) {
      context.handle(
        _gatewayIdMeta,
        gatewayId.isAcceptableOrUnknown(data['gateway_id']!, _gatewayIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gatewayIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('provenance')) {
      context.handle(
        _provenanceMeta,
        provenance.isAcceptableOrUnknown(data['provenance']!, _provenanceMeta),
      );
    }
    if (data.containsKey('usage')) {
      context.handle(
        _usageMeta,
        usage.isAcceptableOrUnknown(data['usage']!, _usageMeta),
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
  Set<GeneratedColumn> get $primaryKey => {gatewayId, name};
  @override
  CachedSkill map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedSkill(
      gatewayId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gateway_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      provenance: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provenance'],
      ),
      usage: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}usage'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedSkillsTable createAlias(String alias) {
    return $CachedSkillsTable(attachedDatabase, alias);
  }
}

class CachedSkill extends DataClass implements Insertable<CachedSkill> {
  final String gatewayId;
  final String name;
  final String? description;
  final String? category;
  final bool enabled;
  final String? provenance;
  final int? usage;
  final DateTime updatedAt;
  const CachedSkill({
    required this.gatewayId,
    required this.name,
    this.description,
    this.category,
    required this.enabled,
    this.provenance,
    this.usage,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['gateway_id'] = Variable<String>(gatewayId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || provenance != null) {
      map['provenance'] = Variable<String>(provenance);
    }
    if (!nullToAbsent || usage != null) {
      map['usage'] = Variable<int>(usage);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedSkillsCompanion toCompanion(bool nullToAbsent) {
    return CachedSkillsCompanion(
      gatewayId: Value(gatewayId),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      enabled: Value(enabled),
      provenance: provenance == null && nullToAbsent
          ? const Value.absent()
          : Value(provenance),
      usage: usage == null && nullToAbsent
          ? const Value.absent()
          : Value(usage),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedSkill.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedSkill(
      gatewayId: serializer.fromJson<String>(json['gatewayId']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      category: serializer.fromJson<String?>(json['category']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      provenance: serializer.fromJson<String?>(json['provenance']),
      usage: serializer.fromJson<int?>(json['usage']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'gatewayId': serializer.toJson<String>(gatewayId),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'category': serializer.toJson<String?>(category),
      'enabled': serializer.toJson<bool>(enabled),
      'provenance': serializer.toJson<String?>(provenance),
      'usage': serializer.toJson<int?>(usage),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedSkill copyWith({
    String? gatewayId,
    String? name,
    Value<String?> description = const Value.absent(),
    Value<String?> category = const Value.absent(),
    bool? enabled,
    Value<String?> provenance = const Value.absent(),
    Value<int?> usage = const Value.absent(),
    DateTime? updatedAt,
  }) => CachedSkill(
    gatewayId: gatewayId ?? this.gatewayId,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    category: category.present ? category.value : this.category,
    enabled: enabled ?? this.enabled,
    provenance: provenance.present ? provenance.value : this.provenance,
    usage: usage.present ? usage.value : this.usage,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedSkill copyWithCompanion(CachedSkillsCompanion data) {
    return CachedSkill(
      gatewayId: data.gatewayId.present ? data.gatewayId.value : this.gatewayId,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      category: data.category.present ? data.category.value : this.category,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      provenance: data.provenance.present
          ? data.provenance.value
          : this.provenance,
      usage: data.usage.present ? data.usage.value : this.usage,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedSkill(')
          ..write('gatewayId: $gatewayId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('enabled: $enabled, ')
          ..write('provenance: $provenance, ')
          ..write('usage: $usage, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    gatewayId,
    name,
    description,
    category,
    enabled,
    provenance,
    usage,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedSkill &&
          other.gatewayId == this.gatewayId &&
          other.name == this.name &&
          other.description == this.description &&
          other.category == this.category &&
          other.enabled == this.enabled &&
          other.provenance == this.provenance &&
          other.usage == this.usage &&
          other.updatedAt == this.updatedAt);
}

class CachedSkillsCompanion extends UpdateCompanion<CachedSkill> {
  final Value<String> gatewayId;
  final Value<String> name;
  final Value<String?> description;
  final Value<String?> category;
  final Value<bool> enabled;
  final Value<String?> provenance;
  final Value<int?> usage;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedSkillsCompanion({
    this.gatewayId = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.category = const Value.absent(),
    this.enabled = const Value.absent(),
    this.provenance = const Value.absent(),
    this.usage = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedSkillsCompanion.insert({
    required String gatewayId,
    required String name,
    this.description = const Value.absent(),
    this.category = const Value.absent(),
    this.enabled = const Value.absent(),
    this.provenance = const Value.absent(),
    this.usage = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : gatewayId = Value(gatewayId),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<CachedSkill> custom({
    Expression<String>? gatewayId,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? category,
    Expression<bool>? enabled,
    Expression<String>? provenance,
    Expression<int>? usage,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (gatewayId != null) 'gateway_id': gatewayId,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (category != null) 'category': category,
      if (enabled != null) 'enabled': enabled,
      if (provenance != null) 'provenance': provenance,
      if (usage != null) 'usage': usage,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedSkillsCompanion copyWith({
    Value<String>? gatewayId,
    Value<String>? name,
    Value<String?>? description,
    Value<String?>? category,
    Value<bool>? enabled,
    Value<String?>? provenance,
    Value<int?>? usage,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedSkillsCompanion(
      gatewayId: gatewayId ?? this.gatewayId,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      enabled: enabled ?? this.enabled,
      provenance: provenance ?? this.provenance,
      usage: usage ?? this.usage,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (gatewayId.present) {
      map['gateway_id'] = Variable<String>(gatewayId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (provenance.present) {
      map['provenance'] = Variable<String>(provenance.value);
    }
    if (usage.present) {
      map['usage'] = Variable<int>(usage.value);
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
    return (StringBuffer('CachedSkillsCompanion(')
          ..write('gatewayId: $gatewayId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('enabled: $enabled, ')
          ..write('provenance: $provenance, ')
          ..write('usage: $usage, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CachedSessionsTable cachedSessions = $CachedSessionsTable(this);
  late final $CachedMessagesTable cachedMessages = $CachedMessagesTable(this);
  late final $PendingOpsTable pendingOps = $PendingOpsTable(this);
  late final $CachedJobsTable cachedJobs = $CachedJobsTable(this);
  late final $CachedSkillsTable cachedSkills = $CachedSkillsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedSessions,
    cachedMessages,
    pendingOps,
    cachedJobs,
    cachedSkills,
  ];
}

typedef $$CachedSessionsTableCreateCompanionBuilder =
    CachedSessionsCompanion Function({
      required String gatewayId,
      required String id,
      Value<String?> source,
      Value<String?> userId,
      Value<String?> model,
      Value<String?> title,
      Value<String?> startedAt,
      Value<String?> endedAt,
      Value<String?> endReason,
      Value<int?> messageCount,
      Value<int?> toolCallCount,
      Value<String?> lastActive,
      Value<String?> preview,
      Value<String?> parentSessionId,
      Value<String> syncStatus,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedSessionsTableUpdateCompanionBuilder =
    CachedSessionsCompanion Function({
      Value<String> gatewayId,
      Value<String> id,
      Value<String?> source,
      Value<String?> userId,
      Value<String?> model,
      Value<String?> title,
      Value<String?> startedAt,
      Value<String?> endedAt,
      Value<String?> endReason,
      Value<int?> messageCount,
      Value<int?> toolCallCount,
      Value<String?> lastActive,
      Value<String?> preview,
      Value<String?> parentSessionId,
      Value<String> syncStatus,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedSessionsTable> {
  $$CachedSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get gatewayId => $composableBuilder(
    column: $table.gatewayId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endReason => $composableBuilder(
    column: $table.endReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get toolCallCount => $composableBuilder(
    column: $table.toolCallCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastActive => $composableBuilder(
    column: $table.lastActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preview => $composableBuilder(
    column: $table.preview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentSessionId => $composableBuilder(
    column: $table.parentSessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedSessionsTable> {
  $$CachedSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get gatewayId => $composableBuilder(
    column: $table.gatewayId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endReason => $composableBuilder(
    column: $table.endReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get toolCallCount => $composableBuilder(
    column: $table.toolCallCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastActive => $composableBuilder(
    column: $table.lastActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preview => $composableBuilder(
    column: $table.preview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentSessionId => $composableBuilder(
    column: $table.parentSessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedSessionsTable> {
  $$CachedSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get gatewayId =>
      $composableBuilder(column: $table.gatewayId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<String> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<String> get endReason =>
      $composableBuilder(column: $table.endReason, builder: (column) => column);

  GeneratedColumn<int> get messageCount => $composableBuilder(
    column: $table.messageCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get toolCallCount => $composableBuilder(
    column: $table.toolCallCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastActive => $composableBuilder(
    column: $table.lastActive,
    builder: (column) => column,
  );

  GeneratedColumn<String> get preview =>
      $composableBuilder(column: $table.preview, builder: (column) => column);

  GeneratedColumn<String> get parentSessionId => $composableBuilder(
    column: $table.parentSessionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedSessionsTable,
          CachedSession,
          $$CachedSessionsTableFilterComposer,
          $$CachedSessionsTableOrderingComposer,
          $$CachedSessionsTableAnnotationComposer,
          $$CachedSessionsTableCreateCompanionBuilder,
          $$CachedSessionsTableUpdateCompanionBuilder,
          (
            CachedSession,
            BaseReferences<_$AppDatabase, $CachedSessionsTable, CachedSession>,
          ),
          CachedSession,
          PrefetchHooks Function()
        > {
  $$CachedSessionsTableTableManager(
    _$AppDatabase db,
    $CachedSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> gatewayId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<String?> userId = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> startedAt = const Value.absent(),
                Value<String?> endedAt = const Value.absent(),
                Value<String?> endReason = const Value.absent(),
                Value<int?> messageCount = const Value.absent(),
                Value<int?> toolCallCount = const Value.absent(),
                Value<String?> lastActive = const Value.absent(),
                Value<String?> preview = const Value.absent(),
                Value<String?> parentSessionId = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedSessionsCompanion(
                gatewayId: gatewayId,
                id: id,
                source: source,
                userId: userId,
                model: model,
                title: title,
                startedAt: startedAt,
                endedAt: endedAt,
                endReason: endReason,
                messageCount: messageCount,
                toolCallCount: toolCallCount,
                lastActive: lastActive,
                preview: preview,
                parentSessionId: parentSessionId,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String gatewayId,
                required String id,
                Value<String?> source = const Value.absent(),
                Value<String?> userId = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> startedAt = const Value.absent(),
                Value<String?> endedAt = const Value.absent(),
                Value<String?> endReason = const Value.absent(),
                Value<int?> messageCount = const Value.absent(),
                Value<int?> toolCallCount = const Value.absent(),
                Value<String?> lastActive = const Value.absent(),
                Value<String?> preview = const Value.absent(),
                Value<String?> parentSessionId = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedSessionsCompanion.insert(
                gatewayId: gatewayId,
                id: id,
                source: source,
                userId: userId,
                model: model,
                title: title,
                startedAt: startedAt,
                endedAt: endedAt,
                endReason: endReason,
                messageCount: messageCount,
                toolCallCount: toolCallCount,
                lastActive: lastActive,
                preview: preview,
                parentSessionId: parentSessionId,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedSessionsTable,
      CachedSession,
      $$CachedSessionsTableFilterComposer,
      $$CachedSessionsTableOrderingComposer,
      $$CachedSessionsTableAnnotationComposer,
      $$CachedSessionsTableCreateCompanionBuilder,
      $$CachedSessionsTableUpdateCompanionBuilder,
      (
        CachedSession,
        BaseReferences<_$AppDatabase, $CachedSessionsTable, CachedSession>,
      ),
      CachedSession,
      PrefetchHooks Function()
    >;
typedef $$CachedMessagesTableCreateCompanionBuilder =
    CachedMessagesCompanion Function({
      required String gatewayId,
      required String sessionId,
      required String id,
      required String role,
      Value<String?> content,
      Value<String?> toolCallId,
      Value<String?> toolName,
      Value<String?> timestamp,
      Value<int?> tokenCount,
      Value<String?> finishReason,
      Value<String?> reasoning,
      Value<String?> toolCallsJson,
      Value<int> sortIndex,
      Value<String> syncStatus,
      Value<int> rowid,
    });
typedef $$CachedMessagesTableUpdateCompanionBuilder =
    CachedMessagesCompanion Function({
      Value<String> gatewayId,
      Value<String> sessionId,
      Value<String> id,
      Value<String> role,
      Value<String?> content,
      Value<String?> toolCallId,
      Value<String?> toolName,
      Value<String?> timestamp,
      Value<int?> tokenCount,
      Value<String?> finishReason,
      Value<String?> reasoning,
      Value<String?> toolCallsJson,
      Value<int> sortIndex,
      Value<String> syncStatus,
      Value<int> rowid,
    });

class $$CachedMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get gatewayId => $composableBuilder(
    column: $table.gatewayId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toolCallId => $composableBuilder(
    column: $table.toolCallId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toolName => $composableBuilder(
    column: $table.toolName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tokenCount => $composableBuilder(
    column: $table.tokenCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get finishReason => $composableBuilder(
    column: $table.finishReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reasoning => $composableBuilder(
    column: $table.reasoning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toolCallsJson => $composableBuilder(
    column: $table.toolCallsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortIndex => $composableBuilder(
    column: $table.sortIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get gatewayId => $composableBuilder(
    column: $table.gatewayId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toolCallId => $composableBuilder(
    column: $table.toolCallId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toolName => $composableBuilder(
    column: $table.toolName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tokenCount => $composableBuilder(
    column: $table.tokenCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get finishReason => $composableBuilder(
    column: $table.finishReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reasoning => $composableBuilder(
    column: $table.reasoning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toolCallsJson => $composableBuilder(
    column: $table.toolCallsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortIndex => $composableBuilder(
    column: $table.sortIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedMessagesTable> {
  $$CachedMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get gatewayId =>
      $composableBuilder(column: $table.gatewayId, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get toolCallId => $composableBuilder(
    column: $table.toolCallId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get toolName =>
      $composableBuilder(column: $table.toolName, builder: (column) => column);

  GeneratedColumn<String> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get tokenCount => $composableBuilder(
    column: $table.tokenCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get finishReason => $composableBuilder(
    column: $table.finishReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reasoning =>
      $composableBuilder(column: $table.reasoning, builder: (column) => column);

  GeneratedColumn<String> get toolCallsJson => $composableBuilder(
    column: $table.toolCallsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortIndex =>
      $composableBuilder(column: $table.sortIndex, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );
}

class $$CachedMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedMessagesTable,
          CachedMessage,
          $$CachedMessagesTableFilterComposer,
          $$CachedMessagesTableOrderingComposer,
          $$CachedMessagesTableAnnotationComposer,
          $$CachedMessagesTableCreateCompanionBuilder,
          $$CachedMessagesTableUpdateCompanionBuilder,
          (
            CachedMessage,
            BaseReferences<_$AppDatabase, $CachedMessagesTable, CachedMessage>,
          ),
          CachedMessage,
          PrefetchHooks Function()
        > {
  $$CachedMessagesTableTableManager(
    _$AppDatabase db,
    $CachedMessagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> gatewayId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String?> content = const Value.absent(),
                Value<String?> toolCallId = const Value.absent(),
                Value<String?> toolName = const Value.absent(),
                Value<String?> timestamp = const Value.absent(),
                Value<int?> tokenCount = const Value.absent(),
                Value<String?> finishReason = const Value.absent(),
                Value<String?> reasoning = const Value.absent(),
                Value<String?> toolCallsJson = const Value.absent(),
                Value<int> sortIndex = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMessagesCompanion(
                gatewayId: gatewayId,
                sessionId: sessionId,
                id: id,
                role: role,
                content: content,
                toolCallId: toolCallId,
                toolName: toolName,
                timestamp: timestamp,
                tokenCount: tokenCount,
                finishReason: finishReason,
                reasoning: reasoning,
                toolCallsJson: toolCallsJson,
                sortIndex: sortIndex,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String gatewayId,
                required String sessionId,
                required String id,
                required String role,
                Value<String?> content = const Value.absent(),
                Value<String?> toolCallId = const Value.absent(),
                Value<String?> toolName = const Value.absent(),
                Value<String?> timestamp = const Value.absent(),
                Value<int?> tokenCount = const Value.absent(),
                Value<String?> finishReason = const Value.absent(),
                Value<String?> reasoning = const Value.absent(),
                Value<String?> toolCallsJson = const Value.absent(),
                Value<int> sortIndex = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedMessagesCompanion.insert(
                gatewayId: gatewayId,
                sessionId: sessionId,
                id: id,
                role: role,
                content: content,
                toolCallId: toolCallId,
                toolName: toolName,
                timestamp: timestamp,
                tokenCount: tokenCount,
                finishReason: finishReason,
                reasoning: reasoning,
                toolCallsJson: toolCallsJson,
                sortIndex: sortIndex,
                syncStatus: syncStatus,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedMessagesTable,
      CachedMessage,
      $$CachedMessagesTableFilterComposer,
      $$CachedMessagesTableOrderingComposer,
      $$CachedMessagesTableAnnotationComposer,
      $$CachedMessagesTableCreateCompanionBuilder,
      $$CachedMessagesTableUpdateCompanionBuilder,
      (
        CachedMessage,
        BaseReferences<_$AppDatabase, $CachedMessagesTable, CachedMessage>,
      ),
      CachedMessage,
      PrefetchHooks Function()
    >;
typedef $$PendingOpsTableCreateCompanionBuilder =
    PendingOpsCompanion Function({
      required String id,
      required String gatewayId,
      required String opType,
      Value<String?> sessionId,
      required String payloadJson,
      Value<int> attemptCount,
      Value<String> lastError,
      required DateTime createdAt,
      Value<DateTime?> nextAttemptAt,
      Value<int> rowid,
    });
typedef $$PendingOpsTableUpdateCompanionBuilder =
    PendingOpsCompanion Function({
      Value<String> id,
      Value<String> gatewayId,
      Value<String> opType,
      Value<String?> sessionId,
      Value<String> payloadJson,
      Value<int> attemptCount,
      Value<String> lastError,
      Value<DateTime> createdAt,
      Value<DateTime?> nextAttemptAt,
      Value<int> rowid,
    });

class $$PendingOpsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingOpsTable> {
  $$PendingOpsTableFilterComposer({
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

  ColumnFilters<String> get gatewayId => $composableBuilder(
    column: $table.gatewayId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get opType => $composableBuilder(
    column: $table.opType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingOpsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingOpsTable> {
  $$PendingOpsTableOrderingComposer({
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

  ColumnOrderings<String> get gatewayId => $composableBuilder(
    column: $table.gatewayId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get opType => $composableBuilder(
    column: $table.opType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingOpsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingOpsTable> {
  $$PendingOpsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get gatewayId =>
      $composableBuilder(column: $table.gatewayId, builder: (column) => column);

  GeneratedColumn<String> get opType =>
      $composableBuilder(column: $table.opType, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );
}

class $$PendingOpsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingOpsTable,
          PendingOp,
          $$PendingOpsTableFilterComposer,
          $$PendingOpsTableOrderingComposer,
          $$PendingOpsTableAnnotationComposer,
          $$PendingOpsTableCreateCompanionBuilder,
          $$PendingOpsTableUpdateCompanionBuilder,
          (
            PendingOp,
            BaseReferences<_$AppDatabase, $PendingOpsTable, PendingOp>,
          ),
          PendingOp,
          PrefetchHooks Function()
        > {
  $$PendingOpsTableTableManager(_$AppDatabase db, $PendingOpsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingOpsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingOpsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingOpsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> gatewayId = const Value.absent(),
                Value<String> opType = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<String> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingOpsCompanion(
                id: id,
                gatewayId: gatewayId,
                opType: opType,
                sessionId: sessionId,
                payloadJson: payloadJson,
                attemptCount: attemptCount,
                lastError: lastError,
                createdAt: createdAt,
                nextAttemptAt: nextAttemptAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String gatewayId,
                required String opType,
                Value<String?> sessionId = const Value.absent(),
                required String payloadJson,
                Value<int> attemptCount = const Value.absent(),
                Value<String> lastError = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingOpsCompanion.insert(
                id: id,
                gatewayId: gatewayId,
                opType: opType,
                sessionId: sessionId,
                payloadJson: payloadJson,
                attemptCount: attemptCount,
                lastError: lastError,
                createdAt: createdAt,
                nextAttemptAt: nextAttemptAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingOpsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingOpsTable,
      PendingOp,
      $$PendingOpsTableFilterComposer,
      $$PendingOpsTableOrderingComposer,
      $$PendingOpsTableAnnotationComposer,
      $$PendingOpsTableCreateCompanionBuilder,
      $$PendingOpsTableUpdateCompanionBuilder,
      (PendingOp, BaseReferences<_$AppDatabase, $PendingOpsTable, PendingOp>),
      PendingOp,
      PrefetchHooks Function()
    >;
typedef $$CachedJobsTableCreateCompanionBuilder =
    CachedJobsCompanion Function({
      required String gatewayId,
      required String id,
      Value<String?> name,
      Value<String?> schedule,
      Value<String?> prompt,
      Value<String?> deliver,
      Value<bool?> enabled,
      Value<String?> state,
      Value<String?> lastRunAt,
      Value<String?> lastStatus,
      Value<String?> nextRunAt,
      Value<String> syncStatus,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedJobsTableUpdateCompanionBuilder =
    CachedJobsCompanion Function({
      Value<String> gatewayId,
      Value<String> id,
      Value<String?> name,
      Value<String?> schedule,
      Value<String?> prompt,
      Value<String?> deliver,
      Value<bool?> enabled,
      Value<String?> state,
      Value<String?> lastRunAt,
      Value<String?> lastStatus,
      Value<String?> nextRunAt,
      Value<String> syncStatus,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedJobsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedJobsTable> {
  $$CachedJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get gatewayId => $composableBuilder(
    column: $table.gatewayId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get schedule => $composableBuilder(
    column: $table.schedule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deliver => $composableBuilder(
    column: $table.deliver,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastRunAt => $composableBuilder(
    column: $table.lastRunAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastStatus => $composableBuilder(
    column: $table.lastStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nextRunAt => $composableBuilder(
    column: $table.nextRunAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedJobsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedJobsTable> {
  $$CachedJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get gatewayId => $composableBuilder(
    column: $table.gatewayId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get schedule => $composableBuilder(
    column: $table.schedule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deliver => $composableBuilder(
    column: $table.deliver,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastRunAt => $composableBuilder(
    column: $table.lastRunAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastStatus => $composableBuilder(
    column: $table.lastStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nextRunAt => $composableBuilder(
    column: $table.nextRunAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedJobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedJobsTable> {
  $$CachedJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get gatewayId =>
      $composableBuilder(column: $table.gatewayId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get schedule =>
      $composableBuilder(column: $table.schedule, builder: (column) => column);

  GeneratedColumn<String> get prompt =>
      $composableBuilder(column: $table.prompt, builder: (column) => column);

  GeneratedColumn<String> get deliver =>
      $composableBuilder(column: $table.deliver, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get lastRunAt =>
      $composableBuilder(column: $table.lastRunAt, builder: (column) => column);

  GeneratedColumn<String> get lastStatus => $composableBuilder(
    column: $table.lastStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nextRunAt =>
      $composableBuilder(column: $table.nextRunAt, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedJobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedJobsTable,
          CachedJob,
          $$CachedJobsTableFilterComposer,
          $$CachedJobsTableOrderingComposer,
          $$CachedJobsTableAnnotationComposer,
          $$CachedJobsTableCreateCompanionBuilder,
          $$CachedJobsTableUpdateCompanionBuilder,
          (
            CachedJob,
            BaseReferences<_$AppDatabase, $CachedJobsTable, CachedJob>,
          ),
          CachedJob,
          PrefetchHooks Function()
        > {
  $$CachedJobsTableTableManager(_$AppDatabase db, $CachedJobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> gatewayId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String?> schedule = const Value.absent(),
                Value<String?> prompt = const Value.absent(),
                Value<String?> deliver = const Value.absent(),
                Value<bool?> enabled = const Value.absent(),
                Value<String?> state = const Value.absent(),
                Value<String?> lastRunAt = const Value.absent(),
                Value<String?> lastStatus = const Value.absent(),
                Value<String?> nextRunAt = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedJobsCompanion(
                gatewayId: gatewayId,
                id: id,
                name: name,
                schedule: schedule,
                prompt: prompt,
                deliver: deliver,
                enabled: enabled,
                state: state,
                lastRunAt: lastRunAt,
                lastStatus: lastStatus,
                nextRunAt: nextRunAt,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String gatewayId,
                required String id,
                Value<String?> name = const Value.absent(),
                Value<String?> schedule = const Value.absent(),
                Value<String?> prompt = const Value.absent(),
                Value<String?> deliver = const Value.absent(),
                Value<bool?> enabled = const Value.absent(),
                Value<String?> state = const Value.absent(),
                Value<String?> lastRunAt = const Value.absent(),
                Value<String?> lastStatus = const Value.absent(),
                Value<String?> nextRunAt = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedJobsCompanion.insert(
                gatewayId: gatewayId,
                id: id,
                name: name,
                schedule: schedule,
                prompt: prompt,
                deliver: deliver,
                enabled: enabled,
                state: state,
                lastRunAt: lastRunAt,
                lastStatus: lastStatus,
                nextRunAt: nextRunAt,
                syncStatus: syncStatus,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedJobsTable,
      CachedJob,
      $$CachedJobsTableFilterComposer,
      $$CachedJobsTableOrderingComposer,
      $$CachedJobsTableAnnotationComposer,
      $$CachedJobsTableCreateCompanionBuilder,
      $$CachedJobsTableUpdateCompanionBuilder,
      (CachedJob, BaseReferences<_$AppDatabase, $CachedJobsTable, CachedJob>),
      CachedJob,
      PrefetchHooks Function()
    >;
typedef $$CachedSkillsTableCreateCompanionBuilder =
    CachedSkillsCompanion Function({
      required String gatewayId,
      required String name,
      Value<String?> description,
      Value<String?> category,
      Value<bool> enabled,
      Value<String?> provenance,
      Value<int?> usage,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedSkillsTableUpdateCompanionBuilder =
    CachedSkillsCompanion Function({
      Value<String> gatewayId,
      Value<String> name,
      Value<String?> description,
      Value<String?> category,
      Value<bool> enabled,
      Value<String?> provenance,
      Value<int?> usage,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedSkillsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedSkillsTable> {
  $$CachedSkillsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get gatewayId => $composableBuilder(
    column: $table.gatewayId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provenance => $composableBuilder(
    column: $table.provenance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get usage => $composableBuilder(
    column: $table.usage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedSkillsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedSkillsTable> {
  $$CachedSkillsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get gatewayId => $composableBuilder(
    column: $table.gatewayId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provenance => $composableBuilder(
    column: $table.provenance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get usage => $composableBuilder(
    column: $table.usage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedSkillsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedSkillsTable> {
  $$CachedSkillsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get gatewayId =>
      $composableBuilder(column: $table.gatewayId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get provenance => $composableBuilder(
    column: $table.provenance,
    builder: (column) => column,
  );

  GeneratedColumn<int> get usage =>
      $composableBuilder(column: $table.usage, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedSkillsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedSkillsTable,
          CachedSkill,
          $$CachedSkillsTableFilterComposer,
          $$CachedSkillsTableOrderingComposer,
          $$CachedSkillsTableAnnotationComposer,
          $$CachedSkillsTableCreateCompanionBuilder,
          $$CachedSkillsTableUpdateCompanionBuilder,
          (
            CachedSkill,
            BaseReferences<_$AppDatabase, $CachedSkillsTable, CachedSkill>,
          ),
          CachedSkill,
          PrefetchHooks Function()
        > {
  $$CachedSkillsTableTableManager(_$AppDatabase db, $CachedSkillsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedSkillsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedSkillsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedSkillsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> gatewayId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String?> provenance = const Value.absent(),
                Value<int?> usage = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedSkillsCompanion(
                gatewayId: gatewayId,
                name: name,
                description: description,
                category: category,
                enabled: enabled,
                provenance: provenance,
                usage: usage,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String gatewayId,
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String?> provenance = const Value.absent(),
                Value<int?> usage = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedSkillsCompanion.insert(
                gatewayId: gatewayId,
                name: name,
                description: description,
                category: category,
                enabled: enabled,
                provenance: provenance,
                usage: usage,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedSkillsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedSkillsTable,
      CachedSkill,
      $$CachedSkillsTableFilterComposer,
      $$CachedSkillsTableOrderingComposer,
      $$CachedSkillsTableAnnotationComposer,
      $$CachedSkillsTableCreateCompanionBuilder,
      $$CachedSkillsTableUpdateCompanionBuilder,
      (
        CachedSkill,
        BaseReferences<_$AppDatabase, $CachedSkillsTable, CachedSkill>,
      ),
      CachedSkill,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CachedSessionsTableTableManager get cachedSessions =>
      $$CachedSessionsTableTableManager(_db, _db.cachedSessions);
  $$CachedMessagesTableTableManager get cachedMessages =>
      $$CachedMessagesTableTableManager(_db, _db.cachedMessages);
  $$PendingOpsTableTableManager get pendingOps =>
      $$PendingOpsTableTableManager(_db, _db.pendingOps);
  $$CachedJobsTableTableManager get cachedJobs =>
      $$CachedJobsTableTableManager(_db, _db.cachedJobs);
  $$CachedSkillsTableTableManager get cachedSkills =>
      $$CachedSkillsTableTableManager(_db, _db.cachedSkills);
}
