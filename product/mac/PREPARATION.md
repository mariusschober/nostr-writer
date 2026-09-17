# Preparation evidence — 2026-09-16

> Recovered historical preparation; read the [current recovery notice](RECOVERY-NOTES.md) before relying on source availability or test claims.

This is a coding-agent handoff, not a built Mac application. Eight detailed PLANs, eight short STARTs and sixty mandatory release criteria are present. The handoff checker verifies their structure, relative links and exact frozen source transport; it does not approve application behaviour.

The portable WriterFoundation package executed 47 passing Swift tests on Linux with Swift 6.2.1. Ten preparation/bootstrap tests passed. All 178 frozen HWP conformance tests passed in four bounded groups (107, 23, 44 and 4), with zero failures, errors or skips. The independent public-verification checker passed. The original large vector was regenerated outside the frozen directory and matched its exact digest; the complete bootstrap reconstructed the original 69-file freeze and passed its inventory check.

A first all-in-one frozen test invocation exceeded the tool time budget without reporting assertion failures. It is not counted as a pass; the subsequent complete partitions provide the recorded evidence. A first Swift compilation also exceeded a call budget; the completed rerun supplies the 47-test result.

No native Mac application, AppKit UI, File Provider lifecycle, NostrShot native build, Word/Pages export round-trip, Developer ID signature or notarized distribution was tested in this environment. No real HWP model/capture release is approved and no real human proof was issued. The stage acceptance reports must supply that future implementation evidence rather than inheriting a green preparation status.

The frozen source's original dates, tests and provenance remain intact. The input digest in INPUTS.md selects the final freeze, not an earlier progress report. Stage 01 must run the documented checkout bootstrap and native environment checks before adopting code.
