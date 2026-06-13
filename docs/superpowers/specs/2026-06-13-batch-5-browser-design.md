# Batch 5: Browser & Data Tools - Design Spec

**Date:** 2026-06-13
**Scope:** Port v8 Browser & Data tools (menu 48-50) into v9.
**Status:** Approved (brainstormed with Matt 2026-06-13). Next step: writing-plans -> batch 5 implementation plan.

## Goal

Port the three v8 browser tools into v9, hardening the data-safety rough edges found
in the v8 source. v8 monolith at `C:\Users\IT\Desktop\NMMTools.ps1` is READ-ONLY reference
(functions: `Backup-BrowserData` L4189, `Restore-BrowserData` L4372, `Clear-BrowserCaches` L1601,
`Get-BrowserBackupUserRoot` L4157).

## Usage model (unchanged)

Interactive technician at the keyboard; toolkit elevates at launch. Optimize the interactive
experience; `-Silent` only needs to be SAFE (report-only / refuse-destructive), not a functional
automation path. All three workflows are per-user (operate on `%LOCALAPPDATA%` / `%APPDATA%`),
so **RequiresAdmin = $false** for both tools.

**User-context caveat (note in report output):** these tools read `%LOCALAPPDATA%`/`%APPDATA%` of the
CURRENT process identity. UAC self-elevation as the SAME account keeps the same profile (correct), but
if the toolkit was elevated with a DIFFERENT admin account, the paths point at that admin's profile,
not the logged-in user's. v8 had the same behavior; v9 just surfaces a note. Not a blocker.

## Decisions made with Matt (do not re-litigate)

1. **Consolidation: merge backup + restore into one tool; clear stays separate.** Two tools total:
   - `browser-backup-restore` (LegacyId 48; legacy 49 folds in as the Restore action - typing `49`
     will NOT dispatch, consistent with prior consolidations 99->22, 27->30, 37->20+94).
   - `browser-clear` (LegacyId 50).
2. **Backup password handling: include + ACL-lock + warn.** Always back up the password stores
   (Chromium `Login Data`; Firefox `key4.db` + `logins.json`). ACL-restrict the backup folder AND
   the ZIP to the current user (`icacls "<path>" /inheritance:r /grant:r "$env:USERNAME:F"`),
   best-effort with a warning if it fails (common on network shares). Warn that **Chromium
   passwords are DPAPI-bound to this machine/user and will not decrypt if restored elsewhere;
   Firefox passwords (key4.db) DO travel.**
3. **Backup destination: keep M: preference, fallback Desktop.** Prefer `M:\BrowserBackups\<user>`;
   fall back to `<Desktop>\BrowserBackups\<user>` when M: is absent. ACL-lock applied best-effort.
4. **Clear scope: ALL profiles.** Chromium clear iterates Default + Profile* (v8 only did `Default`,
   while v8 backup iterated all profiles - this inconsistency is a v8 bug). Firefox already iterates
   all profiles.
5. **Clear preserves Firefox bookmarks.** v8 deleted `places.sqlite`, which stores bookmarks AND
   history together, assuming a prior backup. v9 KEEPS `places.sqlite` (bookmarks safe) and notes
   that FF history remains bundled there. Chromium history (separate `History` file) is still cleared.
6. **Code organization: shared core helper.** New `src\core\08-browser-helpers.ps1` holds the
   browser catalog + Close-Browsers + Get-BrowserProfiles, consumed by both tools (mirrors batch-3
   `07-repair-helpers.ps1`; core funcs are exempt from the registry-mapping test that scans
   `src\tools` only). The browser path/file table - the thing that drifted in v8 - is defined ONCE.

## Architecture

```
src\core\08-browser-helpers.ps1                       NEW shared helper (core)
src\tools\browser\Invoke-BrowserBackupRestore.ps1     -> browser-backup-restore (48/49)
src\tools\browser\Clear-BrowserData.ps1               -> browser-clear          (50)
tests\browser-helpers.tests.ps1                       NEW (locks preserve guarantees)
```

New Category `'Browser'`. Tool count **64 -> 66** (2 browser + 8 cloud + 23 diagnostics + 17 laptop
+ 16 repair). Menu becomes 5 categories, alphabetical by category name:
**A=Browser B=Cloud C=Diagnostics D=Laptop E=Repair**.

