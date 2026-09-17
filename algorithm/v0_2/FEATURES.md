# Exact fixed-point feature map

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

001. `at_document_front`
002. `at_document_tail`
003. `burst.roots.mean`
004. `burst.roots.p10`
005. `burst.roots.p50`
006. `burst.roots.p90`
007. `burst.roots.present`
008. `burst.roots.spread`
009. `context.0.gap.0`
010. `context.0.gap.1`
011. `context.0.gap.2`
012. `context.0.gap.3`
013. `context.0.gap.4`
014. `context.0.gap.5`
015. `context.0.gap.6`
016. `context.0.gap.7`
017. `context.0.pause`
018. `context.0.present`
019. `context.1.gap.0`
020. `context.1.gap.1`
021. `context.1.gap.2`
022. `context.1.gap.3`
023. `context.1.gap.4`
024. `context.1.gap.5`
025. `context.1.gap.6`
026. `context.1.gap.7`
027. `context.1.pause`
028. `context.1.present`
029. `context.2.gap.0`
030. `context.2.gap.1`
031. `context.2.gap.2`
032. `context.2.gap.3`
033. `context.2.gap.4`
034. `context.2.gap.5`
035. `context.2.gap.6`
036. `context.2.gap.7`
037. `context.2.pause`
038. `context.2.present`
039. `context.3.gap.0`
040. `context.3.gap.1`
041. `context.3.gap.2`
042. `context.3.gap.3`
043. `context.3.gap.4`
044. `context.3.gap.5`
045. `context.3.gap.6`
046. `context.3.gap.7`
047. `context.3.pause`
048. `context.3.present`
049. `delete.length.0`
050. `delete.length.1`
051. `delete.length.2`
052. `delete.length.3`
053. `delete.length.4`
054. `delete.length.5`
055. `deleted.per_inserted`
056. `edit.backward`
057. `edit.distance.mean`
058. `edit.distance.p10`
059. `edit.distance.p50`
060. `edit.distance.p90`
061. `edit.distance.present`
062. `edit.distance.spread`
063. `edit.remote`
064. `events`
065. `gap.bin.0`
066. `gap.bin.1`
067. `gap.bin.2`
068. `gap.bin.3`
069. `gap.bin.4`
070. `gap.bin.5`
071. `gap.bin.6`
072. `gap.bin.7`
073. `gap.censored`
074. `gap.concentration`
075. `gap.identical_adjacent`
076. `gap.mean`
077. `gap.p10`
078. `gap.p50`
079. `gap.p90`
080. `gap.present`
081. `gap.spread`
082. `insert.length.0`
083. `insert.length.1`
084. `insert.length.2`
085. `insert.length.3`
086. `insert.length.4`
087. `insert.length.5`
088. `motor.actions_per_production`
089. `motor.coverage`
090. `motor.dwell.mean`
091. `motor.dwell.p10`
092. `motor.dwell.p50`
093. `motor.dwell.p90`
094. `motor.dwell.present`
095. `motor.dwell.spread`
096. `navigation.mean`
097. `navigation.p10`
098. `navigation.p50`
099. `navigation.p90`
100. `navigation.present`
101. `navigation.spread`
102. `op.delete`
103. `op.insert`
104. `op.move`
105. `op.redo`
106. `op.replace`
107. `op.undo`
108. `pause.next_insert_correlation`
109. `production.events`
110. `production.per_root`
111. `resolution`
112. `revision.age.mean`
113. `revision.age.p10`
114. `revision.age.p50`
115. `revision.age.p90`
116. `revision.age.present`
117. `revision.age.spread`
118. `revision.cancel_fraction`
119. `revision.lexical_coupling.mean`
120. `revision.lexical_coupling.p10`
121. `revision.lexical_coupling.p50`
122. `revision.lexical_coupling.p90`
123. `revision.lexical_coupling.present`
124. `revision.lexical_coupling.spread`
125. `revision.propagation_fraction`
126. `revision.propagation_present`
127. `revisited.repeat_fraction`
128. `revisited.roots`
129. `roots`
130. `shift.gap`
131. `shift.revision`
132. `source.control`
133. `source.direct`
134. `source.generated`
135. `source.paste`
136. `source.spelling`
137. `source.unknown`
138. `surviving.evidence_fraction`
139. `syntactic.barrier_fraction`
140. `transition.delete.delete`
141. `transition.delete.insert`
142. `transition.delete.move`
143. `transition.delete.redo`
144. `transition.delete.replace`
145. `transition.delete.undo`
146. `transition.insert.delete`
147. `transition.insert.insert`
148. `transition.insert.move`
149. `transition.insert.redo`
150. `transition.insert.replace`
151. `transition.insert.undo`
152. `transition.move.delete`
153. `transition.move.insert`
154. `transition.move.move`
155. `transition.move.redo`
156. `transition.move.replace`
157. `transition.move.undo`
158. `transition.redo.delete`
159. `transition.redo.insert`
160. `transition.redo.move`
161. `transition.redo.redo`
162. `transition.redo.replace`
163. `transition.redo.undo`
164. `transition.replace.delete`
165. `transition.replace.insert`
166. `transition.replace.move`
167. `transition.replace.redo`
168. `transition.replace.replace`
169. `transition.replace.undo`
170. `transition.undo.delete`
171. `transition.undo.insert`
172. `transition.undo.move`
173. `transition.undo.redo`
174. `transition.undo.replace`
175. `transition.undo.undo`
176. `view.birth`
177. `view.global`
178. `view.layout`
179. `view.retained`
