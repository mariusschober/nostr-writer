# Independent preparation while Stage 01 acceptance is blocked

This local worktree is on `preparation/native-cores`, based on Stage 01 evidence
checkpoint `251a7d1`. It is not merged into `implementation/stage-01` and has not
been pushed. Stage 01 remains blocked on observed final native UI/VoiceOver/network
checks on an unlocked Mac and an actual hosted CI run. No later stage is accepted.
All 60 acceptance requirements and all frozen protocol/historical files remain
unchanged. These packages do not grant HWP authority.

- [Native wire primitives](native-wire/README.md): reviewed source in commit
  `1b4821e`, 17 isolated tests passed; the two fixture-location checks also passed
  from this worktree. The later native algorithm/protocol reports add independent
  component evidence; integrated Stage 04 acceptance remains mandatory.
- [Encrypted source recovery](storage-core/README.md): reviewed rolling recovery
  core, 46 package tests passed. The file and scheduling reports below extend
  this component evidence. Actual app integration, Keychain lifecycle, conflicts,
  local library and real provider acceptance remain mandatory Stage 02 work.
- [Native deterministic algorithm](native-algorithm/README.md): scalar replay,
  all 179 fixed-point features, model/support and complete conditional assessment
  compared with frozen Python. Its report is an earlier component checkpoint;
  approved production trust and integrated Stage 04 acceptance remain absent.
- [Native protocol and CLI](native-protocol/README.md): release/capture admission,
  private transport, conditional appraisal/finalization and offline V/R. All 44
  package tests and 59 CLI/interoperability checks passed. The native synthetic
  proof is accepted by frozen Python and Node as TEST-ONLY / NOT PROVABLE. App
  integration, accepted predecessors and full Stage 04 evidence remain mandatory.

- [Native files and bookmarks](native-files/README.md): exact coordinated reads,
  atomic replacement and conflict-copy primitives with balanced access scopes.
  All 59 storage package tests passed, including a second local process. Real
  provider, sandbox-grant and complete app lifecycle acceptance remain mandatory.

- [Recovery scheduling](recovery-scheduling/README.md): 34 virtual-clock tests
  and two real storage/file composition tests passed. Close forces the newest
  source checkpoint; recovery failure leaves ordinary source saving available.
  Actual app lifecycle, clock timing and Stage 02 acceptance remain mandatory.

After Stage 01 is accepted, create the Stage 02 branch from its accepted commit.
Review and selectively apply the storage preparation, then perform the full plan
and record actual M07-M13 evidence. Apply wire preparation only in the appropriate
later stage; do not infer stage completion from this isolated branch or its tests.
