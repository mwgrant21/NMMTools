# FOLLOW-UP: Jira live-export test (do on work machine)

**Created:** 2026-06-28 (home setup - no Jira access here)
**Do:** Monday 2026-06-29, on a domain-joined work machine with Jira Cloud access
**Owner:** Matt

The "Send to Jira" feature (merged to `master` at `257f9ff`) is fully built and
unit-tested, but the **live POST to a real Jira issue has never run** - the unit tests
mock `Invoke-RestMethod`, and the HTTP 401/404 status-message mapping is
Windows-PowerShell-5.1-only and not automated-tested. Run this once before relying on it
in the field.

## Steps

1. **Create the config** at `%PROGRAMDATA%\NMMTools\jira.json` (machine-wide):
   ```json
   {
     "BaseUrl": "https://<yoursite>.atlassian.net",
     "Email":   "<service-account-email>",
     "Token":   "<service-account-api-token>",
     "TokenProtected": false
   }
   ```
   (API token from id.atlassian.com for the shared service account.)

2. **Launch the GUI elevated**, run any tool, click **Export Ticket**. The Jira row
   should now be **enabled** (no longer "not configured").

3. **Happy path:** type a real issue key (e.g. `DESK-12345`), click **Send to Jira**.
   - Expect: green "Added comment to DESK-12345."; the comment (a `{code}` block with the
     session summary) appears on the issue in Jira, authored by the service account.
   - Confirm the dialog stays responsive during the send (non-blocking runspace).

4. **At-rest encryption:** re-open `jira.json` and confirm it is now
   `"TokenProtected": true` with an **opaque** (DPAPI-encrypted) `Token` value.

5. **Not-found path:** type a syntactically valid but non-existent key (e.g.
   `DESK-9999999`), click Send. Expect red "Issue ... not found or not accessible." (404).

6. **(Optional) Auth path:** temporarily set a bad token and confirm red
   "Authentication failed - check the Jira service account token." (401).

## If something's wrong
- Status mapping wrong/blank on failure: check `ConvertTo-NmmJiraError` in
  `src/core/10-jira.ps1` (it reads `$_.Exception.Response.StatusCode`, which is populated
  on PS 5.1 but often null on pwsh 7).
- Reference: spec `docs/superpowers/specs/2026-06-27-jira-ticket-export-design.md`,
  plan `docs/superpowers/plans/2026-06-27-jira-ticket-export.md` (Task 4, Step 5).

## When done
Delete this file (and note the result in the commit message).
