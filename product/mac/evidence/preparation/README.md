# Independent preparation while Stage 01 acceptance is blocked

This local worktree is on `preparation/native-cores`, based on Stage 01 evidence
checkpoint `251a7d1`. It is not merged into `implementation/stage-01` and has not
been pushed. Stage 01 remains blocked on observed final native UI/VoiceOver/network
checks on an unlocked Mac and an actual hosted CI run. No later stage is accepted.
All 60 acceptance requirements and all frozen protocol/historical files remain
unchanged. These packages do not grant HWP authority.

- [Native wire primitives](native-wire/README.md): reviewed source in commit
  `1b4821e`, 17 isolated tests passed; the two fixture-location checks also passed
  from this worktree. Complete native P/V/R, algorithm parity and production
  admission remain mandatory Stage 04 work.
- [Encrypted source recovery](storage-core/README.md): reviewed rolling recovery
  core, 46 package tests passed. Actual app integration, one-second scheduling,
  Keychain lifecycle, coordinated source files, conflicts, local library and real
  provider acceptance remain mandatory Stage 02 work.
- [Native deterministic algorithm](native-algorithm/README.md): scalar replay,
  all 179 fixed-point features, model/support and complete conditional assessment
  compared with frozen Python. This does not establish capture authentication,
  approved production trust or complete P/V/R and is not Stage 04 acceptance.

After Stage 01 is accepted, create the Stage 02 branch from its accepted commit.
Review and selectively apply the storage preparation, then perform the full plan
and record actual M07-M13 evidence. Apply wire preparation only in the appropriate
later stage; do not infer stage completion from this isolated branch or its tests.