### Shared helper: `08-browser-helpers.ps1`

Single source of truth for "where does each browser store what."

- **`Get-BrowserCatalog`** - returns 4 browser definitions. Chrome/Edge/Brave are family `Chromium`;
  Firefox is family `Firefox`. The file-set lists below are illustrative; the COMPLETE v8 file lists
  (from `Clear-BrowserCaches` L1601 and `Backup-BrowserData` L4189) are enumerated verbatim during
  implementation. Each definition carries:
  - `Name`, `Family`
  - `BasePath` (Chromium: `%LOCALAPPDATA%\<vendor>\User Data`; Firefox: `%APPDATA%\Mozilla\Firefox\Profiles`)
  - `ProcessNames` (chrome / msedge / firefox / brave)
  - Named file-sets used by BOTH tools:
    - Chromium: `Passwords=@('Login Data','Login Data For Account')`, `Autofill=@('Web Data')`,
      `Bookmarks=@('Bookmarks','Bookmarks.bak')`, `Prefs=@('Preferences','Secure Preferences')`,
      `History=@('History','History-journal','Top Sites','Visited Links', ...)`,
      `Cookies=@('Cookies','Cookies-journal')`, `CacheDirs=@('Cache','Code Cache','GPUCache',
      'Service Worker\CacheStorage','Service Worker\ScriptCache')`,
      `SessionDirs=@('Session Storage','Local Storage','IndexedDB','Network','Current Session',
      'Current Tabs','Last Session','Last Tabs', ...)`
    - Firefox: `Passwords=@('key4.db','logins.json')`, `Autofill=@('formhistory.sqlite')`,
      `BookmarksHistory=@('places.sqlite', ...)` (bundled - KEPT by clear),
      `Cookies=@('cookies.sqlite', '...-shm', '...-wal')`, `CacheDirs=@('cache2')`,
      `Permissions=@('permissions.sqlite','content-prefs.sqlite', ...)`, `Favicons=@('favicons.sqlite', ...)`,
      `Prefs=@('prefs.js')`
- **`Get-BrowserProfiles -Browser <def>`** - returns installed profile directories
  (Chromium: `Default` + `Profile*`; Firefox: all dirs under Profiles). Empty array if browser absent.
- **`Close-Browsers -ProcessNames <...>`** - graceful `CloseMainWindow` -> wait -> `Kill` stragglers;
  returns the list of processes it closed. Callers gate this behind a Read-ToolChoice.

The **backup set** = Bookmarks + Prefs + History + Passwords + Autofill (+ FF places/cookies/key4/logins/prefs).
The **clear set** = Cache + Cookies + History + Sessions + Permissions, and EXCLUDES Passwords + Autofill
(+ Chromium Bookmarks, + Firefox places.sqlite). These two sets are derived from the same catalog so they
cannot drift.

### Tool 1: `browser-backup-restore` (Modifies, Admin=$false, SilentCapable)

`Invoke-BrowserBackupRestore` / `New-ToolRun -Id 'browser-backup-restore'`.

- **Report (always):** detected browsers + profile counts; most-recent existing backups under the user root.
- **Action menu:** `Read-ToolChoice -Choices @('None','Backup','Restore') -Default 'None' -Silent:$Silent`.
  Under `-Silent` -> None -> report only, no action.
