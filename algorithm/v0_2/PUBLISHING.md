# Applying this iteration to nostr-writer

The supplied archive contains only the new `algorithm/` directory. The accompanying `HWP-A-0.2.0.patch` is an additive Git patch; it does not alter the prior foundation or cryptographic files.

This execution environment did not provide a working GitHub write route. No remote commit is claimed for this iteration. The patch was locally applied in a clean repository and the resulting files/tests were checked.

From an authenticated checkout of `mariusschober/nostr-writer`:

```sh
git status --short
git apply --check /path/to/HWP-A-0.2.0.patch
git apply /path/to/HWP-A-0.2.0.patch
cd algorithm
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
cd ..
git add algorithm
git commit -m "Specify and implement HWP-A 0.2 human-writing verification algorithm"
git push
```

Review any existing `algorithm/` paths before applying; `git apply --check` will reject conflicts rather than overwrite another contributor's files. Use the repository's current branch/protection workflow rather than forcing a branch update. The local publication-check failure is recorded in the delivery report, not disguised as a successful push.

The scripts regenerate synthetic results and exact vectors. They do not collect human data, authenticate capture, approve a detector, or create a HUMAN-WRITTEN certificate.
