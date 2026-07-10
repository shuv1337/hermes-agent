import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hermes_mobile/core/models/context_usage.dart';
import 'package:hermes_mobile/core/models/hermes_models.dart';
import 'package:hermes_mobile/core/config/reasoning_effort.dart';
import 'package:hermes_mobile/core/network/dashboard_client.dart';
import 'package:hermes_mobile/core/network/gateway_ws_client.dart';
import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/core/services/feedback.dart';
import 'package:hermes_mobile/core/services/slash_commands.dart';
import 'package:hermes_mobile/core/sync/completion_errors.dart';
import 'package:hermes_mobile/core/sync/session_sync_repository.dart';
import 'package:hermes_mobile/core/sync/session_touch.dart';
import 'package:hermes_mobile/core/theme/hermes_skins.dart';
import 'package:hermes_mobile/features/models/model_picker_sheet.dart';
import 'package:hermes_mobile/features/skills/skills_picker_sheet.dart';
import 'package:hermes_mobile/features/sessions/chat_composer.dart';
import 'package:hermes_mobile/features/sessions/context_usage_sheet.dart';
import 'package:hermes_mobile/features/sessions/message_markdown.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

/// Full-screen chat for an existing session (pushed from drawer / deep link).
class SessionChatScreen extends ConsumerStatefulWidget {
  const SessionChatScreen({
    super.key,
    required this.session,
    this.embedded = false,
    this.initialMessage,
    this.initialAttachments = const [],
    this.onSessionUpdated,
    this.onNewChat,
    this.onOpenSessionId,
  });

  final HermesSession session;

  /// When true, no AppBar back — used inside the Claude-style home shell.
  final bool embedded;

  /// If set, auto-send once after the chat mounts (new-chat from home).
  final String? initialMessage;

  /// Images picked on the home composer before the session existed.
  final List<PendingImage> initialAttachments;

  final ValueChanged<HermesSession>? onSessionUpdated;

  /// `/new` / `/reset` — parent starts a fresh chat shell.
  final VoidCallback? onNewChat;

  /// `/resume <id>` — parent opens that session if known.
  final ValueChanged<String>? onOpenSessionId;

  @override
  ConsumerState<SessionChatScreen> createState() => SessionChatScreenState();
}

