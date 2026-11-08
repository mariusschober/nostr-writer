# HWP v0 adversarial audit

This directory contains an executable adversarial audit of the frozen Human Writing
Protocol v0 in `protocol/v0/`. No frozen file was modified.

- [`REPORT.md`](REPORT.md) — verdict, attack table, strongest honest claim, gap-closing
  analysis, reproduction commands.
- [`THREAT-MODEL.md`](THREAT-MODEL.md) — in-principle analysis of the required attack
  classes with protocol section citations.
- [`attacks/`](attacks/) — seven standalone attack scripts plus a common harness and
  runner. They build synthetic traces, invoke the Python R verifier and the independent
  JavaScript V verifier, and never patch verifier code.
- [`evidence/`](evidence/) — raw command outputs, exact verifier verdicts, protocol
  citation excerpts, environment facts and the attack summary.

Run everything:

```sh
.venv-hwp/bin/python audit/attacks/run_all.py
```

The report's findings are conditional on the stated trust inputs: no real human session,
trained production model, native capture path or Mac application was observed.
