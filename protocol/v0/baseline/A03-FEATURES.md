# Exact fixed-point feature map — HWP-A 0.3

`hwp_a/features.py:extract` emits **179 features**, always in lexicographic name order. All are integers in `[-10000,10000]`. The file `artifacts/feature-vector.json` supplies an exact expected vector for the first keyboard birth window. The listed expressions and the reference code, not natural-language impressions of fluent writing, determine each value.

## Shared operators

Q=10000. `ratio(n,d)=clip(floor(Q*n/d),-Q,Q)` for d≠0, and zero otherwise. `scale(n,cap)=ratio(clip(n,0,cap),cap)`. Quantile p is sorted element `max(0,ceil(n*p/100)-1)`; no interpolation. `stats(prefix,values,cap)` emits `.present`, `.p10`, `.p50`, `.p90`, `.mean` and `.spread` (p90−p10), with empty lists yielding zero and presence zero. `.mean` floors the raw mean before scaling. Histograms divide each bin count by the total list length. A value equal to an edge belongs to the bin ending at that edge.

Absent measurements are not interpreted as a real measured zero. The separate presence flag distinguishes them. A supported model can use that distinction; no median-imputation, hidden semantic encoder or external service exists.

## Definitions and caps

| Family | Exact input or rule |
|---|---|
| view.* | One-hot birth, retained, layout or global |
| roots / events / production.events | Distinct unit roots, related effects, effects creating a unit root; caps 256/1024/256 |
| production.per_root | Producing related effects / distinct unit roots |
| resolution | Declared microsecond resolution, cap 10000 |
| syntactic.barrier_fraction | Related effects marked as a fixed run barrier / related effects |
| op.* | Fraction of related effects in insert/delete/replace/move/undo/redo classes |
| source.* | Fraction of related effects with the corresponding direct/spelling/paste/generated/unknown/control classification |
| insert.length / delete.length | `len(new)` / `len(old)` in every related effect; edges 0,1,4,16,64 scalars |
| deleted.per_inserted | Sum removed / inserted lengths on splice effects only; clips at Q |
| surviving.evidence_fraction | Distinct unit roots / all new candidate roots born in the unit's producing effects |
| at_document_front | Fraction where `4*position < max(1,prestate_length)` |
| at_document_tail | Fraction where position≥prestate_length |
| navigation.* | Carried navigation distance on related effects, cap4096 |
| revision.age.* | Positive differences between touching and origin-creation transaction indices; cap4096 |
| revisited.roots | Roots touched by >1 related effects / distinct unit roots |
| revisited.repeat_fraction | Additional touches beyond each root's first touch / all touches |
| gap.* | Consecutive original transactions, same run, no barrier; gaps whose ±2*resolution interval fits one bin and ≤30s; statistics cap30s |
| gap.censored | Ineligible/nonadjacent/uncertain gap pairs / max(0,effects−1) |
| gap.bin.* | Eight bins with edges 50,150,400,1000,3000,10000,30000 milliseconds |
| context.* | Preceding scalar class 0 ordinary,1 whitespace,2 sentence terminal,3 newline; class median gap cap3s; joint gap-bin counts divided by all eligible gaps |
| gap.identical_adjacent | Adjacent eligible gaps with equal recorded values / eligible gap pairs |
| gap.concentration | Sum of squared exact gap-value frequencies / squared number of eligible gaps |
| transition.*.* | Ordered operation-class pairs over eligible consecutive gap pairs |
| motor.dwell.* | Actual matched native key/tap/gesture episode durations for production causes and IME basis; cap1s |
| motor.coverage | Available relevant dwell measurements / distinct relevant motor references |
| motor.actions_per_production | Floored motor-reference count / producing effects; then cap32 |
| edit.distance.* | Absolute difference between next edit position and preceding edit position+new length; cap4096 |
| edit.backward / remote | Fraction with next position less than previous position / positional distance>32 |
| revision.cancel_fraction | Related splice events reintroducing exactly a nonempty deleted string from the preceding8 related effects within5s / all related effects |
| revision.propagation_present/fraction | Eligible replacement opportunities exist / same exact old→new replacement recurs within64 subsequent related effects at position distance>32; strings≤64 scalars |
| revision.lexical_coupling.* | Trigram Jaccard between replacement new text and up to128 subsequently inserted scalars from8 following related effects; capQ |
| burst.roots.* | New unit roots per burst; break at transaction nonadjacency, run change, or >1s gap; cap256 |
| pause.next_insert_correlation | Integer centered correlation of eligible gap and following new-text length; zero for <3 pairs/zero variance |
| shift.gap | Range of median gaps across4 chronological quarters, each scaled at3s; only adjacent uninterrupted gaps≤30s |
| shift.revision | Range of revision-operation fractions across4 chronological quarters |

The quarter-shift gap summary uses the recorded quantized adjacent differences; the finer contextual histogram separately applies its uncertainty-bin rule. Neither claims unavailable sub-resolution precision. Copy and standalone navigation effects are absent from the related-event list; movement and undo/redo remain, and navigation attaches to a later related mutation.

Lexical coupling is not logical premise tracking. A high value can arise in scripted text; a genuine writer can have no revisions and therefore no coupling measurements. No single positive feature forces a positive verdict. Complete calibration determines the useful joint region.

## Ordered feature names

The exact ordered names are the lexicographically sorted keys of [artifacts/feature-vector.json](artifacts/feature-vector.json), identical to the `FEATURE_NAMES` tuple in the reference extractor. That machine-readable artifact supplies all 179 names and one exact synthetic expected value per name; no separately maintained numeric index list overrides it.

## Second-pass qualification

The feature values remain the same 179-dimensional representation; the revised capture, adequacy, source, claim and admission gates surround it. Motor episode durations are cached without changing their values. Production adequacy is computed separately by connected delivery components, not the `motor.actions_per_production` feature. The meaningful text-collision regression is an intentional negative result: this feature map does not uniquely encode wording or cognitive causation. No semantic-encoder capability is implied.
