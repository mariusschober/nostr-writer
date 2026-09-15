# Archival verification, timestamps and renewal

## What survives the company

The mandatory `.hwp` package contains exact document bytes, every public object needed by the positive proof graph, public keys, scopes, captures, appraisals, author associations and exact algorithm-release artifacts. The relying party separately retains its chosen policy bytes and trusted pin. Essential artifact references must resolve locally; neither a content hash, URL, relay nor blockchain can recover lost bytes.

Retain at least two independently administered copies, plus the versioned specification, reference and independent verifier implementations, conformance vectors, build/runtime descriptions and policy provenance. This is an operational recommendation, not a cryptographic availability guarantee. For disclosed verification also retain the complete private openings, lineage salts and compatible installed release runner. Losing those private objects prevents recomputation but does not retroactively change an attested proof's signed claim.

The plain-text/Markdown exact-byte claim does not certify the rendering of a PDF, Word file or web page. Preserve original UTF-8 bytes. An exported asset requires a separately specified mapping/hard binding; matching visible words after normalization is not enough.

## Two independent questions

(1) Do these exact signatures, commitments, scopes and appraisals verify under policy P?
(2) Is P acceptable to the relying party now, or was it justified at a specific historical time?

Core HWP-C answers(1), labels P by its digest and externally supplied status_as_of, and reports timestamp as not assessed. Raw role-key grants are atemporal: they do not silently prove validity-before-expiry, issuance-before-compromise or absence of later revocation. An offline 2026 snapshot cannot establish that no compromise was discovered in2031. A new policy may reject an old proof without altering its historical bytes.

A historical acceptance claim must retain the trust/approval decisions, their effective dates, signer authorization/status evidence and a trustworthy independent existence bound. If key compromise happened at t_c, an existence upper bound strictly before t_c can support pre-compromise existence, but only if the status investigation reliably bounds the compromise and the timestamp itself is trusted. Claimed signing times or the author's clock cannot supply that bound. This core does not create fictitious long-term status evidence.

## RFC3161 profile implemented here

Archive the exact encoded TimeStampToken (`ContentInfo/SignedData/TSTInfo`), not merely a pending request or HTTP response. TSTInfo is checked for canonical DER; outer CMS encoding is parsed and verified as supported by the ASN.1/OpenSSL backends and is retained byte-for-byte, not rewritten by ASN.1 reserialization. Unknown critical TSTInfo extensions reject. For first archival anchoring, timestamp the **exact complete `.hwp` bytes**, including all required appraisals/endorsements. Store the token outside that package to avoid a self-reference. Compute SHA-256 of those exact package bytes as a locator, distinct from the root Proof Ref.

The timestamp request uses a SHA-256 or SHA-512 imprint, certReq=true, and where an online request is made a fresh random nonce of at least128 bits. The portable adapter API accepts an externally selected expected nonce when checking a request/response exchange; omit it only when validating an already archived token with no request-freshness claim.

The verifier supplies its own TSA CA anchors, allowed timestamp policy OIDs and certificate validation time. The implemented adapter checks the exact message imprint, TSTInfo profile, timestamp policy, nonce when supplied, signature and chain through OpenSSL. It exposes genTime and declared accuracy. Under the trusted TSA policy, genTime+accuracy is the maximum claimed time by which the timestamped bytes existed. It is not when writing began, how long someone thought or when a key signed. If accuracy is absent, the adapter reports no numeric existence_upper_bound; obtain the policy's justified uncertainty separately.

Revocation is explicitly `not-assessed` by this adapter. OpenSSL verification at an externally selected historical time is not a complete long-term-validation engine. Archive and verify appropriate issuer chains, TSA authorization, CRLs/OCSP or other governing status evidence separately according to the chosen trust framework. An embedded self-signed TSA certificate grants no trust. Tokens in tests are local synthetic TSA fixtures, not public notarizations of this project.

## Hash/signature renewal before obsolescence

No finite cryptosystem is promised secure forever. Ed25519 is not a post-quantum signature. Do not treat a new hash of an old digest as upgrading already broken content binding. Renewal must occur while the old evidence remains valid and must cover the **actual prior bytes**, the old verification evidence and their previous existence attestations.

Use RFC4998 Evidence Record Syntax with an independently reviewed implementation. The helper `archive_inventory` creates canonical input to such an archival process:

`{v:"hwp-c/1",type:"archive-inventory",sha512_objects:[[SHA512(bytes),bytes],...],bundle_sha512:bstr64,policy_sha512:bstr64}`.

Entries are sorted by digest and deduplicated; bundle and policy bytes are included, not just their hashes. Add old timestamp tokens, certificates/status evidence, verifier/profile artifacts and any previous complete evidence record as attachments. Timestamp/renew the exact inventory bytes under the selected stronger archival suite. RFC4998 timestamp renewal and hash-tree renewal have distinct rules; this helper is an inventory, not an ERS implementation or an automatic proof of longevity.

An archival verification procedure must work backward from currently acceptable evidence, checking each timestamp/evidence record and its covered objects, then validating each earlier layer under its historical policy while the relevant algorithms were still acceptable. Missing layers, untrusted time bounds, already-compromised primitives before renewal or unknown authorization yield an indeterminate historical claim, not successful validation. Before a credible quantum threat, establish an appropriately standardized reviewed post-quantum/hybrid archival suite; simply changing the COSE algorithm number in an old proof is forbidden.

## OpenTimestamps and public logs

OpenTimestamps may anchor the exact complete package/inventory bytes as an optional decentralized prior-existence record. Preserve a completed Bitcoin-attested proof, not just an unupgraded calendar promise. Verification requires an accepted Bitcoin chain-validation basis; a lone attacker-selected header is not enough. Bitcoin block time is not an exact wall-clock creation time. This package does not implement OpenTimestamps validation.

A transparency receipt under RFC9942 can attest inclusion of a well-defined package digest/claim in an externally trusted log. It does not attest composition or that the log saw every attempted session. A receipt is independent supporting evidence; its schema and log policy must name exactly which bytes/digest were logged. Fork detection needs compared consistency evidence and the log's trust assumptions. No new public chain, per-keystroke transactions or global anti-Sybil claim is required.
