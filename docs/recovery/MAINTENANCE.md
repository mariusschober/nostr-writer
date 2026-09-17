# Maintaining the recovered source of truth

SOURCE-OF-TRUTH-MANIFEST.json records SHA-256 and provenance for the reconciled snapshot. It excludes itself to avoid a self-hash cycle. Git identifies the whole version. New files need explicit provenance when added to that snapshot; a deliberate change to an active product/recovery document requires updating only its corresponding manifest row after review.

Do not change recovered history/originals, RECOVERY-INVENTORY.json or protocol/v0 to make a check green. Original hashes and the frozen inventory remain independent checks. New protocol semantics belong in a new version. Current product requirements may evolve through documented decisions; their exact supplied predecessors remain archived.

For mutable app evidence and code added during future implementation, maintain stage reports and Git commits rather than representing new files as historical Astra artifacts. A passing recovery checker is never an application or empirical acceptance result.

The tag human-writing-protocol-v0 identifies the source-only frozen-distribution commit. Never force-move it. Main contains that commit plus the full recovery and product handoff.

Licensing remains component-scoped: protocol/v0/LICENSE covers that distribution; proof/hwp-c-1/LICENSE covers its stated scope. Recovery does not invent a repository-wide license or relicense upstream dependencies. Stage owners preserve notices and resolve licensing for future distribution.
