# Primary sources used to check this revision

Accessed 2026-09-15. These references support specific external premises; none is presented as an empirical result for HWP-A.

- Angelopoulos et al., [Learn then Test](https://arxiv.org/html/2110.01052v5): fixed learned rules, calibration as finite-family testing and explicit i.i.d. sampling assumptions. HWP's exact block loss and ledger are specified here, not supplied by that paper.
- W3C, [Input Events Level 2](https://www.w3.org/TR/input-events-2/): editing intents, input event types and composition-related handling. Browser events are not represented here as proof of a protected physical input path.
- Android, [InputConnection](https://developer.android.com/reference/android/view/inputmethod/InputConnection): committed/composing text and IME-oriented editing transactions. This motivates separate normalized motor/commit/delivery observations; availability to an ordinary application is not assumed.
- Athalye, Carlini and Wagner, [Obfuscated Gradients Give a False Sense of Security](https://proceedings.mlr.press/v80/athalye18a.html), ICML 2018: a primary example of why apparent robustness must face adaptive evaluation. Its numerical results are unrelated to HWP and are not transferred.

All audit counterexamples, mathematical deductions, implementation constants and new regression results are generated in this package. No human-writing accuracy is inferred from these references.