- **Backup action:**
  1. Resolve user root (M: preferred, fallback Desktop).
  2. WARN: backup includes saved passwords; DPAPI cross-machine caveat.
  3. Offer to close browsers (Read-ToolChoice Yes/No, recommend Yes) -> `Close-Browsers`.
  4. For each detected browser/profile, copy the backup set into `<dest>\<Browser>\<Profile>\`.
  5. `Compress-Archive` the dest folder to `<dest>.zip`.
  6. ACL-lock the dest folder AND the ZIP to current user; warn (not fail) if `icacls` exit != 0.
  7. `Complete-ToolRun` Success: "N files backed up to <path> (ACL-locked | ACL-lock failed)".
- **Restore action:**
  1. List recent backups; select by index, OR `Read-Host` a folder/ZIP path (free-text is safe -
     only reached inside the interactive Restore branch, like the BitLocker save-path input).
  2. If ZIP, expand to `%TEMP%\NMM_BrowserRestore_<ts>`.
  3. WARN: overwrites existing browser data + DPAPI caveat. Confirm (Read-ToolChoice Yes/No, Default No).
  4. Offer to close browsers.
  5. Restore ONLY known catalog files into matching profile dirs (sanitized allow-list - do not blindly
     copy arbitrary files present in the backup folder). Create target profile dir if missing.
  6. Clean up the TEMP extraction folder.
  7. `Complete-ToolRun` Success: "N files restored from <path>".

### Tool 2: `browser-clear` (Disruptive, Admin=$false, SilentCapable -> refuses silent-no-force)

`Clear-BrowserData` / `New-ToolRun -Id 'browser-clear'`.

- **Report:** detected browsers/profiles; explicitly lists CLEARED (cache, cookies, history, sessions,
  permissions) vs PRESERVED (passwords, autofill; Firefox bookmarks).
- **Gate:** typed `Read-ToolChoice -Choices @('CONFIRM','Cancel') -Default 'Cancel'`. Disruptive ->
  refuses `-Silent` without `-Force` at the dispatcher level.
- Force-close browsers (locked files block deletion).
- For each browser, **each profile**:
  - **Chromium:** remove CacheDirs, Cookies, History, SessionDirs; edit `Preferences` JSON to clear
    `profile.content_settings.exceptions` + `profile.per_host_zoom_levels` (try/catch; skip on parse
    failure). KEEP Passwords (`Login Data`), Autofill (`Web Data`), Bookmarks.
  - **Firefox:** remove CacheDirs (`cache2`), Cookies, Favicons, Permissions, content-prefs.
    KEEP `places.sqlite` (bookmarks safe; FF history retained - noted), Passwords (`key4.db`/`logins.json`),
    Autofill (`formhistory.sqlite`).
- `Complete-ToolRun` Success: "Cleared N items across M browsers (passwords/autofill preserved;
  FF bookmarks preserved)".

## Testing

- **`tests\browser-helpers.tests.ps1` (NEW)** - locks the safety invariants:
  - `Get-BrowserCatalog` returns 4 browsers (Chrome, Edge, Brave, Firefox).
  - Chromium clear set EXCLUDES `Login Data`, `Web Data`, `Bookmarks`.
  - Firefox clear set EXCLUDES `key4.db`, `logins.json`, `places.sqlite`, `formhistory.sqlite`.
  - Backup set INCLUDES the password stores (parity with the include decision).
- Build green + full suite green: ASCII-only encoding gate, template-compliance gates (approved verbs,
  Silent param, run-bracketing, New-ToolRun-Id <-> registry AST mapping for the 2 new tools).
- **Smoke (non-elevated dev session):**
  - `browser-backup-restore -Silent` -> report only (None default), exit 0; quote summary.
  - `browser-clear -Silent` -> Disruptive refusal, exit 1; quote the refusal.
  - Destructive paths (actual backup write / restore overwrite / clear delete) verified by READING
    + the helper tests; NEVER executed in the dev session.

## Conventions carried from prior batches

Faithful BEHAVIOR port (not code); `Write-ToolOutput`/`Read-ToolChoice` only (no `Write-Host`/`Read-Host`
except free-text path input reached only after an interactive confirm); tight tech-facing summaries;
Info headline + Detail rows; empty-collection early-return Warning; descriptions/tags match actual v8
behavior; ASCII-only source (UTF-8 BOM + trailing newline); PS 5.1 (no ternary/`??`/`&&`, never assign
`$input`/`$matches`). Irreversible operations double-gated (Disruptive dispatcher-refusal + typed
CONFIRM with safe silent default). Scoped path helpers reject empty/drive-root/short paths.

## Out of scope

Tool 60 (Credential Manager Cleanup, batch 6), the Quick Fix "Browser Backup" (Q9, batch 7 - a
separate lightweight composite), and any browser sync/profile-migration features. No new browsers
beyond Chrome/Edge/Firefox/Brave.