class SessionChatScreenState extends ConsumerState<SessionChatScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final _speaker = ReplySpeaker();

  List<HermesMessage> _messages = const [];
  List<PendingImage> _attachments = const [];
  bool _loading = true;
  bool _sending = false;
  bool _queuedHint = false;
  bool _readAloud = false;
  String? _error;
  String? _toolStatus;
  late HermesSession _session;
  StreamSubscription<SessionTouch>? _touchSub;
  StreamSubscription<GatewayWsEvent>? _runtimeSub;
  var _didSendInitial = false;
  String? _lastSpokenAssistantId;
  UsageStats? _usage;
  ContextBreakdown? _contextBreakdown;
  String? _sessionModel;
  String? _sessionProvider;
  String? _sessionReasoningEffort;
  bool? _sessionFastMode;
  Future<void>? _runtimeHydration;

  HermesSession get session => _session;

  /// Show typing/thinking row until first stream token arrives.
  bool get _showThinkingBubble {
    if (!_sending) return false;
    final hasStream = _messages.any(
      (m) =>
          m.isAssistant &&
          m.id.startsWith('stream_') &&
          (m.content?.trim().isNotEmpty ?? false),
    );
    return !hasStream;
  }

  /// Generic waiting copy — covered by the dots bubble; don't also print it.
  bool get _toolStatusIsGeneric {
    final s = (_toolStatus ?? '').trim().toLowerCase();
    if (s.isEmpty) return true;
    return s == L10n.current.thinking.toLowerCase() ||
        s == 'thinking…' ||
        s == 'thinking...' ||
        s == 'thinking' ||
        s == 'writing…' ||
        s == 'writing...' ||
        s == 'writing';
  }

  /// Status strip only for real progress (tools, upload), not duplicate "Thinking".
  bool get _showStatusStrip {
    if (_toolStatus == null || _toolStatus!.trim().isEmpty) return false;
    if (_showThinkingBubble && _toolStatusIsGeneric) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _sessionModel = widget.session.model;
    _attachments = List.of(widget.initialAttachments);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenLive();
      _runtimeHydration = _hydrateSessionRuntime();
      unawaited(_runtimeHydration);
      _maybeSendInitial();
      unawaited(_refreshContextUsage());
    });
  }

  Future<void> _hydrateSessionRuntime() async {
    final sync = ref.read(sessionSyncProvider);
    if (sync == null) return;

    // A historical session owns its runtime model/options. Wait for the
    // resume handshake before falling back to the phone-wide new-chat pick.
    try {
      await _runtimeHydration;
    } catch (_) {}
    final runtime = await sync.fetchSessionRuntime(_session.id);
    if (!mounted || runtime == null) return;
    _applySessionRuntime(runtime);
  }

  void _applySessionRuntime(SessionRuntimeState runtime) {
    if (!mounted) return;
    final nextModel = runtime.model ?? _sessionModel;
    setState(() {
      _sessionModel = nextModel;
      _sessionProvider = runtime.provider ?? _sessionProvider;
      _sessionReasoningEffort =
          runtime.reasoningEffort ?? _sessionReasoningEffort;
      _sessionFastMode = runtime.fastMode ?? _sessionFastMode;
      if (nextModel != null && nextModel.isNotEmpty) {
        _session = HermesSession(
          id: _session.id,
          source: _session.source,
          userId: _session.userId,
          model: nextModel,
          title: _session.title,
          startedAt: _session.startedAt,
          endedAt: _session.endedAt,
          endReason: _session.endReason,
          messageCount: _session.messageCount,
          toolCallCount: _session.toolCallCount,
          lastActive: _session.lastActive,
          preview: _session.preview,
          parentSessionId: _session.parentSessionId,
        );
      }
    });
    widget.onSessionUpdated?.call(_session);
  }

  Future<void> _refreshContextUsage({bool fullBreakdown = false}) async {
    try {
      await _runtimeHydration;
    } catch (_) {}
    final sync = ref.read(sessionSyncProvider);
    if (sync == null || !mounted) return;
    try {
      final usage = await sync.fetchSessionUsage(_session.id);
      if (!mounted) return;
      if (usage != null) {
        setState(() => _usage = (_usage ?? const UsageStats()).merge(usage));
      }
      if (fullBreakdown || _contextBreakdown == null) {
        try {
          final bd = await sync.fetchContextBreakdown(_session.id);
          if (!mounted) return;
          setState(() {
            _contextBreakdown = bd;
            if (bd.contextMax > 0) {
              _usage = (_usage ?? const UsageStats()).merge(
                UsageStats(
                  contextUsed: bd.contextUsed,
                  contextMax: bd.contextMax,
                  contextPercent: bd.contextPercent,
                  model: bd.model,
                ),
              );
            }
          });
        } catch (_) {
          // Breakdown needs a built agent; usage alone is still useful.
        }
      }
    } catch (_) {}
  }

  Future<void> _openContextUsage() async {
    hermesHaptic(HapticIntent.open);
    final sync = ref.read(sessionSyncProvider);
    if (sync == null) return;
    await showContextUsageSheet(
      context,
      seedUsage: _usage,
      load: () => sync.fetchContextBreakdown(_session.id),
    );
    // Pull again after the sheet so the chip stays fresh.
    unawaited(_refreshContextUsage(fullBreakdown: true));
  }

  Future<void> _maybeSendInitial() async {
    final first = widget.initialMessage?.trim() ?? '';
    if (_didSendInitial) return;
    if (first.isEmpty && _attachments.isEmpty) return;
    _didSendInitial = true;
    // Wait for session row to settle after create.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    if (first.isNotEmpty) _composer.text = first;
    await _send();
  }

  @override
  void didUpdateWidget(covariant SessionChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.id != widget.session.id) {
      // Session id remap (local_* → server) must not wipe an in-flight turn.
      final wasSending = _sending;
      final keep = wasSending ? List<HermesMessage>.from(_messages) : null;
      _session = widget.session;
      _sessionModel = widget.session.model;
      _sessionProvider = null;
      _sessionReasoningEffort = null;
      _sessionFastMode = null;
      _runtimeHydration = _hydrateSessionRuntime();
      unawaited(_runtimeHydration);
      if (wasSending && keep != null) {
        _messages = [
          for (final m in keep)
            HermesMessage(
              id: m.id,
              sessionId: widget.session.id,
              role: m.role,
              content: m.content,
              toolCallId: m.toolCallId,
              toolCalls: m.toolCalls,
              toolName: m.toolName,
              timestamp: m.timestamp,
              tokenCount: m.tokenCount,
              finishReason: m.finishReason,
              reasoning: m.reasoning,
            ),
        ];
        // Background refresh only — do not clear the chat.
        unawaited(_softReloadMessages());
      } else {
        _messages = const [];
        _load();
      }
    }
  }

  void _listenLive() {
    final rt = ref.read(gatewayRealtimeProvider);
    if (rt == null) return;
    _touchSub?.cancel();
    _runtimeSub?.cancel();
    _touchSub = rt.sessionTouches.listen((touch) {
      if (_sending) return;
      final sid = touch.sessionId;
      if (sid != null &&
          sid.isNotEmpty &&
          sid != _session.id &&
          !sid.startsWith(_session.id) &&
          !_session.id.startsWith(sid)) {
        return;
      }
      unawaited(_softReloadMessages());
    });
    _runtimeSub = rt.events.listen(_onRuntimeEvent);
  }

  void _onRuntimeEvent(GatewayWsEvent event) {
    if (event.type != 'session.info') return;
    final sid = event.sessionId;
    final sync = ref.read(sessionSyncProvider);
    if (sid != null && sid.isNotEmpty) {
      final family = sync?.sessionIdFamily(_session.id) ?? {_session.id};
      if (!family.contains(sid) && sid != _session.id) return;
    }
    final nested = event.payload['payload'];
    final body = nested is Map ? nested.cast<String, dynamic>() : event.payload;
    _applySessionRuntime(SessionRuntimeState.fromJson(body));
  }

  Future<void> _softReloadMessages() async {
    final sync = ref.read(sessionSyncProvider);
    if (sync == null || !mounted || _sending) return;
    try {
      final merged = await sync.syncMessages(_session.id);
      if (!mounted || _sending) return;
      setState(() => _messages = _mergePreserveInflight(merged));
    } catch (_) {
      try {
        final local = await sync.loadMessagesLocal(_session.id);
        if (!mounted || _sending) return;
        setState(() => _messages = _mergePreserveInflight(local));
      } catch (_) {}
    }
  }

  /// Never drop the optimistic user bubble / live stream row when a background
  /// sync returns a partial transcript (common mid-turn).
  List<HermesMessage> _mergePreserveInflight(List<HermesMessage> incoming) {
    if (!_sending) return dedupeAdjacentUserMessages(incoming);
    final out = List<HermesMessage>.from(incoming);
    for (final m in _messages) {
      final isOptimisticUser =
          m.isUser &&
          (m.id.startsWith('local_user_') || m.id.startsWith('local_slash_'));
      final isStream = m.isAssistant && m.id.startsWith('stream_');
      if (!isOptimisticUser && !isStream) continue;
      final already = out.any((o) {
        if (o.id == m.id) return true;
        if (isOptimisticUser &&
            o.isUser &&
            (o.content ?? '').trim() == (m.content ?? '').trim()) {
          return true;
        }
        // Keep a streamed completion-error banner if sync lags.
        if (isStream &&
            o.isAssistant &&
            isCompletionErrorText(m.content) &&
            (o.content ?? '').trim() == (m.content ?? '').trim()) {
          return true;
        }
        return false;
      });
      if (!already) out.add(m);
    }
    return dedupeAdjacentUserMessages(out);
  }

  @override
  void dispose() {
    _touchSub?.cancel();
    _runtimeSub?.cancel();
    _composer.dispose();
    _scroll.dispose();
    unawaited(_speaker.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final sync = ref.read(sessionSyncProvider);
    if (sync == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final local = await sync.loadMessagesLocal(_session.id);
    if (!mounted) return;
    // Initial auto-send can race this load — never clobber an in-flight turn.
    if (_sending) {
      setState(() {
        _loading = false;
        _messages = _mergePreserveInflight(local);
      });
      return;
    }
    setState(() {
      _messages = local;
      _loading = false;
    });

    try {
      final merged = await sync.syncMessages(_session.id);
      if (!mounted) return;
      if (_sending) {
        setState(() => _messages = _mergePreserveInflight(merged));
        return;
      }
      setState(() => _messages = merged);
    } catch (e) {
      if (!mounted) return;
      if (_messages.isEmpty) {
        setState(() => _error = '$e');
      }
    }
  }

  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && _attachments.isEmpty) || _sending) return;
    _composer.text = trimmed;
    await _send();
  }

  Future<void> _uploadAttachments(SessionSyncRepository sync) async {
    if (_attachments.isEmpty) return;
    final model = _sessionModel ?? _session.model;
    final provider = _sessionProvider;
    final pending = List<PendingImage>.from(_attachments);
    for (final img in pending) {
      await sync.attachImageBytes(
        sessionId: _session.id,
        bytes: img.bytes,
        filename: img.filename,
        model: model,
        provider: provider,
      );
    }
    if (mounted) setState(() => _attachments = const []);
  }

  void _maybeSpeakAssistant(List<HermesMessage> messages) {
    if (!_readAloud) return;
    HermesMessage? lastAssistant;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isAssistant) {
        lastAssistant = messages[i];
        break;
      }
    }
    if (lastAssistant == null) return;
    if (lastAssistant.id.startsWith('stream_')) return;
    if (lastAssistant.id == _lastSpokenAssistantId) return;
    final text = lastAssistant.content?.trim() ?? '';
    if (text.isEmpty) return;
    _lastSpokenAssistantId = lastAssistant.id;
    unawaited(_speaker.speak(text));
  }

  Future<void> _stopGeneration() async {
    hermesHaptic(HapticIntent.cancel);
    final sync = ref.read(sessionSyncProvider);
    if (sync == null) return;
    try {
      await sync.interruptSession(_session.id);
    } catch (e) {
      FeedbackService.instance.error();
      if (mounted) setState(() => _error = context.l10n.stopFailed('$e'));
    }
  }

  /// User ordinal for edit/retry (Desktop `visibleUserOrdinal`).
  int? _userOrdinalForMessage(HermesMessage message) {
    final idx = _messages.indexWhere((m) => m.id == message.id);
    if (idx < 0) return null;
    if (message.isUser) {
      return SessionSyncRepository.userOrdinalAmong(_messages, idx);
    }
    // Assistant: find preceding user turn.
    for (var i = idx - 1; i >= 0; i--) {
      if (_messages[i].isUser) {
        return SessionSyncRepository.userOrdinalAmong(_messages, i);
      }
    }
    return null;
  }

  HermesMessage? _precedingUser(HermesMessage message) {
    final idx = _messages.indexWhere((m) => m.id == message.id);
    if (idx < 0) return message.isUser ? message : null;
    if (message.isUser) return message;
    for (var i = idx - 1; i >= 0; i--) {
      if (_messages[i].isUser) return _messages[i];
    }
    return null;
  }

  Future<void> _waitUntilIdle() async {
    if (!_sending) return;
    await _stopGeneration();
    for (var i = 0; i < 80 && _sending; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  /// True when this user turn never got a real assistant reply (empty tail or
  /// only an API-error / failed banner after it).
  ///
  /// While [_sending], the latest user turn is **in flight** (thinking) — not
  /// a failed turn — so we must not show "No reply yet / resend".
  bool _isUnansweredUser(HermesMessage message) {
    if (!message.isUser) return false;
    final idx = _messages.indexWhere((m) => m.id == message.id);
    if (idx < 0) return false;
    if (_sending) {
      final laterUser = _messages.skip(idx + 1).any((m) => m.isUser);
      if (!laterUser) return false;
    }
    for (var i = idx + 1; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.isUser) break;
      if (m.isSystem || m.isTool) continue;
      if (m.isAssistant) {
        final body = (m.content ?? '').trim();
        if (body.isEmpty) continue;
        if (m.finishReason == 'error' || isCompletionErrorText(body)) {
          return true;
        }
        return false;
      }
    }
    return true;
  }

  bool _isApiErrorMessage(HermesMessage message) {
    if (!message.isAssistant && !message.isSystem) return false;
    if (message.finishReason == 'error') return true;
    return isCompletionErrorText(message.content);
  }

  Future<void> _retryFrom(HermesMessage message) async {
    final user = _precedingUser(message);
    if (user == null) return;
    var text = user.content?.trim() ?? '';
    // Strip image-chip suffix from optimistic labels if present.
    if (text.contains('\n📷')) {
      text = text.split('\n📷').first.trim();
    }
    final ordinal = _userOrdinalForMessage(user);
    if (text.isEmpty) {
      if (mounted) {
        setState(() => _error = context.l10n.resubmitMessage);
      }
      return;
    }
    // Fall back to last user ordinal if id lookup failed (stale local ids).
    final resolvedOrdinal =
        ordinal ??
        SessionSyncRepository.userOrdinalAmong(
          _messages,
          _messages.lastIndexWhere((m) => m.isUser),
        );

    await _waitUntilIdle();
    if (!mounted) return;

    // Optimistic truncate: keep messages before this user turn.
    final userIdx = _messages.indexWhere((m) => m.id == user.id);
    if (userIdx >= 0) {
      setState(() {
        _messages = [
          ..._messages.take(userIdx),
          HermesMessage(
            id: user.id,
            sessionId: _session.id,
            role: 'user',
            content: text,
            timestamp: user.timestamp,
          ),
        ];
        _error = null;
      });
    }
    await _send(
      text: text,
      truncateBeforeUserOrdinal: resolvedOrdinal,
      interruptFirst: true,
      skipOptimisticAppend: true,
    );
  }

  Future<void> _editUserMessage(HermesMessage message) async {
    if (!message.isUser) return;
    final original = message.content ?? '';
    final ctrl = TextEditingController(text: original);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.editMessage),
        content: TextField(
          controller: ctrl,
          maxLines: 8,
          minLines: 3,
          autofocus: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            hintText: context.l10n.messageHintShort,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(context.l10n.saveAndResend),
          ),
        ],
      ),
    );
    // dispose after dialog closes
    // ignore: unawaited_futures
    Future<void>.delayed(const Duration(milliseconds: 100), ctrl.dispose);

    if (next == null || next.isEmpty || next == original.trim()) return;
    final ordinal = _userOrdinalForMessage(message);
    if (ordinal == null) return;

    await _waitUntilIdle();

    final userIdx = _messages.indexWhere((m) => m.id == message.id);
    if (userIdx >= 0) {
      setState(() {
        _messages = [
          ..._messages.take(userIdx),
          HermesMessage(
            id: message.id,
            sessionId: _session.id,
            role: 'user',
            content: next,
            timestamp: message.timestamp,
          ),
        ];
      });
    }
    await _send(
      text: next,
      truncateBeforeUserOrdinal: ordinal,
      interruptFirst: true,
      skipOptimisticAppend: true,
    );
  }

  Future<void> _onMessageLongPress(HermesMessage message) async {
    if (message.isTool) return;
    hermesHaptic(HapticIntent.selection);
    final isUser = message.isUser;
    final unanswered = isUser && _isUnansweredUser(message);
    final apiError = _isApiErrorMessage(message);
    // One primary re-run action: Resend (no reply / error) or Retry/Regenerate.
    // Edit is separate. No duplicate subtitles that restate the same thing.
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final l10n = ctx.l10n;
        final reRunLabel = isUser
            ? (unanswered ? l10n.resend : l10n.retry)
            : (apiError ? l10n.resend : l10n.regenerate);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isUser || apiError)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(l10n.editMessage),
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
              ListTile(
                leading: Icon(
                  unanswered || apiError ? Icons.send_outlined : Icons.refresh,
                ),
                title: Text(reRunLabel),
                onTap: () => Navigator.pop(ctx, 'retry'),
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: Text(l10n.copy),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
              if (!isUser && !apiError)
                ListTile(
                  leading: const Icon(Icons.volume_up_outlined),
                  title: Text(l10n.readAloud),
                  onTap: () => Navigator.pop(ctx, 'speak'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        final target = isUser ? message : _precedingUser(message);
        if (target != null) await _editUserMessage(target);
      case 'retry':
        await _retryFrom(message);
      case 'copy':
        final text = message.content ?? '';
        if (text.isNotEmpty) {
          hermesHaptic(HapticIntent.selection);
          await Clipboard.setData(ClipboardData(text: text));
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(context.l10n.copied)));
          }
        }
      case 'speak':
        final text = message.content ?? '';
        if (text.isNotEmpty) {
          hermesHaptic(HapticIntent.open);
          unawaited(_speaker.speakOnce(text));
        }
    }
  }

  void _appendSystem(String text) {
    if (!mounted) return;
    final body = text.trim();
    if (body.isEmpty) return;
    setState(() {
      _messages = [
        ..._messages,
        HermesMessage(
          id: 'slash_${DateTime.now().microsecondsSinceEpoch}',
          sessionId: _session.id,
          role: 'system',
          content: body,
          timestamp: DateTime.now().toUtc().toIso8601String(),
        ),
      ];
    });
  }

  /// Mobile-owned slash surfaces (mirror Desktop action handlers).
  Future<bool> _handleClientSlash(String name, String arg, String raw) async {
    switch (name) {
      case 'new':
      case 'reset':
      case 'clear':
        // clear = new session on mobile (no terminal screen clear).
        widget.onNewChat?.call();
        if (widget.onNewChat == null) {
          _appendSystem('Start a new chat from the menu (New chat).');
        }
        return true;
      case 'model':
        if (arg.isEmpty) {
          await _pickModel();
          return true;
        }
        // `/model provider:name` or bare model id — session-scope like Desktop.
        final colon = arg.indexOf(':');
        final model = colon > 0 ? arg.substring(colon + 1).trim() : arg.trim();
        final provider = colon > 0 ? arg.substring(0, colon).trim() : null;
        if (model.isEmpty) return false;
        await ref
            .read(selectedModelProvider.notifier)
            .select(model, provider: provider);
        final sync = ref.read(sessionSyncProvider);
        if (sync != null) {
          await sync.applySessionModel(
            sessionId: _session.id,
            model: model,
            provider: provider,
          );
        }
        _appendSystem(
          slashStatusText(
            raw,
            'Model set to $model${provider != null ? ' ($provider)' : ''}',
          ),
        );
        hermesHaptic(HapticIntent.success);
        return true;
      case 'title':
        if (arg.isEmpty) return false; // bare /title → gateway
        final sync = ref.read(sessionSyncProvider);
        if (sync == null) return false;
        await sync.renameSession(_session.id, arg);
        setState(() {
          _session = HermesSession(
            id: _session.id,
            source: _session.source,
            userId: _session.userId,
            model: _session.model,
            title: arg,
            startedAt: _session.startedAt,
            endedAt: _session.endedAt,
            endReason: _session.endReason,
            messageCount: _session.messageCount,
            toolCallCount: _session.toolCallCount,
            lastActive: _session.lastActive,
            preview: _session.preview,
            parentSessionId: _session.parentSessionId,
          );
        });
        widget.onSessionUpdated?.call(_session);
        _appendSystem(slashStatusText(raw, 'Session title set: $arg'));
        hermesHaptic(HapticIntent.success);
        return true;
      case 'resume':
      case 'sessions':
      case 'switch':
        if (arg.isEmpty) {
          _appendSystem(
            'Usage: /resume <session-id> — or open a chat from the drawer.',
          );
          return true;
        }
        final id = arg.split(RegExp(r'\s+')).first;
        widget.onOpenSessionId?.call(id);
        if (widget.onOpenSessionId == null) {
          _appendSystem('Open session $id from the chats drawer.');
        }
        return true;
      case 'skin':
        final skins = kBuiltinSkins;
        if (arg.isEmpty) {
          final cur = ref.read(appSkinProvider);
          final ids = skins.map((s) => s.id).toList();
          final i = ids.indexOf(cur.id);
          final next = skins[(i + 1) % skins.length];
          await ref.read(appSkinIdProvider.notifier).select(next.id);
          _appendSystem(slashStatusText(raw, 'Theme: ${next.label}'));
        } else {
          final needle = arg.toLowerCase();
          final match = skins.where(
            (s) =>
                s.id.toLowerCase() == needle || s.label.toLowerCase() == needle,
          );
          if (match.isEmpty) {
            _appendSystem(
              'Unknown skin. Try: ${skins.map((s) => s.id).join(', ')}',
            );
          } else {
            await ref.read(appSkinIdProvider.notifier).select(match.first.id);
            _appendSystem(slashStatusText(raw, 'Theme: ${match.first.label}'));
          }
        }
        hermesHaptic(HapticIntent.selection);
        return true;
      case 'stop':
        await _stopGeneration();
        _appendSystem(slashStatusText(raw, L10n.current.stopRequested));
        return true;
      case 'skills':
        // `/skills` subcommands (pending/approve/…) stay on gateway;
        // bare `/skills` opens the mobile catalog so users can pull & run.
        if (arg.trim().isNotEmpty) return false;
        await _pickAndRunSkill();
        return true;
      case 'reload-skills':
      case 'reload_skills':
        final sync = ref.read(sessionSyncProvider);
        if (sync == null) return false;
        final msg = await ref.read(skillsProvider.notifier).reloadFromGateway();
        _appendSystem(slashStatusText(raw, msg));
        hermesHaptic(HapticIntent.success);
        return true;
      default:
        return false;
    }
  }

  Future<void> _pickAndRunSkill() async {
    final cmd = await showSkillsPickerSheet(context, ref);
    if (cmd == null || !mounted) return;
    // Prefill so the user can add an instruction, or send bare.
    final withSpace = cmd.endsWith(' ') ? cmd : '$cmd ';
    _composer.value = TextEditingValue(
      text: withSpace,
      selection: TextSelection.collapsed(offset: withSpace.length),
    );
    hermesHaptic(HapticIntent.selection);
  }

  Future<void> _runSlash(String command) async {
    final sync = ref.read(sessionSyncProvider);
    if (sync == null) return;
    final model = _sessionModel ?? _session.model;
    final provider = _sessionProvider;

    hermesHaptic(HapticIntent.submit);
    setState(() {
      _composer.clear();
      _sending = true;
      _error = null;
      _toolStatus = 'Running $command…';
      _messages = [
        ..._messages,
        HermesMessage(
          id: 'local_slash_${DateTime.now().microsecondsSinceEpoch}',
          sessionId: _session.id,
          role: 'user',
          content: command,
          timestamp: DateTime.now().toUtc().toIso8601String(),
        ),
      ];
    });

    try {
      final result = await sync.runSlashCommand(
        sessionId: _session.id,
        command: command,
        model: model,
        provider: provider,
        callbacks: SlashCallbacks(
          sys: (t) {
            // Prefer slash:status framing when it's plain command output.
            _appendSystem(
              t.startsWith('slash:') ? t : slashStatusText(command, t),
            );
          },
          send: (msg) async {
            // Nested agent turn after skill/send dispatch.
            if (!mounted) return;
            setState(() => _sending = false);
            await _send(text: msg, skipOptimisticAppend: false);
          },
          prefill: (msg) {
            if (!mounted) return;
            _composer.text = msg;
            _composer.selection = TextSelection.collapsed(offset: msg.length);
          },
          onClientCommand: _handleClientSlash,
        ),
      );

      if (!mounted) return;
      if (result == SlashExecResult.error) {
        FeedbackService.instance.error();
      } else {
        hermesHaptic(HapticIntent.success);
      }
      // If send() already nested, _sending is false; otherwise clear here.
      if (_sending) {
        setState(() {
          _sending = false;
          _toolStatus = null;
        });
      } else {
        setState(() => _toolStatus = null);
      }
      unawaited(ref.read(sessionsProvider.notifier).softRefresh());
    } catch (e) {
      if (!mounted) return;
      FeedbackService.instance.error();
      setState(() {
        _sending = false;
        _toolStatus = null;
        _error = context.l10n.slashFailed('$e');
      });
      _appendSystem(slashStatusText(command, 'error: $e'));
    }
  }

  Future<void> _send({
    String? text,
    int? truncateBeforeUserOrdinal,
    bool interruptFirst = false,
    bool skipOptimisticAppend = false,
  }) async {
    final body = (text ?? _composer.text).trim();
    // Allow image-only sends (Desktop can attach then prompt "what's this?").
    final hasImages = _attachments.isNotEmpty;
    // Synchronous latch — setState is async to the next frame; double-tap
    // would otherwise append two optimistic user bubbles.
    if ((body.isEmpty && !hasImages) || _sending) return;
    final sync = ref.read(sessionSyncProvider);
    if (sync == null) return;

    // Slash path — never hit prompt.submit for `/…` (web/Desktop parity).
    if (body.isNotEmpty && looksLikeSlashCommand(body) && !hasImages) {
      await _runSlash(body);
      return;
    }

    final model =
        _sessionModel ??
        _session.model ??
        ref.read(selectedModelProvider).value;
    var provider = _sessionProvider ?? ref.read(selectedProviderProvider).value;
    final reasoningEffort =
        _sessionReasoningEffort ??
        ref.read(selectedReasoningEffortProvider).value ??
        'medium';
    final fastMode =
        _sessionFastMode ?? ref.read(selectedFastModeProvider).value ?? false;
    // Older sessions may have no persisted provider; resolve it only when the
    // catalog confirms the model's owner.
    if (model != null && model.trim().isNotEmpty) {
      final opts = ref.read(modelOptionsProvider).value;
      if (opts != null) {
        provider = providerForModel(opts, model, preferred: provider);
      }
    }
    final prompt = body.isEmpty
        ? (hasImages
              ? 'Please look at the attached image${_attachments.length > 1 ? 's' : ''}.'
              : '')
        : body;
    if (prompt.isEmpty) return;

    _sending = true;
    hermesHaptic(HapticIntent.submit);
    hermesHaptic(HapticIntent.streamStart);

    setState(() {
      if (text == null) _composer.clear();
      _sending = true;
      // Immediate feedback — don't wait for first token / tool event.
      _toolStatus = hasImages
          ? L10n.current.uploadingImage
          : L10n.current.thinking;
      _error = null;
      _queuedHint = false;
      if (!skipOptimisticAppend) {
        final label = hasImages && body.isEmpty
            ? '📷 ${_attachments.length} image${_attachments.length > 1 ? 's' : ''}'
            : (hasImages ? '$body\n📷 ${_attachments.length} image(s)' : body);
        final alreadyOptimistic = _messages.any(
          (m) =>
              m.isUser &&
              (m.id.startsWith('local_user_') || m.id.startsWith('local_')) &&
              (m.content ?? '').trim() == label.trim(),
        );
        if (!alreadyOptimistic) {
          _messages = [
            ..._messages,
            HermesMessage(
              id: 'local_user_${DateTime.now().microsecondsSinceEpoch}',
              sessionId: _session.id,
              role: 'user',
              content: label,
              timestamp: DateTime.now().toUtc().toIso8601String(),
            ),
          ];
        }
      }
      _messages = dedupeAdjacentUserMessages(_messages);
    });

    try {
      await _uploadAttachments(sync);
    } catch (e) {
      if (!mounted) return;
      FeedbackService.instance.error();
      setState(() {
        _sending = false;
        _toolStatus = null;
        _error = L10n.current.imageAttachFailed('$e');
      });
      return;
    }

    final result = await sync.sendMessage(
      sessionId: _session.id,
      input: prompt,
      model: model,
      provider: provider,
      reasoningEffort: reasoningEffort,
      fastMode: fastMode,
      truncateBeforeUserOrdinal: truncateBeforeUserOrdinal,
      interruptFirst: interruptFirst,
      onToolStatus: (s) {
        if (!mounted) return;
        setState(() {
          // Empty string = clear tool line but keep a soft "writing" cue while
          // tokens are still arriving (stream bubble covers that).
          if (s.isEmpty) {
            final hasStream = _messages.any(
              (m) => m.isAssistant && m.id.startsWith('stream_'),
            );
            _toolStatus = hasStream ? null : L10n.current.thinking;
          } else {
            _toolStatus = s;
          }
        });
      },
      onAssistantDelta: (partial) {
        if (!mounted) return;
        setState(() {
          // Tokens flowing — drop status strip (bubble is the indicator).
          if (partial.trim().isNotEmpty) {
            _toolStatus = null;
          }
          final withoutTrailingAssistant = [
            for (final m in _messages)
              if (!(m.isAssistant && m.id.startsWith('stream_'))) m,
          ];
          _messages = [
            ...withoutTrailingAssistant,
            HermesMessage(
              id: 'stream_partial',
              sessionId: _session.id,
              role: 'assistant',
              content: partial,
              timestamp: DateTime.now().toIso8601String(),
            ),
          ];
        });
      },
    );

    if (!mounted) return;
    final resultHasApiError =
        result.error != null ||
        result.messages.any((m) => isCompletionErrorText(m.content));
    if (resultHasApiError) {
      FeedbackService.instance.error();
    } else if (result.queued) {
      hermesHaptic(HapticIntent.warning);
    } else {
      FeedbackService.instance.streamDone();
      _maybeSpeakAssistant(result.messages);
    }
    setState(() {
      // Prefer server transcript, but keep optimistic user/stream if sync was empty.
      var next = dedupeAdjacentUserMessages(result.messages);
      final hasUser = next.any((m) => m.isUser);
      if (next.isEmpty || !hasUser) {
        final preserved = [
          for (final m in _messages)
            if (m.isUser || (m.isAssistant && m.id.startsWith('stream_'))) m,
        ];
        next = dedupeAdjacentUserMessages([
          ...preserved,
          for (final m in next)
            if (!preserved.any(
              (p) =>
                  p.id == m.id ||
                  (p.isUser &&
                      m.isUser &&
                      (p.content ?? '').trim() == (m.content ?? '').trim()) ||
                  (p.isAssistant &&
                      m.isAssistant &&
                      (p.content ?? '').trim() == (m.content ?? '').trim()),
            ))
              m,
        ]);
      }

      // Desktop parity: API failures must appear as an assistant bubble, e.g.
      // "API call failed after 3 retries: Connection error."
      if (result.error != null && result.error!.trim().isNotEmpty) {
        final userFacing = formatTurnErrorForUser(result.error);
        next = ensureErrorAssistantMessage(
          next,
          sessionId: _session.id,
          errorText: userFacing,
        );
        // Prefer the in-transcript banner; keep a short strip only if missing.
        _error = transcriptHasErrorAssistant(next, errorText: userFacing)
            ? null
            : userFacing;
      } else if (result.queued) {
        _error = L10n.current.savedWaitingWs;
      } else {
        _error = null;
      }

      _messages = next;
      _sending = false;
      _toolStatus = null;
      _queuedHint = result.queued;
      // Context occupancy updates after each turn (Desktop status bar).
      unawaited(_refreshContextUsage(fullBreakdown: true));
      if (result.sessionId != null && result.sessionId != _session.id) {
        _session = HermesSession(
          id: result.sessionId!,
          source: _session.source,
          userId: _session.userId,
          model: _session.model,
          title: _session.title,
          startedAt: _session.startedAt,
          endedAt: _session.endedAt,
          endReason: _session.endReason,
          messageCount: _session.messageCount,
          toolCallCount: _session.toolCallCount,
          lastActive: _session.lastActive,
          preview: _session.preview,
          parentSessionId: _session.parentSessionId,
        );
        widget.onSessionUpdated?.call(_session);
      }
    });
    unawaited(ref.read(sessionsProvider.notifier).softRefresh());
  }

  /// Look up provider slug for a model id from cached /api/model/options.
  String? _providerSlugForModel(String modelId) {
    final opts = ref.read(modelOptionsProvider).value;
    if (opts == null) return null;
    return providerForModel(opts, modelId);
  }

  Future<void> _pickModel() async {
    try {
      await _runtimeHydration;
    } catch (_) {}
    if (!mounted) return;
    final pick = await showModelPickerSheet(
      context,
      ref,
      sessionId: _session.id,
      initialModel: _sessionModel ?? _session.model,
      initialProvider: _sessionProvider,
      initialReasoningEffort: _sessionReasoningEffort,
      initialFastMode: _sessionFastMode,
    );
    if (pick == null || !mounted) return;

    final provider = (pick.provider != null && pick.provider!.trim().isNotEmpty)
        ? pick.provider
        : _providerSlugForModel(pick.model);
    final effort = pick.reasoningEffort ?? _sessionReasoningEffort ?? 'medium';
    final fast = pick.fastMode ?? _sessionFastMode ?? false;

    await ref
        .read(selectedModelProvider.notifier)
        .select(pick.model, provider: provider);
    await ref.read(selectedReasoningEffortProvider.notifier).select(effort);
    await ref.read(selectedFastModeProvider.notifier).select(fast);

    final sync = ref.read(sessionSyncProvider);
    if (sync != null) {
      try {
        await sync.applySessionModel(
          sessionId: _session.id,
          model: pick.model,
          provider: provider,
        );
        if (pick.reasoningSupported) {
          await sync.applySessionReasoning(
            sessionId: _session.id,
            effort: effort,
          );
        }
        if (pick.fastModeSupported) {
          await sync.applySessionFast(sessionId: _session.id, enabled: fast);
        }
        if (!mounted) return;
        setState(() {
          _sessionModel = pick.model;
          _sessionProvider = provider;
          _sessionReasoningEffort = effort;
          _sessionFastMode = pick.fastModeSupported ? fast : false;
          _session = HermesSession(
            id: _session.id,
            source: _session.source,
            userId: _session.userId,
            model: pick.model,
            title: _session.title,
            startedAt: _session.startedAt,
            endedAt: _session.endedAt,
            endReason: _session.endReason,
            messageCount: _session.messageCount,
            toolCallCount: _session.toolCallCount,
            lastActive: _session.lastActive,
            preview: _session.preview,
            parentSessionId: _session.parentSessionId,
          );
          _error = null;
        });
        widget.onSessionUpdated?.call(_session);
        unawaited(ref.read(sessionsProvider.notifier).softRefresh());
      } catch (e) {
        if (!mounted) return;
        FeedbackService.instance.error();
        setState(() => _error = context.l10n.modelSavedLocal('$e'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Existing sessions render their own runtime identity. The global sticky
    // pick is only a fallback for a brand-new session with no model yet.
    final modelId =
        (_sessionModel ?? _session.model ?? ref.watch(resolvedModelIdProvider))
            ?.trim() ??
        context.l10n.selectModel;
    final model = modelChipLabel(
      modelId,
      _sessionReasoningEffort ?? 'medium',
      fast: _sessionFastMode ?? false,
    );

    final body = Column(
      children: [
        // Model + context usage (Desktop status-bar parity).
        Material(
          color: theme.scaffoldBackgroundColor,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickModel,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.9,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.expand_more,
                            size: 18,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ContextUsageChip(
                  usage: _usage,
                  breakdown: _contextBreakdown,
                  onTap: _openContextUsage,
                ),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          color: theme.colorScheme.outline.withValues(alpha: 0.35),
        ),
        Expanded(
          child: _loading && _messages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                  child: Center(
                    child: Text(
                      context.l10n.sendAMessageToContinue,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                  ),
                )
              // reverse:true → newest at bottom, open already scrolled there.
              : ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  // +1 thinking/typing row while waiting for first token.
                  itemCount: _messages.length + (_showThinkingBubble ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (_showThinkingBubble && i == 0) {
                      // reverse list: index 0 is visual bottom.
                      return const _ThinkingBubble();
                    }
                    final msgIndex = _showThinkingBubble
                        ? _messages.length - i
                        : _messages.length - 1 - i;
                    final msg = _messages[msgIndex];
                    final unanswered = msg.isUser && _isUnansweredUser(msg);
                    final apiError = _isApiErrorMessage(msg);
                    return _MessageBubble(
                      message: msg,
                      unanswered: unanswered,
                      showRetryActions: unanswered || apiError,
                      onLongPress: () => _onMessageLongPress(msg),
                      onResend: () => unawaited(_retryFrom(msg)),
                      onEdit: () {
                        final target = msg.isUser ? msg : _precedingUser(msg);
                        if (target != null) {
                          unawaited(_editUserMessage(target));
                        }
                      },
                    );
                  },
                ),
        ),
        if (_showStatusStrip)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _toolStatus!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.secondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_queuedHint)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              context.l10n.queuedForSync,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ),
        ChatComposerBar(
          controller: _composer,
          sending: _sending,
          onSend: () => _send(),
          onStop: _stopGeneration,
          // Short hint — long "Message Hermes Go…" wraps under the + chip.
          hint: context.l10n.messageHintShort,
          attachments: _attachments,
          onAttachmentsChanged: (next) => setState(() => _attachments = next),
          readAloud: _readAloud,
          onReadAloudChanged: (v) {
            setState(() => _readAloud = v);
            _speaker.setEnabled(v);
            if (!v) unawaited(_speaker.stop());
          },
          slashCompleter: (text) async {
            final sync = ref.read(sessionSyncProvider);
            if (sync == null) return const [];
            return sync.completeSlashWithSkills(text);
          },
          onPickSkill: () => unawaited(_pickAndRunSkill()),
        ),
      ],
    );

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _session.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.sync,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: body,
    );
  }
}

