---
description: Execute ONE specified BACKEND JIRA ticket end-to-end up to PR — then STOP for human review. Never merges.
argument-hint: "SCRUM-NNN"
---

You are executing **one** backend ticket, `$ARGUMENTS`, through the team's ritual.
Follow `CLAUDE.md` ("JIRA workflow" + "Architectural conventions (must read)") strictly.

The Jira project is SCRUM (cloudId `ead0eefe-a0f8-4248-9bc9-f9618abab799`). Resolve the
current user once with `atlassianUserInfo` and cache the `accountId` (used to self-assign).

This command takes the ticket up to **an open PR and then STOPS**. It NEVER merges and
NEVER moves the ticket to Done — that is a separate, human-approved step (see the hard
rule at the bottom).

Run these steps in this exact order:

## a. Re-read the ticket
`getJiraIssue` for `$ARGUMENTS` with `responseContentFormat: "markdown"`. Read the whole
description and understand every Acceptance Criterion before touching code.

## b. RECON-GATE (no coding on assumptions)
Confirm the REAL contracts the ticket touches against the current codebase: routes, params
(strong params), request/response shape, models + columns, serializers (Blueprints), jobs,
queues, service signatures, i18n keys. If anything the ticket assumes does NOT exist, or
the ticket's stated approach clashes with what's really there (wrong method signature,
column name, helper that already returns a scalar, queue name, etc.) → **STOP and report
the mismatch**. Do not invent or work around it silently.

## c. Fresh main
`git checkout main && git pull` so the branch starts from up-to-date main.

## d. Transition + self-assign (the command always forces this)
`transitionJiraIssue` to **In Progress** AND set `fields.assignee.accountId` to the cached
current user. If assignee can't be set in the same call, follow with `editJiraIssue`. If it
still fails, log a warning and continue — the state move matters more.

## e. Branch
`git checkout -b feat/scrum-NNN-<short-slug>`.

## f. Implement
Honor SOLID / GRASP and the project's architecture conventions:
- Thin controllers/jobs; business logic in single-purpose services returning `ServiceResult`.
- **OCP / extensible by default** — compose, don't add flags inline; no throwaway one-offs.
- **Multi-tournament safe**: nothing hardcoded to the World Cup, to a fixed number of
  groups, or a fixed number of teams. Derive from data (external_code, `Match#group`, etc.).
- `Time.current` (never `Time.now`); bang methods inside services; indexes on FKs / hot
  `where` columns; strong params on writes.

## g. Tests — REGRESSION-TEST-FIRST
If this is a bug fix: FIRST write/adjust a test that **FAILS against the code without the
fix** (prove it reproduces the bug — show the red run), THEN apply the fix and watch it go
green. For features, write the specs the ACs call for. Run the suite **in Docker**:
`docker compose exec -T app bundle exec rspec`. Resolve until green (coverage ≥ 80%).

## h. SMOKE TEST (real, when contracts/endpoints change)
When the change touches an endpoint or a request/response contract, exercise it **e2e
against the local backend on :3000** — not only unit tests with mocks. Paste the real
`curl`/output into the final report. (Auth-gated endpoints: log in first or hit the public
ones; for write paths, show the actual status + body.)

## i. Lint
`docker compose exec -T app bundle exec rubocop` — clean before committing (if it
auto-fixes, review the changes). Run at commit time, not per-edit.

## j. Commit
Conventional Commit whose message ENDS with `Refs SCRUM-NNN`. **NEVER** include any
tool attribution — no "Generated with Claude Code", no "Co-Authored-By: Claude", no
emoji branding, no mention of Anthropic/Claude.

## k. Push + PR
`git push -u origin <branch>`, then `gh pr create` with a hand-written body (summary +
key changes + `Refs SCRUM-NNN`). The PR body must contain NO tool attribution either.

## l. Comment on the ticket
`addCommentToJiraIssue`: the PR link, a one-line summary, and the commit SHA. If you
deviated from any AC, document it on the ticket (original AC → final AC → why).

## m. STOP
Report: the SHA, the PR link, and the smoke-test output. Do **not** merge. Wait for an
explicit human OK.

---

## ⛔ HARD RULE — merge & Done are a SEPARATE, human-approved step

**Step (m) is the end of this command.** The merge and the transition to Done are NEVER
chained onto it and NEVER run without an explicit human "merge it" / "aprobado, mergeá".

When (and only when) that explicit OK is given, the separate merge step is:
1. `gh pr merge <PR> --squash --delete-branch` with subject ending in `…(#PR)` and a body
   ending in `Refs SCRUM-NNN` (no attribution). Wait for green CI first.
2. `transitionJiraIssue` to **Done** (transition id `41`).
3. `git checkout main && git pull`; report the final squash SHA.

If there is no explicit human OK, this step does not execute. Period.

## STOP conditions (pause and report instead of pushing through)
- RECON-GATE mismatch (contract/signature/column/queue doesn't match the ticket).
- A dependency marked Done in Jira but not actually implemented.
- An AC genuinely ambiguous in a way that changes the architecture.
- About to touch a high-blast-radius shared file (`app/services/*` base, `base_controller`,
  `config/routes.rb`, shared models) in a non-trivial way — report the approach first.
- Tests fail for reasons needing expanded scope.
