import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../models/messages.dart';
import '../../chat_session/state/chat_session_cubit.dart';
import '../../chat_session/state/chat_session_state.dart';

/// Codex-specific session cubit.
///
/// Extends [ChatSessionCubit] so that shared widgets
/// (`ChatMessageList`, `ChatInputWithOverlays`, etc.) that read
/// `context.read<ChatSessionCubit>()` continue to work.
///
/// Reliably manages read-only monitor mode, resume-then-send flow,
/// conflict handling, and automatic takeover queueing.
class CodexSessionCubit extends ChatSessionCubit {
  static const _uuid = Uuid();

  bool _isReadOnly;
  ({
    String text,
    List<({Uint8List bytes, String mimeType})>? images,
    Iterable<String>? mentionablePaths,
  })? _pendingResumeCommand;

  StreamSubscription<ServerMessage>? _resumeSub;
  StreamSubscription<CodexTakeoverConflictMessage>? _conflictSub;
  StreamSubscription<CodexTakeoverQueueStatusMessage>? _queueStatusSub;
  StreamSubscription<CodexReadOnlyInfoMessage>? _readOnlySub;

  CodexSessionCubit({
    required super.sessionId,
    required super.bridge,
    required super.streamingCubit,
    super.initialExplorerCurrentPath,
    super.initialRecentPeekedFiles,
    super.initialSandboxMode,
    super.initialPermissionMode,
    super.initialCodexApprovalPolicy,
    super.initialCodexApprovalsReviewer,
    super.initialCodexPermissionsMode,
    super.initialProjectPath,
    bool? isReadOnly,
  })  : _isReadOnly = isReadOnly ??
            !bridge.sessions.any(
              (s) => s.id == sessionId || s.claudeSessionId == sessionId,
            ),
        super(provider: Provider.codex) {
    _initTakeoverListeners();
  }

  bool get isReadOnlySession => _isReadOnly;
  bool get hasPendingResumeCommand => _pendingResumeCommand != null;

  void _initTakeoverListeners() {
    bool matchesThread(String threadId) {
      if (threadId == sessionId) return true;
      for (final s in bridge.sessions) {
        if ((s.id == sessionId || s.claudeSessionId == sessionId) &&
            (s.id == threadId || s.claudeSessionId == threadId)) {
          return true;
        }
      }
      return false;
    }

    _readOnlySub = bridge.codexReadOnlyInfoStream.listen((msg) {
      if (matchesThread(msg.threadId)) {
        _isReadOnly = msg.isReadOnly;
        if (state.sessionUnavailable) {
          emit(state.copyWith(sessionUnavailable: false));
        }
      }
    });

    _resumeSub = bridge.messages.listen((msg) {
      if (msg
          case SystemMessage(
            :final subtype,
            :final sourceSessionId,
            sessionId: final createdSessionId,
          ) when subtype == 'session_created' &&
              (matchesThread(sourceSessionId ?? '') ||
                  matchesThread(createdSessionId ?? ''))) {
        _onSessionResumed();
      }
    });

    _queueStatusSub = bridge.codexTakeoverQueueStatusStream.listen((msg) {
      if (matchesThread(msg.threadId) &&
          (msg.status == 'resumed' ||
              msg.status == 'running' ||
              msg.status == 'completed')) {
        _onSessionResumed();
      }
    });

    _conflictSub = bridge.codexTakeoverConflictStream.listen((msg) {
      if (matchesThread(msg.threadId)) {
        if (state.sessionUnavailable) {
          emit(state.copyWith(sessionUnavailable: false));
        }
        _onConflictEncountered(msg);
      }
    });
  }

  void _onSessionResumed() {
    _isReadOnly = false;
    if (state.sessionUnavailable) {
      emit(state.copyWith(sessionUnavailable: false));
    }
    final pending = _pendingResumeCommand;
    if (pending != null) {
      _pendingResumeCommand = null;
      super.sendMessage(
        pending.text,
        images: pending.images,
        mentionablePaths: pending.mentionablePaths,
      );
    }
  }

  void _onConflictEncountered(CodexTakeoverConflictMessage msg) {
    final pending = _pendingResumeCommand;
    if (pending != null) {
      _pendingResumeCommand = null;
      bridge.enqueueCodexTakeover(
        sessionId,
        msg.projectPath.isNotEmpty ? msg.projectPath : (state.projectPath ?? ''),
        queuedCommand: pending.text,
      );
    }
  }

  @override
  void sendMessage(
    String text, {
    List<({Uint8List bytes, String mimeType})>? images,
    Iterable<String>? mentionablePaths,
  }) {
    final isActive = bridge.sessions.any(
      (s) => s.id == sessionId || s.claudeSessionId == sessionId,
    );
    if (!isActive && _isReadOnly) {
      _pendingResumeCommand = (
        text: text,
        images: images,
        mentionablePaths: mentionablePaths,
      );
      final clientMessageId = _uuid.v4();
      final entry = UserChatEntry(
        text,
        sessionId: sessionId,
        clientMessageId: clientMessageId,
        imageBytesList: images?.map((i) => i.bytes).toList(),
        status: MessageStatus.sending,
      );
      emit(state.copyWith(entries: [...state.entries, entry]));

      final project = state.projectPath ?? '';
      bridge.resumeSession(sessionId, project, provider: Provider.codex.value);
      return;
    }

    super.sendMessage(
      text,
      images: images,
      mentionablePaths: mentionablePaths,
    );
  }

  void takeControl({String? command}) {
    if (command != null && command.trim().isNotEmpty) {
      sendMessage(command.trim());
    } else {
      final project = state.projectPath ?? '';
      bridge.resumeSession(sessionId, project, provider: Provider.codex.value);
    }
  }

  @override
  Future<void> close() {
    _resumeSub?.cancel();
    _conflictSub?.cancel();
    _queueStatusSub?.cancel();
    _readOnlySub?.cancel();
    return super.close();
  }
}
