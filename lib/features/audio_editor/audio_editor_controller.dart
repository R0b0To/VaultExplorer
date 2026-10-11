import 'package:vaultexplorer/features/video_editor/video_editor_controller.dart';

/// Editing state for the audio editor: the segments on the timeline, which one
/// is selected, keep vs cut out, and undo.
///
/// Audio has no keyframes -- every frame can start a cut -- so this is the
/// video editor's controller with an empty keyframe list: boundaries land
/// exactly where they are put, and "snapped" ranges equal planned ranges.
/// Sharing the class (rather than copying ~350 lines) keeps segment rules,
/// undo and the 0.1 s minimum identical in both editors.
class AudioEditorController extends VideoEditorController {
  AudioEditorController({required super.durationUs});
}
