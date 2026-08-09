---
name: vendor-technical-evaluation
description: Use when evaluating third-party vendors for a Buy decision, driving or participating in a vendor technical evaluation, navigating the Draft/Review/Revision/Decision lifecycle, or handling escalations, score ties, author replacement, or failed security assessments.
---

# Vendor Technical Evaluation Process

## Overview

A structured four-phase lifecycle (Draft → Review → Revision → Decision) for selecting a third-party vendor after a Build vs. Buy process concludes with "Buy". A Director-assigned author drives the document; the Lead Director holds final decision authority at every gate.

**Pre-requisite:** Build vs. Buy process must already have concluded with a "Buy" decision.

## Process Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Unstarted : Build vs. Buy = Buy

    Unstarted --> Draft : Author assigned;\npage from template;\nmoved to Draft Evaluations folder;\nstatus → [Rough Draft]

    Draft --> AuthorReplaced : Author unavailable / MIA
    AuthorReplaced --> Draft : Director assigns replacement;\nwork resumes

    Draft --> ReadyForReview : All 5 sections complete;\nstatus → [Ready for Review];\nshared to Directors

    ReadyForReview --> Revision : Director feedback received\nwithin 5 business days

    ReadyForReview --> DirectorEscalation : High feedback volume;\nescalated to Electric Platypus\nor ad-hoc meeting
    DirectorEscalation --> Revision : Consolidated feedback recorded

    ReadyForReview --> Decision : 5 days elapsed, no feedback;\nLead Director accepts as-is or rejects

    Revision --> ReadyForReview : Major changes required\n(one loop max)
    Revision --> ScoreTie : Comparison Matrix\nproduces tied scores
    ScoreTie --> Decision : Lead Director applies\nqualitative judgment
    Revision --> Decision : All comments addressed;\nLead Director satisfied

    Decision --> NoViableVendor : All vendors fail scorecard\nor Lead Director rejects all
    NoViableVendor --> [*] : Readdress needs/scope;\nreturn to Build vs. Buy

    Decision --> Verified : Lead Director approves;\nstatus → [Verified];\nmoved to Complete Evaluations folder

    Verified --> ProcurementTipalti : Author submits PO in Tipalti;\nSecurity Assessment triggered

    ProcurementTipalti --> Complete : Assessment passes;\nnegotiations begin
    ProcurementTipalti --> Decision : Vendor blocked by security/legal;\nre-select from existing scorecard

    Complete --> [*]
```

## Phase Reference

### Phase 1: Draft
**Owner:** Author | **Status:** `[Rough Draft]`

Author creates page from the Confluence template, manually moves it to the **Draft Vendor Evaluations** folder, and completes all 5 sections:

| Section | Purpose |
|---|---|
| Overview & Objectives | Problem statement, desired outcomes, budget |
| Requirements Scorecard | Weighted requirements (informed by API Review) |
| Vendor Comparison Matrix | Quantitative scoring of vendors against requirements |
| Qualitative Feedback | Stakeholder "vibe check" per vendor |
| Recommendation | Winning vendor + executive justification |

Author may schedule vendor demos during this phase.

### Phase 2: Review
**Owner:** Directors | **Deadline:** 5 business days | **Status:** `[Ready for Review]`

Author sets status to `[Ready for Review]` and shares to Directors for async feedback.

- **High feedback volume** → escalate to Electric Platypus Director meeting or schedule ad-hoc
- **No feedback after 5 days** → Lead Director decides: accept as-is or reject

### Phase 3: Revision
**Owner:** Author | **Loop limit:** 1

Author addresses and acknowledges all Director comments, then shares final copy.

- **Major changes** → one loop back to Phase 2 (Review); after that, Lead Director makes the call
- **Score tie in Comparison Matrix** → Lead Director breaks tie using qualitative judgment
- **Lead Director** has final say on whether all comments are sufficiently addressed

### Phase 4: Decision
**Owner:** Lead Director | **Status:** `[Verified]`

Lead Director reviews and records the final decision with rationale.

- **Approved** → author sets status `[Verified]`, moves page to **Complete Vendor Evaluations** folder
- **All vendors rejected / none viable** → readdress needs/scope, return to Build vs. Buy process

## Post-Decision: Procurement

Author submits a PO request in **Tipalti** to trigger the Vendor Security Assessment.

- **Assessment passes** → proceed to vendor negotiations
- **Vendor blocked** (security/legal) → return to Phase 4 Decision, re-select from existing scorecard

Reference: [PO Process Overview](https://justworks.atlassian.net/wiki/spaces/FPO/pages/3816390998/PO+Process+Overview)

## Ownership & Escalation Summary

| Situation | Who acts |
|---|---|
| Author unavailable / MIA | Director assigns replacement |
| Feedback volume too high for async | Author or Director escalates to Electric Platypus |
| No Director feedback after 5 days | Lead Director: accept as-is or reject |
| Revision loop exceeds 1 round | Lead Director makes the call |
| Score tie in Comparison Matrix | Lead Director breaks tie qualitatively |
| Comment resolution disputed | Lead Director has final say |
| All vendors fail / rejected | Team readdresses scope, re-enters Build vs. Buy |
| Tipalti security blocks vendor | Re-select from existing scorecard at Phase 4 |

## Common Mistakes

| Mistake | Fix |
|---|---|
| Moving page to folder but not updating status label | Do both — folder AND status must reflect current phase |
| Skipping vendor demos before completing Comparison Matrix | Demos inform qualitative scoring; run them during Draft |
| Treating 5-day silence as "no opinion" | Silence transfers decision authority to Lead Director — don't proceed without their explicit call |
| Starting Phase 4 before all Revision comments are acknowledged | Lead Director must confirm comments addressed, not just the author |
| Submitting Tipalti before page is in `[Verified]` status | Verified status = audit trail that decision was made; do this first |
| Assuming Tipalti security pass is automatic | Assessment can block the vendor; keep the scorecard accessible for re-selection |
