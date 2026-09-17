# PLAN 07 — voluntary locked writing and offline sound

> Recovered historical preparation; read the [current recovery notice](../RECOVERY-NOTES.md) before relying on source availability or test claims.

## Outcome and entry

From Stage06, implement the actual discipline experience without coercive system control or misleading HWP claims. Own **M46–M51**. Read FOCUS, UX U14/U15, SECURITY, DATA and the prepared FocusState tests. Keep normal focus separate from a locked session and never make proof eligibility depend on completing a goal.

## Session model and interaction

Complete the pure state reducer and persist only enough metadata to explain interruption/recovery. Support time goals1–240minutes, default25; word goals50–20000, default500. The session is bound to one document UUID and source revision at start. User choices and restrictions are shown before Start. Sound is optional. Word sessions require external insertion restrictions; time sessions allow the explicit switches documented in FOCUS.

Use continuous monotonic time, accumulating only awake foreground active writing-window time. Sleep, lockscreen, app deactivation, Space changes or a required dialog interrupt/pause rather than create fictitious active time. Detect activity transitions before accruing elapsed time. Returning to the app offers Continue/End; do not silently restart a lock after reboot or crash. Word progress uses surviving direct-entry roots created after this session start and the conservative net-word bound in FOCUS; copied text, restoring an old draft, redo of pre-session content or deleting baseline words cannot earn new writing credit. This is a discipline counter, not HWP detection.

The active bar shows the goal/remaining amount, sound control and a discoverable End Session action. It avoids a large dashboard or performance score. Ordinary Focus remains Escape-to-exit. Locked mode consumes its own in-app escape/close commands with a clear explanation, while keeping the emergency path, accessibility and system security paths available. Standard editing/undo/find remain usable when they do not violate an explicitly chosen restriction.

## App/window/screen friction through public APIs

Apply the valid AppKit presentation option combination from FOCUS; retain the previous option set and restore it on every termination path. Use native full-screen/window presentation rather than a permanent always-on-top fullscreen process. Keep the menu/Dock hidden while active where the OS supports it, discourage normal process switching and hide other Writer windows. Neutral app-owned shield windows can cover other connected displays during the opted-in session; they are not screenshots or screen monitoring.

Observe screen arrangement changes, window resign-key, screen sleep/wake, active Space changes and presentation changes. A new display must get a shield or interrupt the session visibly before claiming the multi-screen restriction remains active. Removing a display cannot strand the editor offscreen. With Stage Manager, Mission Control, OS security UI or remote-control/session changes, pause or report the limitation. The Mac's owner can force quit, change settings or restart: do not promise prevention of those paths.

Do not use disableForceQuit, private APIs, process killing, Accessibility automation, systemwide keyboard filters, privileged helpers, MDM or a global clipboard watcher. Do not block password dialogs or assistive technology. The release remains sandboxed. If an OS version cannot apply a restriction combination, Start must show which restriction is unavailable and refuse that selected locked configuration, not silently claim full protection. Ordinary writing remains available.

## Controlled insertion blocking

Enforce restrictions in the same EditorMutationGateway used by every insertion route. Cover menu/keyboard/context paste, paste-and-match-style, drag/drop, Services, programmatic import, cross-document insertion, completion and configured assistance. Do not merely disable Command-V while letting another command insert the same external text. Rejected operations change neither source nor clipboard. Internal move/undo/redo are allowed according to lineage and word-credit rules. Do not prohibit ordinary IME conversion or dead-key text input just because it arrives as a multi-scalar update.

While word-locked, disable new dictation/autocomplete/translation and any app-triggered action that would insert externally supplied wording. A pending pre-session dictation or async import must be stopped or fail revision/session validation before Start. External file-provider changes never enter the live buffer during a session: preserve conflict copies and interrupt safely. A blocked input produces a brief accessible explanation; it does not call the user's intent dishonest.

## Emergency exit and recovery

End Session is always reachable by visible button, menu and keyboard/VoiceOver. It begins a visible10-second countdown with Cancel; after expiry remove all restrictions and restore windows/presentation/sound safely. Never hide the escape action behind an undisclosed key chord or require writing more words to recover the computer. Cancellation returns to the prior active/interrupted state without charging time spent in the countdown as writing.

On fatal storage error, lost security scope needed to save, app termination request or unsafe window state, prioritize preserving text and releasing restrictions. Tests must inject exceptions at every adapter setup/teardown step and verify restoration. A watchdog may detect an app-owned inconsistency; it must not become a privileged always-running service. Crash recovery displays “Previous session interrupted” and preserved text, not a resurrected lock. No punishment, deletion or money commitment is introduced.

## Offline sounds and finishing detail

Implement tick, rain, café ambience and brown noise as local audio with volume, play/pause, looping and gentle fade. Generate brown noise/ticking from fixed native DSP with bounded amplitude, no DC buildup/clipping and deterministic test seeds; use secure/random playback seeds only where appropriate to sound, not protocol timing. Rain may be procedural. Café ambience must be an actually licensed/owned non-identifying asset or an original foley mix; a missing-download button or synthetic brown noise labelled café is not completion. Create an asset/license manifest with exact source and attribution. No copyrighted recordings scraped from streaming services.

Use AVAudioEngine/player without opening a recording device. Handle device changes, headphones disconnecting, audio interruptions and sleep. No autoplay before user intent, no background network fetch and no sensitive writing in filenames/metadata. Keep sound preference separate from session restrictions. A failed audio route cannot trap a locked session or stop saving. Test CPU/energy use and seamless loops; no abrupt loud sound on launch or resumed session.

## Verification and exit

Run pure reducer/property tests with injected clock and eligible-root counts. Run native interaction tests on one and multiple displays for all supported OS conditions, plus screen hotplug, Mission Control/Stage Manager, sleep/wake, forcedquit, apprelaunch, permissionsfailure and externalfileconflict. Exercise copy/paste through every route, IME and VoiceOver while locked. Capture a video or timestamped evidence of entering and safely exiting both time and word sessions, including the emergency countdown.

All M46–M51 pass only when the actual restrictions and disclosed limits match what is shown. The resulting feature should make voluntary escape inconvenient during ordinary use without purporting to control the device owner or authenticate composition. Stage08 will retest it in a signed sandboxed build rather than an overprivileged development process.

## Execution contract

You are the implementing coding agent, not a planning agent. Read this PLAN and the named contracts in the current checkout, inspect current HEAD, then implement and verify the assigned stage. Do not return another roadmap. Preserve unrelated changes and all frozen protocol bytes. Resolve routine API and implementation details yourself; a discovered platform limitation must be handled honestly, not by weakening provenance or claiming an unrun test passed.

Work on a stage branch from the predecessor's accepted commit. Run relevant earlier tests as well as the new tests. Keep deterministic tests independent of live relays, Apple accounts and real author keys. Native UI acceptance requires actual macOS runs; Linux results are not Mac results. Use synthetic documents and test keys only. Commit coherent source, tests, resources and reports; do not commit build products, credentials or private writing.

Write `product/mac/evidence/STAGE-07.md` with input/output commits, changed contracts, exact commands and results, screenshots/inspection where applicable, every assigned acceptance ID, remaining genuine external blockers and next-stage state. Include a machine-readable `STAGE-07.json` mapping assigned IDs to PASS/FAIL/BLOCKED and evidence paths. No required BLOCKED/FAIL row is completion. Do not edit the acceptance matrix to excuse missing work. The next stage must be able to start from the report and repository without reconstructing this conversation.
