---
description: Find and execute the next available JIRA ticket end-to-end. Scoped to BACKEND tickets only. Assigns the ticket to the current Jira user.
argument-hint: "[phase number or range, e.g. 0, 1, or 0-2]"
---

You are now in **autonomous ticket execution mode** for the **BACKEND** repository. Follow the workflow in `CLAUDE.md` (section "JIRA workflow") and respect the "Architectural conventions (must read)" section strictly.

This command only picks up tickets tagged with `labels = "backend"`.

## Step 0 — Resolve the current Jira user (once per session)

Call `atlassianUserInfo` and cache the `accountId`. You will need it to assign tickets in Step 3.

## Parse arguments

User invocation: `/next $ARGUMENTS`

- If `$ARGUMENTS` is empty → no phase filter, but still scoped to backend.
- If `$ARGUMENTS` is a single number N (0-10) → only phase N, backend tickets.
- If `$ARGUMENTS` is a range `N-M` → phases N through M, backend tickets.
- Phase-to-epic key map: phase 0 = SCRUM-48, phase 1 = SCRUM-49, phase 2 = SCRUM-50, phase 3 = SCRUM-51, phase 4 = SCRUM-52, phase 5 = SCRUM-53, phase 6 = SCRUM-54, phase 7 = SCRUM-55, phase 8 = SCRUM-56, phase 9 = SCRUM-57, phase 10 = SCRUM-58.

## Step 1 — Find the next ticket

Build JQL based on parsed arguments. The `labels = "backend"` clause is MANDATORY in every variant:

**No phase filter:**
```
project = SCRUM AND status = "To Do" AND labels = "backend" AND issuetype != Epic ORDER BY "External Issue ID" ASC
```

**Single phase N:**
```
project = SCRUM AND status = "To Do" AND parent = SCRUM-<48+N> AND labels = "backend" ORDER BY "External Issue ID" ASC
```

**Phase range N-M:**
```
project = SCRUM AND status = "To Do" AND parent in (SCRUM-<48+N>, SCRUM-<48+N+1>, ..., SCRUM-<48+M>) AND labels = "backend" ORDER BY "External Issue ID" ASC
```

Run the query with `searchJiraIssuesUsingJql`.

Pick the **first** result where all dependencies (listed in the description under "Dependencies") are in status `Done`. If the lowest-numbered ticket has open dependencies, skip and check the next. If you exhaust the results without finding an unblocked ticket, **stop and report**:

```
No unblocked BACKEND tickets in <scope>.
Tickets in scope still blocked:
- task-NNN (waiting on task-MMM, task-LLL)
- ...
```

## Step 2 — Confirm before changing state

Before transitioning the ticket or creating a branch, print exactly:

```
Next ticket: SCRUM-NNN (task-NNN) — <summary>
Phase: <phase number> — <phase name>
Repo: backend
Branch: feature/task-NNN-<slug>
Story points: <X>
Dependencies: <all met / list>
Assignee will be: <current user accountId>

Proceeding...
```

Then immediately proceed to Step 3 without waiting for user confirmation.

## Step 3 — Execute the workflow

Follow the "Workflow para cada ticket" in `CLAUDE.md` end to end:

1. **Transition AND assign** the ticket in one operation:
   - Call `transitionJiraIssue` with `transition.id` for "In Progress" AND with `fields.assignee.accountId` set to the cached current user. If the assignee cannot be set in the same call, follow with `editJiraIssue` to set it. If both fail, log a warning and continue.
2. From `main` updated (`git fetch && git pull`), create a branch: `feature/task-NNN-<slug-up-to-50-chars>`.
3. Implement the full Scope. Create/modify every file in `Files`. Cover every `Acceptance criteria`.
4. **Architectural review (self-check before commit)**: Re-read the "Architectural conventions (must read)" section of `CLAUDE.md` and verify your implementation honors it. Specifically, verify:
   - Controllers contain no business logic (only param parsing, auth, single service call, serialization).
   - Jobs contain only one service call.
   - Services are single-purpose and return `ServiceResult`.
   - Models contain only schema-level concerns + tiny pure helpers.
   - No raw SQL outside Query objects.
   - Bang methods (`update!`, `save!`) used inside services; non-bang reserved for branching.
   - Indexes on every foreign key and on every column hit by `where` in hot paths.
   - Strong parameters on every write action.
   - `Time.current` everywhere, never `Time.now`.
   - Coverage stays ≥ 80%.
   If any rule is violated, refactor before committing.
5. Run `bin/rspec`. Resolve until green.
6. Run `bin/lint`. Resolve until green.
7. Stage and commit using Conventional Commits with `Refs SCRUM-NNN` in the footer. **NEVER** include "Generated with Claude Code", "Co-Authored-By: Claude", or any similar tooling-attribution footer.
8. Push the branch.
9. `gh pr create --fill --base main`, then `gh pr merge --squash --auto --delete-branch` (or without `--auto` if branch protection is unavailable on free plan).
10. Checkout `main`, pull, ensure local is clean.
11. Add a JIRA comment via `addCommentToJiraIssue` with the merged commit URL and a 1-line summary.
12. Transition the ticket to `Done` via `transitionJiraIssue`.

## Step 4 — Continue the loop

After closing the ticket, run Step 1 again with the **same** arguments. Keep looping until you exhaust the scope or hit a stop condition. When the scope is complete:

```
✓ Phase <N> (backend) complete: X tickets closed.
Next phase ready with /next <N+1>.
```

## Stop conditions

Pause and ask the user only when:

- A dependency is marked Done in JIRA but not actually implemented in the codebase.
- An `Acceptance criteria` is genuinely ambiguous and the answer would meaningfully change the architecture.
- Tests fail for reasons requiring expanded scope.
- A required credential or env var is missing.
- `gh pr merge` fails due to branch protection.
- An architectural rule (thin controllers/jobs, SOLID, GRASP) would be violated and there's no clean way to honor it within the ticket's scope.

Otherwise: keep going.
