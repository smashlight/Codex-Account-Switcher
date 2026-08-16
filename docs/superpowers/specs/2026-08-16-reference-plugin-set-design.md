# Reference Plugin Set — Design

**Date:** 2026-08-16
**Status:** Approved in conversation; awaiting written-spec review

## Runtime correction

End-to-end testing showed that `openai-curated-remote` is an account-synchronized server cache, not a durable installation source. Codex replaces it after launch, so copying an exact reference tree into the active remote cache cannot survive synchronization.

The saved tree is now converted into a local `account-switcher-reference` marketplace. Reference packages are installed and enabled through the bundled `codex plugin` CLI, while the account-owned remote cache is left untouched. The initial launch still lets account synchronization settle; reconciliation then runs from a stopped state followed by one final launch. Final verification checks the local marketplace installation and explicit curated plugins rather than requiring the remote cache to match.

## Goal

Keep one account-independent reference set of user and integration plugins active after every Codex account switch. Plugins introduced by the target account must be removed from the active set, while Codex system plugins remain untouched.

## Scope

The reference set covers:

- the complete `~/.codex/plugins/cache/openai-curated-remote` tree, including plugin versions and support packages;
- explicitly installed `openai-curated` plugin identifiers that are part of the saved reference manifest.

The reference set does not manage:

- `openai-bundled` plugins such as Browser, Chrome, Computer Use, Sites, and Visualize;
- `openai-primary-runtime` plugins such as Documents, PDF, Presentations, Spreadsheets, and Template Creator;
- OAuth grants or other account-bound authorization tokens.

The initial reference is captured from the currently active canonical account. Its observed remote packages are `cloudflare`, `openai-templates`, `plugin-management`, `product-design`, `superpowers`, and `vercel`. GitHub is retained as the canonical explicitly installed curated plugin. The temporary duplicate local installation `superpowers@openai-curated` is not part of the reference because `superpowers` is already supplied by `openai-curated-remote`.

## User Experience

Settings gains one action: **Save Current Plugins as Reference**.

Selecting it:

1. reads the active user/integration plugin set;
2. writes a new reference snapshot atomically;
3. reports the captured plugin count and identifiers;
4. leaves the previous reference intact if capture or verification fails.

After a successful account switch, the existing switch transcript reports one reference-plugin outcome:

- reference already matched;
- reference applied, including added and removed counts;
- reference unavailable because none has been saved;
- reference application failed and rollback restored the previous active set.

No automatic reference update occurs during account switching. Account-provided plugins can never silently enter the reference.

## Storage

Reference data lives outside `~/.codex` under the switcher's Application Support directory:

```text
~/Library/Application Support/Codex Account Switcher/reference-plugins/
├── manifest.json
└── openai-curated-remote/
```

`manifest.json` contains a schema version, capture timestamp, sorted remote package identifiers, and sorted explicitly installed `openai-curated` plugin identifiers. It contains no account IDs, email addresses, OAuth tokens, or other credentials.

The remote cache snapshot preserves the exact package versions and files needed to restore packages that are not available through the current CLI marketplace, notably `product-design`.

## Switching Data Flow

The account switch remains transactional:

1. save the active auth snapshot;
2. switch and verify the target account;
3. terminate the Codex process tree;
4. run the existing bundled-plugin repair;
5. launch Codex once and wait for target-account plugin synchronization to settle, bounded by a timeout;
6. terminate Codex again;
7. reconcile user/integration plugins against the saved reference;
8. launch Codex with the reconciled reference set;
9. verify Codex is running and record the result.

Synchronization is considered settled when the remote cache inventory and modification timestamps remain unchanged across two consecutive polls. The wait is bounded; a timeout proceeds to reconciliation using the latest observed state and is recorded in the transcript.

## Reconciliation

Remote packages use an atomic directory replacement:

1. copy the saved reference into a sibling staging directory;
2. verify that the staged identifiers exactly match the manifest;
3. move the active `openai-curated-remote` directory to a timestamped rollback path;
4. move the staged reference into the active path;
5. re-read the active inventory and require exact equality with the manifest;
6. restore the rollback directory if any operation or verification fails.

This exact replacement removes target-account packages that are not in the reference and restores missing reference packages. Successful reconciliation keeps a bounded number of rollback snapshots; pruning never touches the active directory or the saved reference.

Explicit `openai-curated` plugins are reconciled through the bundled Codex CLI. Missing reference identifiers use `codex plugin add`. Installed non-reference identifiers use `codex plugin remove`, except for protected system entries. Every command has a timeout and its result is included in the reconciliation outcome. A CLI failure triggers rollback of local configuration and cache changes where possible and reports the remaining discrepancy.

## Safety and Failure Handling

- Never read, copy, modify, or log `auth.json`, account registries, OAuth grants, or tokens.
- Never mutate `openai-bundled` or `openai-primary-runtime` as part of reference reconciliation.
- Never delete the active remote cache before a verified staging copy and rollback path exist.
- Reference capture and application are idempotent.
- A missing or corrupt reference prevents reconciliation and leaves the account-synchronized set untouched.
- A repair failure does not roll back the authenticated account switch; it is reported as a plugin reconciliation failure.
- OAuth-backed plugins may require authorization on each ChatGPT account even when their files are restored.

## Components

Pure, AppKit-free infrastructure in `Sources/AppInfrastructure.swift`:

- `ReferencePluginManifest`: Codable schema for reference metadata.
- `ReferencePluginInventory`: discovers sorted remote and explicit curated plugin identifiers.
- `ReferencePluginStore`: atomically captures and validates the saved reference.
- `ReferencePluginReconciler`: stages, swaps, verifies, rolls back, and returns a structured outcome.

Thin integration in `Sources/main.swift`:

- settings action for explicit capture;
- bounded post-switch synchronization wait;
- reconciliation between the synchronization launch and final Codex launch;
- concise transcript formatting.

## Testing

Infrastructure tests use temporary fixture trees and injected command runners. Required cases:

- capture writes a manifest and exact remote snapshot;
- failed capture preserves the previous reference;
- matching active/reference sets are a no-op;
- missing reference packages are restored;
- target-account-only packages are removed from the active set;
- missing and extra packages are reconciled together;
- unavailable `product-design` is restored from the saved files without marketplace access;
- staged-copy or post-swap verification failure restores the previous active set;
- missing/corrupt reference leaves the active set unchanged;
- curated CLI add/remove receives only the expected identifiers;
- bundled and primary-runtime plugins are never passed to removal;
- repeated reconciliation is idempotent;
- synchronization polling stops on stability and respects its timeout.

Verification requires `./run-tests.sh`, `./build.sh`, installation, installed-bundle verification, reference capture on the canonical account, and one real switch to a different account confirming exact user/integration plugin equality.

## Success Criteria

After switching to any saved account:

- active user/integration plugin identifiers exactly equal the saved reference;
- plugins supplied only by the target account are absent;
- all bundled and primary-runtime plugins remain available;
- reference packages unavailable from the current marketplace still work from the saved snapshot;
- failures preserve either the pre-reconciliation active set or a verified rollback and produce a clear transcript entry.
