# NMMTools v9 - Jira Ticket Export Design Specification

**Date:** 2026-06-27
**Version:** 1.0
**Status:** Approved (design)
**Scope:** GUI Ticket Export dialog (v1); reusable core function for later console parity

---

## 1. Concept

Add a "Send to Jira" action to the GUI Ticket Export dialog so a technician can push
the current session summary (`Export-TicketSummary` output) directly onto an existing
Jira Cloud issue (e.g. `DESK-12345`) as a comment, without leaving the toolkit. The
feature is additive: the existing Copy-to-Clipboard and Save-to-Desktop actions are
unchanged.

---

## 2. Decisions (locked during brainstorming 2026-06-27)

1. **Jira flavor:** Jira **Cloud** (`*.atlassian.net`). Auth = email + API token via
   HTTP Basic (`base64("email:token")`).
2. **Identity:** a single **shared service account**. All comments appear as that bot
   user; comments are not attributed to the individual technician.
3. **Token delivery / storage:** an out-of-band config file deployed **per endpoint**
   to `%PROGRAMDATA%\NMMTools\jira.json` (via PDQ/GPO). Never committed to the repo or
   baked into the artifact. Re-encrypted at rest with DPAPI (LocalMachine) on first read.
4. **Payload:** a single **comment** containing the summary wrapped in a `{code}` block.
   No attachment.
5. **Surface:** GUI only in v1. The HTTP logic lives in a reusable core function so the
   console ticket-export path (`T` key) can adopt it later with no rework.

---

## 3. Config File

**Path:** `%PROGRAMDATA%\NMMTools\jira.json`
(`[Environment]::GetFolderPath('CommonApplicationData')` + `NMMTools\jira.json`).
Machine-wide, deployed by PDQ/GPO. A `$script:JiraConfigPathOverride` hook lets tests
point at a temp file (mirrors `06-usage.ps1`'s `$script:UsageFilePathOverride`).

**Format (as deployed, plaintext):**
```json
{
  "BaseUrl": "https://acme.atlassian.net",
  "Email": "svc-nmm@acme.com",
  "Token": "<api-token>",
  "TokenProtected": false
}
```

**Secret at rest (DPAPI LocalMachine):**
On first successful load where `TokenProtected` is `false`, the tool re-saves the file
with `Token` replaced by a Base64 DPAPI ciphertext and `TokenProtected` set to `true`.
Subsequent loads decrypt transparently. This shrinks the plaintext window to the time
between deployment and first run.

- Protect: `[System.Security.Cryptography.ProtectedData]::Protect(`
  `[Text.Encoding]::UTF8.GetBytes($token), $null, [...DataProtectionScope]::LocalMachine)`
  -> bytes -> Base64. (`Add-Type -AssemblyName System.Security` on PS 5.1.)
- LocalMachine scope is deliberate: any technician on that managed endpoint can use the
  shared token; per-user (CurrentUser) scope would break when a different tech logs in.
- The re-save requires write access to `%PROGRAMDATA%\NMMTools`. The GUI runs elevated,
  so this succeeds. If the re-save ever fails (non-admin, read-only path), the failure is
  swallowed and the plaintext token is still used for the request - configuration must
  never crash the dialog.

`Import-NmmJiraConfig` returns `$null` (never throws) when the file is missing, malformed,
or the token cannot be resolved. `$null` => the feature is treated as "not configured".

---

## 4. Core Module: `src/core/10-jira.ps1`

`build.ps1` globs `src/core/*.ps1` in numeric order, so the new file is included
automatically and lands after `09-ui-wpf.ps1`'s consumers can still call it (functions
are all defined before the entry point runs).

| Function | Signature | Behavior |
|----------|-----------|----------|
| `Get-NmmJiraConfigPath` | `()` -> string | Returns the override path if set, else `%PROGRAMDATA%\NMMTools\jira.json`. |
| `Import-NmmJiraConfig` | `()` -> hashtable or `$null` | Loads + parses the JSON, decrypts the token (and performs first-run re-encryption), returns `@{ BaseUrl; Email; Token }`. Missing/corrupt/incomplete -> `$null`. Never throws. |
| `Test-NmmJiraKey` | `-Key [string]` -> bool | `$Key -cmatch '^[A-Z][A-Z0-9]+-\d+$'`. Used to gate the Send button and validate before any network call. |
| `Send-NmmJiraComment` | `-Key [string] -Body [string]` -> `@{ Success=[bool]; Message=[string] }` | Loads config; if `$null` -> `Success=$false, Message='Jira is not configured on this machine.'`. Optionally GETs the issue to verify existence/access, then POSTs the comment, wrapping `$Body` in a `{code}` block itself (callers pass the raw summary). All exceptions caught and mapped to a friendly `Message`. Never throws. |

`Send-NmmJiraComment` is the single seam the GUI calls and the single seam tests mock at
the `Invoke-RestMethod` level.

---

## 5. API Details

