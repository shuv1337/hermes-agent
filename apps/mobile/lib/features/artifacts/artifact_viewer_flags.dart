/// Feature gate for the in-app artifact viewer: the chip that appears under
/// an agent-written `.md`/`.html` file in the transcript and opens it via
/// `ArtifactViewerScreen`.
///
/// **Paused, not removed, for v1's App Store resubmission.** Owner's call:
/// "we can pause the html and md file rendering, not needed for v1." The
/// implementation is good and fully tested — it is coming back — so nothing
/// was deleted:
///
///  * Detection (`artifact_detection.dart`), the sandboxed renderer
///    (`artifact_sandbox.dart`, `artifact_viewer_screen.dart`), and every
///    test under `test/artifacts/` and `test/demo/demo_artifacts_test.dart`
///    are untouched and still exercised directly against real seed data.
///  * Only two things read this flag: `SessionChatScreenState
///    ._knownArtifactPaths` (skips indexing the transcript for written-file
///    paths when off) and `_MessageBubble`'s artifact detection (skips
///    rendering the chip when off) in `session_chat_screen.dart`. Nothing
///    else about the scroll/transcript machinery in that file changed.
///
/// To re-enable:
///
///  1. Flip this to `true`.
///  2. Re-add `_latencyReviewSession(now)` as the first entry of
///     `DemoFixtures.buildSessions` (`lib/core/demo/demo_fixtures.dart`) —
///     it is still built by `latencyReviewSessionForTests`, just not wired
///     into the seeded list while this flag is off.
///  3. Bump the seeded-session-count assertion in
///     `test/demo/demo_gateway_server_test.dart` back up by one, and restore
///     (or re-verify) the "is the most recent session" expectation removed
///     from `test/demo/demo_artifacts_test.dart`.
///  4. Restore the App Review tour step and the "two agent-written files"
///     mention in `APP_REVIEW_NOTES.md` (both were deliberately removed —
///     that document must describe only what the shipped build does).
///  5. Run `flutter test` — the artifact/detection/sandbox suites should
///     already be green; re-verify the chip actually renders end to end.
const bool kArtifactViewerEnabled = false;
