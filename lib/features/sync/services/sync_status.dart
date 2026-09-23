import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_plan.dart';

/// What the UI (dashboard banner, notification) shows about syncing.
@immutable
class SyncStatus {
  /// A run is transferring or deleting files right now. Runs that find
  /// nothing to do (most live-watch polls) are never reported as running,
  /// so the banner doesn't flash every minute.
  final bool running;

  /// Display name of the folder being synced with (never a file name).
  final String targetLabel;
  final int doneActions;
  final int totalActions;
  final int failedActions;

  /// How many rules' latest run needs a look: files that failed, folders
  /// that couldn't be read, or deletions that were held back as suspicious.
  final int attention;

  /// Most recent completed run, if any (used for in-app completion feedback).
  final SyncRunReport? lastCompletedReport;
  final String? lastCompletedTargetLabel;

  const SyncStatus({
    this.running = false,
    this.targetLabel = '',
    this.doneActions = 0,
    this.totalActions = 0,
    this.failedActions = 0,
    this.attention = 0,
    this.lastCompletedReport,
    this.lastCompletedTargetLabel,
  });

  /// 0..1 while [totalActions] is known, else null.
  double? get fraction =>
      totalActions > 0 ? (doneActions / totalActions).clamp(0.0, 1.0) : null;

  SyncStatus copyWith({
    bool? running,
    String? targetLabel,
    int? doneActions,
    int? totalActions,
    int? failedActions,
    int? attention,
    SyncRunReport? lastCompletedReport,
    String? lastCompletedTargetLabel,
    bool clearLastCompleted = false,
  }) {
    return SyncStatus(
      running: running ?? this.running,
      targetLabel: targetLabel ?? this.targetLabel,
      doneActions: doneActions ?? this.doneActions,
      totalActions: totalActions ?? this.totalActions,
      failedActions: failedActions ?? this.failedActions,
      attention: attention ?? this.attention,
      lastCompletedReport: clearLastCompleted
          ? null
          : (lastCompletedReport ?? this.lastCompletedReport),
      lastCompletedTargetLabel: clearLastCompleted
          ? null
          : (lastCompletedTargetLabel ?? this.lastCompletedTargetLabel),
    );
  }

  // Value equality, so a ValueNotifier<SyncStatus> only notifies on a real change.
  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.running == running &&
      other.targetLabel == targetLabel &&
      other.doneActions == doneActions &&
      other.totalActions == totalActions &&
      other.failedActions == failedActions &&
      other.attention == attention &&
      other.lastCompletedReport == lastCompletedReport &&
      other.lastCompletedTargetLabel == lastCompletedTargetLabel;

  @override
  int get hashCode => Object.hash(
    running,
    targetLabel,
    doneActions,
    totalActions,
    failedActions,
    attention,
    lastCompletedReport,
    lastCompletedTargetLabel,
  );
}