Jira Cloud REST **v2** (string comment body - simpler than v3's ADF JSON):

- **Verify (optional pre-check):** `GET {BaseUrl}/rest/api/2/issue/{KEY}?fields=key`
  - 200 -> issue exists and is accessible.
  - 404 -> `Message='Issue {KEY} not found or not accessible.'` (stop, no POST).
- **Post comment:** `POST {BaseUrl}/rest/api/2/issue/{KEY}/comment`
  - Headers: `Authorization: Basic <base64(email:token)>`, `Content-Type: application/json`.
  - Body: `{ "body": "{code}\n<Export-TicketSummary text>\n{code}" }` (JSON-encoded).
  - 201 -> success.
- **Transport:** force `[Net.ServicePointManager]::SecurityProtocol = Tls12` before the
  call; set a request timeout (e.g. 30s) so a hung endpoint does not freeze the dialog
  thread.

**Error -> message mapping (returned, never thrown):**

| Condition | Message |
|-----------|---------|
| No config | "Jira is not configured on this machine." |
| Invalid key format | "Enter a valid issue key, e.g. DESK-12345." (gated in UI; defense-in-depth in core) |
| 401 / 403 | "Authentication failed - check the Jira service account token." |
| 404 (verify) | "Issue {KEY} not found or not accessible." |
| Timeout / DNS / network | "Could not reach Jira ({short reason})." |
| Other non-success | "Jira returned an error ({status})." |
| 201 success | "Added comment to {KEY}." |

---

## 6. GUI Changes (`Invoke-TicketExportDialog` in `09-ui-wpf.ps1`)

Add to the existing dialog (reusing `SaveStatusLabel` for feedback):

- A **TextBox** `JiraKeyBox` preceded by an inline "Jira issue:" label (WPF has no
  native watermark; the label conveys the expected `DESK-12345` format). Input is
  upper-cased on change.
- A **Button** `SendJiraButton` ("Send to Jira") in the dialog's button row.

**Behavior:**
- On dialog open, call `Import-NmmJiraConfig`. If `$null`: disable `SendJiraButton` and
  `JiraKeyBox`, set a quiet hint ("Jira not configured") - the rest of the dialog works
  normally.
- If configured: `SendJiraButton` is enabled only when `Test-NmmJiraKey` passes on the
  current box text.
- On click: disable the button, set its content to "Sending..."; call
  `Send-NmmJiraComment -Key $JiraKeyBox.Text -Body (the ticket text already shown)`;
  on return, write `Message` to `SaveStatusLabel` (green `#4EC94E` on success, red
  `#F44747` on failure) and re-enable the button. The network call runs without blocking
  the UI thread (consistent with how the dialog already avoids freezing; implementation
  detail deferred to the plan - e.g. a short-lived runspace or async pattern).

The dialog's existing Copy/Save/Close behavior is untouched.

---

## 7. Testing (Pester 5)

New `tests/jira.tests.ps1`:

- `Test-NmmJiraKey`: accepts `DESK-12345`, `ABC1-7`; rejects `desk-12345` (lowercase),
  `DESK12345` (no dash), `12-34` (no leading letter), empty/`$null`.
- `Import-NmmJiraConfig` (via `$script:JiraConfigPathOverride`): missing file -> `$null`;
  corrupt JSON -> `$null`; incomplete (no token) -> `$null`; valid plaintext -> hashtable
  AND file rewritten with `TokenProtected:true`; DPAPI round-trip -> second load returns
  the original token.
- `Send-NmmJiraComment` with `Mock Invoke-RestMethod`: success (201) -> `Success=$true`;
  404 on verify -> not-found message, POST not attempted; 401 -> auth message; thrown
  WebException/timeout -> network message; no config -> not-configured message.

The existing `artifact.tests.ps1` build gate continues to cover that `10-jira.ps1`
compiles cleanly into the artifact and passes PSScriptAnalyzer (errors).

---

## 8. Non-Goals (v1)

1. Console-mode "Send to Jira" (the core function is reusable; wiring deferred).
2. Per-technician tokens / per-tech comment attribution.
3. File **attachments** on the issue.
4. Transitioning issue **status** or setting fields.
5. **Creating** new issues.
6. Editing or threading existing comments.
7. Central/UNC shared config (per-endpoint + DPAPI chosen instead).
8. Jira **Server / Data Center** support (Cloud only).

---

## 9. Risks / Notes

- **v2 API longevity:** Jira Cloud has deprecated some v2 endpoints over time. The
  comment endpoint still accepts a string body today; if it is ever rejected, the
  fallback is v3 with an ADF body. Out of scope for v1, noted for awareness.
- **ProgramData write permission:** first-run DPAPI re-encryption needs write access to
  `%PROGRAMDATA%\NMMTools`. The GUI runs elevated, so this is satisfied in normal use;
  failure degrades gracefully to using the plaintext token.
- **Shared-secret exposure:** a shared token deployed to every endpoint is inherently
  broader exposure than a central secret; this is an accepted tradeoff of the shared
  service-account + per-endpoint decisions. Rotation = redeploy `jira.json`.
