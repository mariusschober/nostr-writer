# Cross-stage interfaces and state semantics

> Recovered historical preparation; read the [current recovery notice](../RECOVERY-NOTES.md) before relying on source availability or test claims.

This contract complements native Swift types; naming refinements are allowed, semantic changes are not. Main-actor editor ownership and Sendable immutable requests are mandatory. Do not expose a global mutable `AppState.text` to storage/network/proof services.

## Shared values

`DocumentID` is a stable UUID independent of path. `Revision` is monotonic per document session; restarts resume after the last durable revision. `SourceSnapshot` holds UUID, revision and exact UTF8 bytes; its SHA256 is computed with CryptoKit by the implementation, never by String equality. `ByteRange` is half-open and scalar-aligned; `NativeRange` is UTF16. All transformations carry pre/post snapshots and cause identity. Digests are exactly32byte SHA256 unless a frozen object explicitly says otherwise; names/revisions are not cryptographic identity.

`EditCommand` variants: directnativeinput, nativeIMEupdate/commit, knownassistance(kind), pasteexternal, internalmove/copy(reference), undo/redo(originaloperation), formatting, findreplace, externalreload, recover. Every applied command returns an ordered `MutationReceipt` with pre/postrevision, exact deleted/inserted text, nativecause references, origin classification and capturecompleteness. An appreceipt cannot be upgraded into independently observed HWPdelivery solely by serializing it twice.

`DurableRevision` identifies recoverycommit and separately savedfile revision/URL. Save UI observes these acknowledgements, not scheduled tasks. `RecoveryState` is complete/local partial/conflict/corrupt/keyunavailable. Corrupt/keyunavailable never means empty. `DocumentSession` owns a single live editor and active capture-run handle; all async completions compare input snapshot before touching UI.

## Proof state

Separate recordingState(off/observing/gap/pausedLimit), assessmentState(idle/running/unsupported/notprovable/completed), result(productionorconformance,verdict,scope,sourceDigest,release,policy,mode), and artifact(optionalexactpublicproof). Only a complete trusted production verifier output, exactcurrent bytes and scope may project a human-written display. Conformance is TESTONLY; a matching selfsignedNostr event is irrelevant. Cancelled/failed checks preserve prior historical results but never display them on changed source as current. No negative HWPsignature.

Producerinputs identify exactsource,canonicalrecord,plannedrelease,parents,authorityselection andscope. The frozen runtime is responsible for validity andadmission. V andR are separate enumcases with no fallback. Locally missing/unsupportedcapture remainsNP; no fabricated approval to satisfy interface. Oldproofimportmayverify as an exacthistoricalsource version without asserting the user'snewrevision.

## Outbox and drafts

`PublishIntent` fixes document/revision, exactbody,identityID,kind,metadata anddestination list. State graph: durableIntent→signedPersisted→sending→acceptedAtLeastOne/failed/pausedIdentity/cancelledRetries. Signedpayload andeventID are immutable; attempts attach relayID/socketgeneration/deadline/result. Cancelling before signing sendsnothing; aftersend doesnotmeanwithdrawn. PublicUI never equates firstACK with permanentstorage.

RemoteDraft state: localOnly/optedIn/pending/sending/acknowledged/conflict/expired/tombstoned/error. Exactlywhichlocalrevision got an ACK is retained. Transportfailure never clearslocaldraft; receivingremoteversion never importsprivatehistory. Identitychangessegregate encryptedcontent. PayloadusesNIP37 notcustomsyncformat. Replacementwinner usesNIP01 time/IDtie afterfullsignature validation.

## Export/focus state

ExportRequest fixesSourceSnapshot,template,paper,metadata,assets,optionalverifiedproof; resultcontainsformat,exactsource digest,outputbytes/hash,warnings. Cancellation/progress have jobID; staleresults archivednotcurrent. Companionmanifest isdescriptive, notnewHWPtransformationclaim.

FocusSession bindsDocumentID,baseline rootset/wordcount,goal,restrictions andmonotonicclock. Phases idle/active/interrupted/exiting/completed/ended. Inputgate andprogressreceive authoritative editor mutations; inventedeligible counts woulddefeatdisciplinebut never grantHWP. AppKitadapterownspresentationrestoration; reducerownstransitions. Recoveryalwaysends anoldlock. Audiofailure isseparatefromsaving/focusproof.

## Error behaviour

Every boundary uses typed failure plus a user-safe localized message, not rawexceptiondump. Preserveoriginalbytes/privatework. Security/parserfailuresfailclosed; availabilityfailureskeeptyping andrecord gaps. Never translate an unavailabletestenvironment intoPASS. Unit testsinjectfile/network/key/clock failures. Policies, algorithm andcapsare notsilentlychanged byretry logic.
