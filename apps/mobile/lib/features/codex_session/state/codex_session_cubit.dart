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

  /// Matches incoming message identities (source Codex [threadId] and/or runtime
  /// [bridgeSessionId]) against this cubit's [sessionId] and known Bridge sessions.
  ///
  /// Note: [queueId] identifies a takeover task and is distinct from [threadId]
  /// and [bridgeSessionId].
  bool _matchesIdentity({String? threadId, String? bridgeSessionId}) {
    if (threadId != null && threadId.isNotEmpty && threadId == sessionId) {
      return true;
    }
    if (bridgeSessionId != null &&
        bridgeSessionId.isNotEmpty &&
        bridgeSessionId == sessionId) {
      return true;
    }

    for (final s in bridge.sessions) {
      final sMatchesCubit =
          s.id == sessionId || s.claudeSessionId == sessionId;
      if (sMatchesCubit) {
        if (threadId != null &&
            threadId.isNotEmpty &&
            (s.id == threadId || s.claudeSessionId == threadId)) {
          return true;
        }
        if (bridgeSessionId != null &&
            bridgeSessionId.isNotEmpty &&
            (s.id == bridgeSessionId ||
                s.claudeSessionId == bridgeSessionId)) {
          return true;
        }
      }
    }

    for (final r in bridge.recentSessions) {
      if (r.sessionId == sessionId) {
        if (threadId != null &&
            threadId.isNotEmpty &&
            r.sessionId == threadId) {
          return true;
        }
        if (bridgeSessionId != null &&
            bridgeSessionId.isNotEmpty &&
            r.sessionId == bridgeSessionId) {
          return true;
        }
      }
    }

    return false;
  }

  /// Checks if an active session exists in [bridge.sessions] corresponding to
  /// this cubit or the given target identities.
  bool _hasActiveSession({
    String? targetThreadId,
    String? targetBridgeSessionId,
  }) {
    return bridge.sessions.any((s) {
      if (s.id == sessionId || s.claudeSessionId == sessionId) {
        return true;
      }
      if (targetThreadId != null &&
          targetThreadId.isNotEmpty &&
          (s.id == targetThreadId || s.claudeSessionId == targetThreadId)) {
        return true;
      }
      if (targetBridgeSessionId != null &&
          targetBridgeSessionId.isNotEmpty &&
          (s.id == targetBridgeSessionId ||
              s.claudeSessionId == targetBridgeSessionId)) {
        return true;
      }
      return false;
    });
  }

  StreamSubscription<ServerMessage>? _errorSub;

  void _initTakeoverListeners() {
    _readOnlySub = bridge.codexReadOnlyInfoStream.listen((msg) {
      if (_matchesIdentity(threadId: msg.threadId)) {
        _isReadOnly = msg.isReadOnly;
        if (state.sessionUnavailable) {
          emit(state.copyWith(sessionUnavailable: false));
        }
        if (state.status == ProcessStatus.starting) {
          emit(state.copyWith(status: ProcessStatus.idle));
        }
      }
    });

    _resumeSub = bridge.messages.listen((msg) {
      if (msg
          case SystemMessage(
            :final subtype,
            :final sourceSessionId,
            sessionId: final createdSessionId,
          )
          when subtype == 'session_created' &&
              _matchesIdentity(
                threadId: sourceSessionId,
                bridgeSessionId: createdSessionId,
              )) {
        _onSessionResumed();
      }
    });

    _queueStatusSub = bridge.codexTakeoverQueueStatusStream.listen((msg) {
      if (!_matchesIdentity(
        threadId: msg.threadId,
        bridgeSessionId: msg.sessionId,
      )) {
        return;
      }

      if (msg.status == 'resumed' || msg.status == 'running') {
        _onSessionResumed();
      } else if (msg.status == 'completed') {
        final hasActive = _hasActiveSession(
          targetThreadId: msg.threadId,
          targetBridgeSessionId: msg.sessionId,
        );
        if (hasActive) {
          _onSessionResumed();
        } else {
          // If no active session exists (e.g. bridge restart or closed session),
          // keep read-only so next sendMessage triggers resume.
          _pendingResumeCommand = null;
          _isReadOnly = true;
        }
      }
    });

    _conflictSub = bridge.codexTakeoverConflictStream.listen((msg) {
      if (_matchesIdentity(threadId: msg.threadId)) {
        if (state.sessionUnavailable) {
          emit(state.copyWith(sessionUnavailable: false));
        }
        if (state.status == ProcessStatus.starting) {
          emit(state.copyWith(status: ProcessStatus.idle));
        }
        _onConflictEncountered(msg);
      }
    });

    _errorSub = bridge.messages.listen((msg) {
      if (msg is HistoryMessage) {
        final conflictMsg =
            msg.messages.where(isActiveWriterConflictMessage).lastOrNull;
        if (conflictMsg != null) {
          if (state.sessionUnavailable) {
            emit(state.copyWith(sessionUnavailable: false));
          }
          if (state.status == ProcessStatus.starting) {
            emit(state.copyWith(status: ProcessStatus.idle));
          }
        }
      }
      final msgSessionId = switch (msg) {
        ErrorMessage(:final sessionId) => sessionId,
        ResultMessage(:final sessionId) => sessionId,
        _ => null,
      };
      if ((msg is ErrorMessage || msg is ResultMessage) &&
          _matchesIdentity(
            threadId: msgSessionId,
            bridgeSessionId: msgSessionId,
          ) &&
          isActiveWriterConflictMessage(msg)) {
        if (state.sessionUnavailable) {
          emit(state.copyWith(sessionUnavailable: false));
        }
        if (state.status == ProcessStatus.starting) {
          emit(state.copyWith(status: ProcessStatus.idle));
        }
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
        msg.projectPath.isNotEmpty
            ? msg.projectPath
            : (state.projectPath ?? ''),
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
    final isActive = _hasActiveSession();
    if (!isActive && _isReadOnly) {
      final wasResuming = _pendingResumeCommand != null;
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

      if (!wasResuming) {
        final project = state.projectPath ?? '';
        bridge.resumeSession(
          sessionId,
          project,
          provider: Provider.codex.value,
        );
      }
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
    _errorSub?.cancel();
    return super.close();
  }
}