/// Claude-style “thinking” row: pulsing dots + label while the agent works
/// before the first assistant token.
class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble();

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.55,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dots only — no "Thinking" label (status strip handles tools).
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final phase = (_ctrl.value + i * 0.2) % 1.0;
                    final t = (phase < 0.5 ? phase : 1 - phase) * 2;
                    final opacity = 0.35 + 0.65 * t;
                    final dy = -2.0 * t;
                    return Transform.translate(
                      offset: Offset(0, dy),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: Opacity(
                          opacity: opacity,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.onLongPress,
    this.onResend,
    this.onEdit,
    this.unanswered = false,
    this.showRetryActions = false,
  });

  final HermesMessage message;
  final VoidCallback? onLongPress;
  final VoidCallback? onResend;
  final VoidCallback? onEdit;
  final bool unanswered;
  final bool showRetryActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;
    final isTool = message.isTool;
    final isSystem = message.isSystem;
    // Slash/system status — strip `slash:/cmd` prefix for a cleaner label.
    var body = message.content?.trim() ?? '';
    String? slashLabel;
    if (isSystem && body.startsWith('slash:')) {
      final nl = body.indexOf('\n');
      slashLabel = nl < 0 ? body.substring(6) : body.substring(6, nl);
      body = nl < 0 ? '' : body.substring(nl + 1).trim();
    }

    // Desktop parity: provider/API failures render as error banners, not
    // normal assistant prose (e.g. "API call failed after 3 retries: …").
    final isApiError =
        !isUser &&
        (message.finishReason == 'error' || isCompletionErrorText(body));
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final radius = BorderRadius.circular(isSystem || isApiError ? 12 : 18);
    final bg = isUser
        ? theme.colorScheme.primary.withValues(alpha: 0.16)
        : isApiError
        ? theme.colorScheme.errorContainer.withValues(alpha: 0.55)
        : isTool
        ? theme.colorScheme.surfaceContainerHighest
        : isSystem
        ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.45)
        : Colors.transparent;
    final fg = isApiError
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurface;

    final bubble = Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(
        // Material long-press wins over SelectableText selection on iOS.
        onLongPress: isTool ? null : onLongPress,
        borderRadius: radius,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isUser || isTool || isSystem || isApiError ? 14 : 4,
            vertical: isUser || isTool || isSystem || isApiError ? 10 : 4,
          ),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: isSystem || isApiError || unanswered
                ? Border.all(
                    color: isApiError || unanswered
                        ? theme.colorScheme.error.withValues(alpha: 0.45)
                        : theme.colorScheme.outline.withValues(alpha: 0.25),
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isApiError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 16,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        context.l10n.error,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              if (unanswered && !isApiError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    context.l10n.noResponseYet,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (isTool || message.toolName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    message.toolName ?? 'tool',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ),
              if (slashLabel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    slashLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (body.isNotEmpty || !isSystem)
                _MessageBody(
                  text: body.isNotEmpty
                      ? body
                      : (isUser ? '' : (isSystem ? '' : '…')),
                  isUser: isUser,
                  color: fg,
                  // Selection fights long-press; copy lives in the sheet.
                  selectable: false,
                ),
            ],
          ),
        ),
      ),
    );

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.sizeOf(context).width *
              (isUser ? 0.86 : (isSystem || isApiError ? 0.92 : 0.96)),
        ),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: bubble,
            ),
            // Only the two primary recoveries — Copy / more stay on long-press.
            if (showRetryActions && !isTool)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: isUser ? WrapAlignment.end : WrapAlignment.start,
                  children: [
                    if (onResend != null)
                      ActionChip(
                        avatar: const Icon(Icons.send_outlined, size: 16),
                        label: Text(context.l10n.resend),
                        onPressed: onResend,
                        visualDensity: VisualDensity.compact,
                      ),
                    if (onEdit != null)
                      ActionChip(
                        avatar: const Icon(Icons.edit_outlined, size: 16),
                        label: Text(context.l10n.editMessage),
                        onPressed: onEdit,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.text,
    required this.isUser,
    required this.color,
    this.selectable = true,
  });

  final String text;
  final bool isUser;
  final Color color;
  final bool selectable;

  /// Cheap heuristic: plain user lines rarely need full markdown.
  bool get _looksLikeMarkdown {
    if (text.contains('```') ||
        text.contains('`') ||
        text.contains('\n- ') ||
        text.contains('\n* ') ||
        text.contains('\n#') ||
        text.contains('**') ||
        (text.contains('[') && text.contains(']('))) {
      return true;
    }
    // Short plain user messages stay plain for snappier layout.
    if (isUser && text.length < 280 && !text.contains('\n\n')) return false;
    return !isUser;
  }

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    if (!_looksLikeMarkdown) {
      final style = Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(color: color, height: 1.4);
      if (!selectable) {
        return Text(text, style: style);
      }
      return SelectableText(text, style: style);
    }
    return MessageMarkdown(data: text, color: color);
  }
}
