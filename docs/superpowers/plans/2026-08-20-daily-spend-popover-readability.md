# Daily Spend Popover Readability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the daily-spend hover popover larger and reduce its visible content to a concise at-a-glance summary.

**Architecture:** Keep completeness metadata and accessibility precision unchanged in the model layer, but split visible hover copy from the detailed VoiceOver description in `PoolChartLocalization`. Update only the existing Swift Charts popover metrics and typography; aggregation and chart values remain untouched.

**Tech Stack:** Swift 6.3, SwiftUI, Swift Charts, Foundation localization, existing shell-driven Swift tests.

## Global Constraints

- Keep the chart section at `104 pt` and clamp the enlarged popover inside it.
- Use an approximately `190 pt` popover width, an `11 pt` date, and a `10 pt` body.
- Visible content is date, spent percentage, and remaining percentage only.
- Do not show pace, `at least`, `incomplete day`, or sampling-gap caveats in the visible popover.
- Preserve completeness details and daily-reference comparison in accessibility text.
- Keep Russian and English behavior equivalent.
- Do not change aggregation, forecast, verdict, account rows, or persistence.
- Run automated checks, reinstall, and relaunch; the user performs visual verification.

---

### Task 1: Concise visible copy and readable popover

**Files:**
- Modify: `Tests/InfrastructureTests.swift:230-300,1070-1110`
- Modify: `Sources/Localization.swift:225-315`
- Modify: `Sources/main.swift:55-275`

**Interfaces:**
- Consumes: `DailyPoolSpendPoint`, `DailyPoolSpendCoverage`, `PoolChartPopoverPolicy.placement(...)`.
- Produces: `PoolChartLocalization.detailLines(for:language:) -> [String]` for concise visible copy and `accessibilityValue(for:language:) -> String` for complete VoiceOver copy.

- [ ] **Step 1: Write failing localization and geometry tests**

Assert that a lower-bound Russian point renders exactly:

```swift
[
    "17 авг.",
    "Потрачено: 12% пула",
    "Осталось: 6,6%"
]
```

Assert that its accessibility value still contains `Потрачено не менее`, `Неполный день`, and the daily-reference comparison. Update edge-placement fixtures to `popoverWidth: 190` and `popoverHeight: 72`, expecting centers at `97`/`423`, vertical centers at `38`/`66`, and caret offsets at `-83`/`83`.

- [ ] **Step 2: Run tests and verify the new expectations fail**

Run: `./run-tests.sh`

Expected: localization and placement assertions fail because visible copy still contains caveats and the old popover metrics remain in the fixtures.

- [ ] **Step 3: Separate visible and accessibility copy**

Make `detailLines` return only date, `Потрачено: …% пула` / `Spent: …% of pool`, and `Осталось: …%` / `Remaining: …%`. Keep the no-data two-line state. Build `accessibilityValue` independently so lower-bound points retain precise `at least` and incomplete-day wording plus the daily-reference comparison.

- [ ] **Step 4: Increase SwiftUI popover metrics and typography**

Set width to `190`, estimated height to `72`, date font to `11`, body font to `10`, spacing to `3`, horizontal padding to `10`, and vertical padding to `8`. Continue using `PoolChartPopoverPolicy` for bounded placement and caret offset.

- [ ] **Step 5: Run all automated verification**

Run: `./run-tests.sh`

Expected: all infrastructure, AppKit, reset, and install-script tests pass.

Run: `./build.sh`

Expected: the application builds successfully.

Run: `git diff --check`

Expected: no whitespace errors.

- [ ] **Step 6: Commit the implementation**

```bash
git add Sources/Localization.swift Sources/main.swift Tests/InfrastructureTests.swift
git commit -m "fix: simplify daily spend popover"
```

- [ ] **Step 7: Reinstall and relaunch for user review**

Run: `./install.sh`

Run: `./verify-install.sh`

Expected: version `1.8.5`, ad-hoc signature, lifecycle monitor, and running installed process are verified. Do not perform visual inspection.
