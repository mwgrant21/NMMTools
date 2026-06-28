# NMMTools v9 — WPF GUI Design Specification

**Date:** 2026-06-26  
**Version:** 1.0  
**Status:** Ready for handoff  
**Author:** Design direction  
**Target handoff:** app-architect (Runspace/threading/output sink) + WPF implementer (layout, controls, styles)

---

## 1. Concept

The WPF GUI is an alternative entry point to the same 101-tool registry that drives the console menu. It is not a separate product; it shares all architecture — the tool registry, `Write-ToolOutput`, `Read-ToolChoice`, `Invoke-NmmTool`, `Invoke-ToolWithGate`, `Get-NmmCommonFixes`, and `Export-TicketSummary` — without modification. The GUI's sole job is to replace the console's visual layer with a richer one: a scrollable, filterable tool browser on the left, a live output stream on the right, and confirm gates rendered as WPF controls instead of `Read-Host` calls. The defining requirement, the one the v8 GUI failed on, is that every line emitted by `Write-ToolOutput` appears in the output pane the instant it is emitted, while the tool is still running.

---

## 2. Experience Narrative

Matt opens NMMTools. The script detects an interactive console and prints two lines:

```
NMM System Toolkit v9
  1 = Console  2 = GUI
```

He types `2`. A WPF window opens at approximately 1200 × 750 pixels, dark-themed. The left column shows eight colored category buttons and a pinned "Common Fixes" item at the top. The middle column shows a searchable tool list with all 101 tools sorted by LegacyId within their category. The right side is split: a tool detail card in the upper third (showing the currently selected tool's name, description, risk, and admin status), and a large output pane filling the lower two-thirds, currently empty with a placeholder "No output yet — run a tool to begin."

Matt clicks "Diagnostics" in the left nav. The tool list filters to the 23 Diagnostics tools. He clicks "System Information." The detail card fills with the tool's name, description ("OS, hardware, BIOS, and domain summary for the machine"), a green "ReadOnly" risk chip, no admin indicator. A green "Run" button is the primary call to action. He clicks Run.

Because System Information is ReadOnly, no confirm gate appears. The tool launches in a background Runspace. In the output pane, lines begin arriving immediately:

```
[10:14:22] === System Information ===
[10:14:22] OS: Windows 11 Pro 23H2 (Build 26200)
[10:14:22] Hostname: DESKTOP-ABCDEF
[10:14:23] CPU: Intel Core i7-1265U ...
```

Each line appears as it is emitted; the pane auto-scrolls. The Run button turns gray and shows "Running..." with a spinner in the status bar at the bottom. When the tool completes, the final line appears:

```
[10:14:24] [SUCCESS] System information reported.
```

The status bar reads "Last run: System Information — SUCCESS." The Run button re-enables.

Next, Matt searches for "teams." The tool list immediately narrows to all tools with "teams" in name, description, or tags, across all categories. He selects "Teams Camera and Mic Repair." The detail card shows: Risk = [M] Modifies, RequiresAdmin = yes (admin badge visible). A yellow-orange "Run" button is the primary action.

He clicks Run. The detail card area shows a Modifies confirm banner: yellow-tinted background, "This tool modifies system settings. Proceed?" with "Run" and "Cancel" side by side. He clicks Run. The tool launches. Its first output is a report of camera permissions and devices. Then the output pane shows a `Read-ToolChoice` prompt:

```
[10:16:01] Select action: FixPermissions / ResetMediaStack / None
```

Below the output pane, a prompt area slides up showing three buttons: "FixPermissions", "ResetMediaStack", "None." Matt clicks "FixPermissions." The button group disappears, and output resumes:

```
[10:16:04] Setting ConsentStore webcam to Allow...
[10:16:04] [SUCCESS] Camera permissions updated.
```

At the end of the session, Matt clicks "Export Ticket" in the bottom toolbar. A modal dialog opens showing the formatted `Export-TicketSummary` text — machine name, session start/end, each tool run with status and duration. Two buttons: "Copy to Clipboard" and "Save to Desktop." He copies it and pastes it into the ticket.

---

## 3. Window Layout

```
+----------------------------------------------------------+
| HEADER: NMM Toolkit v9   DESKTOP-ABCDEF\Matt   [ADMIN]  |
|                                        Session: 00:12:44 |
+------------------+-------------------+-------------------+
| CATEGORY NAV     | TOOL LIST         | RIGHT PANEL       |
|                  |                   |                   |
| [*] Common Fixes | [Search...]  [X]  | TOOL DETAIL CARD  |
| ─────────────── |                   | ─────────────     |
| [  ] Browser     | 1.  Sys Info      | System Info       |
| [  ] Cloud       | 2.  Disk Space    | Diagnostics       |
| [  ] Diagnostics | 3.  Network Diag  | ReadOnly  no-admin|
| [  ] Laptop      | 4.  ...           | OS, hardware ...  |
| [  ] QuickFix    |                   | Tags: system os   |
| [  ] Repair      | 11. Temp Cleanup  |                   |
| [  ] Security    |      [M] [admin]  | [  RUN  ]         |
| [  ] User        | ...               | ─────────────     |
|                  |                   | OUTPUT PANE       |
|                  |                   |                   |
|                  |                   | [10:14:22] === .. |
|                  |                   | [10:14:22] OS: .. |
|                  |                   | [10:14:23] CPU: . |
|                  |                   | ...               |
|                  |                   |                   |
|                  |                   | ─────────────     |
|                  |                   | [PROMPT AREA]     |
|                  |                   | hidden when idle  |
+------------------+-------------------+-------------------+
| STATUS: Idle     | [Export Ticket]   | [Clear Output]    |
+----------------------------------------------------------+
```

### Column widths (default, all resizable via GridSplitters)
- Category Nav: 180 px fixed (no splitter needed; categories are static)
- Tool List: 280 px default, draggable splitter on right edge
- Right Panel: fills remainder

### Row heights within the Right Panel
- Tool Detail Card: 220 px default, draggable splitter below it
- Output Pane: fills remainder (minimum 200 px)
- Prompt Area: 80 px, visible only when a `Read-ToolChoice` is pending

### Window constraints
- Minimum size: 900 × 580 px
- Default size: 1200 × 750 px
- Window state and size persist via user settings (see section 12)

---

## 4. Color System

### Window chrome (dark theme — v1 is dark-only)
| Surface              | Hex       | Notes                              |
|----------------------|-----------|------------------------------------|
| App background       | `#1E1E1E` | VS Code-style near-black           |
| Left nav background  | `#252526` |                                    |
| Tool list background | `#2D2D30` |                                    |
| Output pane bg       | `#0C0C0C` | Near-terminal-black for contrast   |
| Header/status bar    | `#2D2D30` |                                    |
| Card background      | `#252526` |                                    |
| Border/divider       | `#3E3E42` | 1 px lines between panels          |
| Primary text         | `#CCCCCC` |                                    |
| Secondary text       | `#858585` |                                    |

### Output pane text (Level color map)
| Level   | Hex       | Notes                              |
|---------|-----------|------------------------------------|
| Info    | `#DCDCDC` | Near-white — most lines            |
| Success | `#4EC94E` | Green                              |
| Warning | `#FFCA28` | Amber                              |
| Error   | `#F44747` | Red                                |
| Detail  | `#808080` | Gray — subordinate detail rows     |
| Timestamp prefix  | `#505050` | Shown before every line in Detail gray |
| Run header (===)  | `#4FC3F7` | Cyan — matches Diagnostics color; stands out as section boundary |

### Category accent colors (used as left-border accents and nav button highlights)
| Category     | Hex       | ConsoleColor equivalent |
|--------------|-----------|-------------------------|
| Browser      | `#E0E0E0` | White                   |
| Cloud        | `#FFCA28` | Yellow                  |
| Diagnostics  | `#4FC3F7` | Cyan                    |
| Laptop       | `#66BB6A` | Green                   |
| QuickFix     | `#CE93D8` | Magenta                 |
| Repair       | `#EF5350` | Red                     |
| Security     | `#C9A227` | DarkYellow              |
| User         | `#5C8DDF` | Blue                    |
| Common Fixes | `#FFFFFF` | White (matches console) |

### Risk chip colors
| Risk        | Background | Text      | Notes                     |
|-------------|------------|-----------|---------------------------|
| ReadOnly    | `#2E4A2E`  | `#4EC94E` | Dark green chip            |
| Modifies    | `#4A3E1A`  | `#FFCA28` | Dark amber chip            |
| Disruptive  | `#4A1E1E`  | `#F44747` | Dark red chip              |

### Run button colors (reflects risk of selected tool)
| Risk        | Button bg  | Hover      |
|-------------|------------|------------|
| ReadOnly    | `#2E7D32`  | `#388E3C`  |
| Modifies    | `#E65100`  | `#EF6C00`  |
| Disruptive  | `#C62828`  | `#D32F2F`  |
| Disabled    | `#404040`  | n/a         |

---

## 5. Screens and States

### 5.1 Idle (no tool selected)

- Tool detail card: shows placeholder text "Select a tool to see its details." Run button hidden.
- Output pane: shows placeholder text "No output yet — run a tool to begin." in Detail gray.
- Status bar: "Idle"
- Category nav: all buttons enabled
- Tool list: full list visible (or filtered by selected category/search)
- Prompt area: hidden

### 5.2 Tool Selected (pre-run)

- Tool detail card: populated with Name, Category chip, Risk chip, RequiresAdmin badge (triangle symbol matching console's `[char]0x25B2`, or the word "Admin"), Description, Tags row.
- Run button: visible, labeled "Run", colored per risk (green/orange/red).
- Output pane: shows previous session output unchanged. If this is the first selection, shows placeholder.
- Status bar: "Ready — {Tool Name}"
- Category nav: all buttons enabled
- Prompt area: hidden

### 5.3 Modifies Confirm Gate

Triggered: user clicks Run on a Modifies-risk tool.

A confirm banner appears INSIDE the detail card, replacing the Run button area. It does NOT open a dialog — it is inline.

Banner content:
- Amber left border (4 px, `#FFCA28`)
- Text: "This tool modifies system settings. Review the description above before proceeding."
- Button row: "Run" (amber `#FF9800` background) | "Cancel" (transparent, gray text)
- No text input required

On "Run": banner hides, tool launches.  
On "Cancel": banner hides, state returns to Tool Selected.

### 5.4 Disruptive Confirm Gate

Triggered: user clicks Run on a Disruptive-risk tool.

Opens a modal dialog (separate Window, owner = MainWindow, cannot be dismissed by clicking outside).

Dialog content:
- Red header bar with tool name: "{Tool Name} — DISRUPTIVE OPERATION"
- Body: tool description + "This operation cannot be easily undone. Type CONFIRM below to proceed."
- TextBox (single line, centered, large font)
- Buttons: "Proceed" (enabled only when TextBox contains exactly "CONFIRM", case-insensitive) | "Cancel"
- Escape key fires Cancel

On "Proceed": dialog closes, tool launches.  
On "Cancel" / Escape: dialog closes, state returns to Tool Selected.

### 5.5 Tool Running

- Run button: disabled, label changes to "Running..." (text only, no spinner in the button)
- Status bar: "Running: {Tool Name}" + an indeterminate ProgressBar (thin, beneath status text, full width)
- Output pane: receives and displays lines in real time. Auto-scrolls to the bottom unless user has manually scrolled up.
- Prompt area: hidden until a `Read-ToolChoice` call is pending
- Category nav: disabled (grayed out) — prevents launching a second tool mid-run
- Tool list: disabled — prevents selection changes mid-run
- No Cancel button in v1 (see Non-Goals, section 11)

**Auto-scroll behavior:** The output pane auto-scrolls to the bottom on each new line as long as the user has not scrolled up from the bottom. If the user scrolls up (to read earlier output), auto-scroll is paused. When the user scrolls back to within 20 px of the bottom, auto-scroll resumes. A small "Scroll to Bottom" button appears in the bottom-right corner of the output pane when auto-scroll is paused.

### 5.6 Read-ToolChoice Pending (in-tool prompt)

Triggered mid-run when a tool calls `Read-ToolChoice`.

The Prompt Area slides up from the bottom of the output pane (it was hidden; it becomes visible with a height animation, ~150 ms ease-out). The tool's Runspace thread is blocked waiting for the response.

Prompt area content:
- Dark background (`#1A2530`) with a cyan left border (`#4FC3F7`)
- Prompt text: the verbatim `$Prompt` string from `Read-ToolChoice`, in white
- Default indicator: "(default: {Default})" in Detail gray
- Button row: one Button per entry in `$Choices`, left to right
  - The Default choice button gets a solid colored background matching the current tool's risk color; other choices get transparent/ghost style
- Output pane above continues to show all previous lines (no scroll lock during prompt)

On button click: the choice is returned to the Runspace, prompt area slides back down (hidden), tool output resumes.

**Timeout behavior:** none in v1. The Runspace waits indefinitely for a user response, matching the console behavior.

### 5.7 Tool Completed

- Run button: re-enables, reverts to "Run" label with risk color
- Status bar: "Last run: {Tool Name} — {STATUS}" where STATUS is SUCCESS / WARNING / FAILED in the matching color
- ProgressBar: hides
- Output pane: shows the final `[SUCCESS] ...` / `[FAILED] ...` line from `Complete-ToolRun`; auto-scrolls to it
- Prompt area: hidden
- Category nav: re-enables
- Tool list: re-enables
- Selected tool remains selected in the list (so the tech can run it again immediately)

### 5.8 Admin Refused State

When a RequiresAdmin=true tool is selected but the script is NOT running as admin:
- The Run button is replaced with a static text label: "Requires admin — re-launch elevated" in red
- The Run button is not shown at all (not disabled — absent)
- This matches `Invoke-NmmTool`'s existing admin refusal behavior, surfaced visually before the user even tries to click

Note: in normal use the script is launched elevated. This state is rare but should be handled cleanly.

---

## 6. Component Inventory

### Windows
| Component          | Type          | Notes                                                     |
|--------------------|---------------|-----------------------------------------------------------|
| MainWindow         | WPF Window    | Primary window, 3-pane layout                            |
| ConfirmDialog      | WPF Window    | Modal — Disruptive tools only. Owner = MainWindow.        |
| TicketExportDialog | WPF Window    | Modal — shows ticket summary. Owner = MainWindow.         |

### Panels (all within MainWindow)
| Component          | WPF Control           | Notes                                                     |
|--------------------|-----------------------|-----------------------------------------------------------|
| HeaderBar          | Border + DockPanel    | Fixed height ~40 px                                       |
| CategoryNav        | Border + StackPanel   | Fixed width 180 px; holds nav buttons                     |
| ToolListPanel      | Border + DockPanel    | Holds SearchBox + ToolListBox                            |
| RightPanel         | Grid (2 rows)         | Detail card top, output pane bottom                       |
| ToolDetailCard     | Border + StackPanel   | Collapses to placeholder when nothing selected            |
| ConfirmBanner      | Border + StackPanel   | Inline Modifies confirm; visibility-toggled               |
| OutputPaneWrapper  | Border + Grid         | Contains OutputBox + scroll-to-bottom button overlay      |
| PromptArea         | Border + StackPanel   | Hidden by default; slides up on Read-ToolChoice           |
| StatusBar          | Border + DockPanel    | Fixed height ~28 px                                       |

### Controls
| Control              | WPF Type               | Notes                                                              |
|----------------------|------------------------|--------------------------------------------------------------------|
| AppTitle             | TextBlock              | "NMM Toolkit v9" in header                                         |
| MachineUserLabel     | TextBlock              | "{COMPUTERNAME}\{USERNAME}" in header                              |
| AdminBadge           | Border + TextBlock     | Green "[ADMIN]" or red "[NOT ADMIN]"                               |
| SessionTimer         | TextBlock              | Updated on a 1-second DispatcherTimer                              |
| CategoryNavButtons   | Button (8 + 1)         | One per category + Common Fixes; each has a colored left border accent |
| CategorySelectedIndicator | Rectangle       | 3 px left border, category accent color, fills button left edge    |
| SearchBox            | TextBox                | Placeholder text via watermark behavior                            |
| SearchClearButton    | Button                 | "X" button; visible only when SearchBox is non-empty               |
| ToolListBox          | ListBox (virtualized)  | VirtualizingStackPanel; items are tool hashtables from registry     |
| ToolListItemTemplate | DataTemplate           | " {LegacyId}. {Name}" + risk badge + admin triangle, right-aligned |
| ToolNameLabel        | TextBlock              | In detail card; large font ~16 px                                  |
| CategoryChip         | Border + TextBlock     | Category name, accent-colored left border                          |
| RiskChip             | Border + TextBlock     | Risk label, risk-colored background                                |
| AdminChip            | Border + TextBlock     | "Admin Required"; hidden when RequiresAdmin=false                  |
| DescriptionLabel     | TextBlock (wrapped)    | Tool.Description; secondary text color                             |
| TagsPanel            | ItemsControl           | Chip-style template; each tag as a small bordered TextBlock        |
| RunButton            | Button                 | Primary action; risk-colored; hidden for non-admin tools when not elevated |
| AdminRefusedLabel    | TextBlock              | Replaces RunButton when admin required and not elevated            |
| ConfirmBannerText    | TextBlock              | In ConfirmBanner; Modifies warning text                            |
| ConfirmRunButton     | Button                 | In ConfirmBanner; amber                                            |
| ConfirmCancelButton  | Button                 | In ConfirmBanner; ghost style                                      |
| OutputBox            | RichTextBox (read-only)| Auto-scroll behavior; receives Dispatcher-marshalled lines         |
| ScrollToBottomButton | Button                 | Overlay in bottom-right of OutputBox; appears when scroll paused   |
| OutputClearButton    | Button                 | In output pane header area; clears the RichTextBox Document        |
| CopyOutputButton     | Button                 | Copies all output pane text to clipboard                           |
| PromptText           | TextBlock              | In PromptArea; shows Read-ToolChoice $Prompt string                |
| PromptDefaultLabel   | TextBlock              | "(default: {Default})" in PromptArea                              |
| ChoiceButtonsPanel   | StackPanel (Horizontal)| One Button per $Choices entry in PromptArea                       |
| StatusLabel          | TextBlock              | Left side of status bar; "Idle" / "Running: ..." / "Last run: ..." |
| RunProgressBar       | ProgressBar            | Indeterminate; visible only during tool run; full-width under status |
| ExportTicketButton   | Button                 | Opens TicketExportDialog                                           |
| ClearOutputStatusBtn | Button                 | Right side of status bar; same action as OutputClearButton         |

### ConfirmDialog controls
| Control            | Notes                                                              |
|--------------------|--------------------------------------------------------------------|
| DialogHeader       | Red bar; "{Tool Name} — DISRUPTIVE OPERATION"                      |
| DialogDescription  | Tool description (read-only TextBlock)                             |
| InstructionText    | "Type CONFIRM below to proceed."                                   |
| ConfirmTextBox     | Single-line TextBox; text compared to "CONFIRM" case-insensitive   |
| ProceedButton      | Enabled only when ConfirmTextBox.Text == "CONFIRM"; red background |
| CancelButton       | Closes dialog, returns null                                        |

### TicketExportDialog controls
| Control            | Notes                                                              |
|--------------------|--------------------------------------------------------------------|
| TicketTextBox      | Multi-line, read-only TextBox showing Export-TicketSummary output  |
| CopyButton         | Copies TicketTextBox.Text to Clipboard                             |
| SaveButton         | Saves to Desktop as NMM-TicketSummary-{timestamp}.txt             |
| CloseButton        | Closes dialog                                                      |
| SaveStatusLabel    | Shows "Saved to {path}" or error after save attempt                |

---

## 7. Category Navigation

The left nav has 9 items:

1. **Common Fixes** (star glyph, ★, white accent) — shows the top-6 usage-ranked tools
2. Separator line
3. **Browser** (white accent)
4. **Cloud** (yellow accent)
5. **Diagnostics** (cyan accent)
6. **Laptop** (green accent)
7. **QuickFix** (magenta accent)
8. **Repair** (red accent)
9. **Security** (dark-yellow accent)
10. **User** (blue accent)

There is no "All Tools" item. The default selection on launch is Common Fixes if usage data exists; otherwise Diagnostics (category with the most tools and the category Matt historically visits most).

Each nav button:
- Full width of the nav panel
- Left edge: a 4 px colored rectangle (the category accent color), visible when the item is selected; collapses to 0 px or turns transparent when deselected
- Text: category name + tool count in secondary color "(23)" when not Common Fixes; "(6)" when Common Fixes
- Selected state: slightly lighter background (`#2A2A2E`)
- Hover: `#323235`

When Common Fixes is selected and usage is empty (first launch ever), the tool list shows a message: "No tools have been run yet. Use any tool once to start tracking favorites." This state clears as soon as the first tool run is recorded.

---

## 8. Tool List

The tool list is a virtualized ListBox. Virtualization is important: 101 items is manageable without it, but the items use color rendering and badge logic, and virtualization is the correct WPF pattern regardless.

**Item template layout** (within each row, approximately 270 px wide):
```
[ LegacyId. Tool Name ............... [M][admin] ]
```
- LegacyId in secondary text color, fixed-width right-aligned (4 chars)
- Tool Name in primary text color
- Risk badge ([M] or [!]) right-aligned, colored per risk: amber for [M], red for [!], hidden for ReadOnly
- Admin triangle (▲) right of risk badge if RequiresAdmin, in secondary text color
- Row height: 30 px
- Selected row: the category accent color as a 2 px left border + slightly lighter row background

**Sorting:** within the selected category, tools are sorted by `Get-NmmLegacyIdSortKey` (numeric first, then Q#), matching the console menu order. When search results are shown across categories, tools are sorted by category accent color group first, then by LegacyId within each group.

**Category group headers:** when "All" search results are shown across categories, the list shows a non-selectable category header row above each group (same boxed-banner concept from the console, but implemented as a non-clickable separator item in a different background). When a single category is selected, no header is needed.

**Selection behavior:** clicking a tool selects it and populates the detail card immediately. Double-clicking a tool selects it AND triggers Run (same as single-click + Run button). A running tool's row is highlighted in the list.

---

## 9. Output Pane

### Structure
The output pane is a `RichTextBox` with `IsReadOnly=true`, dark background (`#0C0C0C`), horizontal scroll disabled, word wrap on.

### Line format
Each line appended to the output pane has the format:
```
[HH:mm:ss] {Message}
```
The timestamp portion `[HH:mm:ss] ` is rendered in the Timestamp color (`#505050`). The message portion is rendered in the Level color. Both are on the same line (same `Paragraph` in the `FlowDocument`, mixed `Run` elements with different foregrounds).

The run header emitted by `New-ToolRun` (`=== Tool Name ===`) is rendered in the Run Header color (`#4FC3F7`) in bold, slightly larger font, and is preceded by a blank line as a visual separator.

### Persistence
Output accumulates for the entire session. Individual tool runs are visually delimited by the run header. The pane is NOT cleared between tool runs. An explicit "Clear" button lets Matt wipe it when the session output gets long.

### Thread safety
Every append to the RichTextBox Document is made via `Dispatcher.InvokeAsync` on the UI thread. The 'GUI' output sink in `Write-ToolOutput` posts each call through this mechanism. See section 13 (Threading) for the architectural contract.

### Scroll-to-bottom button
A small button (label "↓ Bottom", chevron icon) appears as an overlay in the bottom-right corner of the output pane when:
- A tool is running AND
- The user has scrolled up from the bottom (auto-scroll is paused)

Clicking it scrolls immediately to the bottom and re-enables auto-scroll. It disappears when auto-scroll resumes.

### Copy behavior
The "Copy Output" button copies the full plain-text content of the output pane to the clipboard, stripping color formatting. This is different from the Ticket Export which uses `Export-TicketSummary`'s structured format.

---

## 10. Common Fixes Section

When "Common Fixes" is selected in the left nav, the tool list shows the top-6 tools returned by `Get-NmmCommonFixes`. These are displayed in the same tool list format as any other category selection — same item template, same risk badges, same click behavior.

The heading of the tool list (a non-selectable label row at the top of the list, visible for all categories) shows:
- "★ Common Fixes" in white when Common Fixes is selected
- "Browser" / "Cloud" / etc. in the category accent color when a category is selected

There is no separate visual treatment beyond what the tool list already provides — the section feels like any other category. The star in the nav button and the heading label are the only signals that this is usage-ranked.

**Usage tracking in GUI mode:** `Add-NmmUsage` must be called from `Invoke-ToolWithGate` in the GUI path exactly as it is in the console path. Since the GUI will have its own run path (not literally calling `Start-ConsoleMenu`), it must call `Add-NmmUsage` at the same point: after a tool completes (or after the gate confirm, for Disruptive tools that are cancelled — match the console behavior: cancelled tools are NOT recorded).

---

## 11. Search

The search box sits at the top of the tool list panel, above the list. Placeholder text: "Search tools..."

### Behavior
- Filters happen on every keystroke (no Enter required)
- Matching uses the same logic as `Search-NmmTools`: case-insensitive substring match on Name, Description, and Tags
- While a search term is active, category nav selection is visually deselected (none highlighted); the list shows all matching tools across all categories
- A "×" clear button appears in the search box's right edge when text is present; clicking it clears the box and restores the previously selected category view
- If a tool was selected before search started, and the search results include that tool, it remains selected; otherwise selection clears
- Zero results: list shows "No tools match '{term}'" as a non-selectable placeholder item
- Search box can be focused with Ctrl+F from anywhere in the window

### What search does NOT do
- Does not search output pane content
- Does not run searches remotely
- Does not remember recent searches

---

## 12. Entry Point (Launch-Time Mode Selection)

The existing `99-main.ps1` entry point, after elevation and before `Start-ConsoleMenu`, will gain:

```
1 = Console  2 = GUI
```

The implementer must add this prompt to `99-main.ps1`. This spec does not prescribe the exact implementation, but the behavior must be:

- Defaults to Console if Enter is pressed without a choice (backward-compatible with existing workflow)
- If `2` is selected, calls `Start-GuiMenu` (the new GUI entry point function, analogous to `Start-ConsoleMenu`)
- `Start-GuiMenu` loads the WPF assembly, instantiates MainWindow, wires up the GUI output sink, and calls `Application.Run()`
- The choice is NOT persisted between sessions in v1 (see Non-Goals)
- If the session is non-interactive (headless/PDQ), the prompt is skipped entirely and Console mode is used

---

## 13. Threading Architecture (Contract for the Architect)

This section defines the threading contract the GUI requires. Implementation belongs to the architect, not the WPF implementer.

### Output sink ('GUI')
A third `$script:OutputSink` value, `'GUI'`, is added (alongside the existing `'Console'` and `'Silent'`). When active:
- `Write-ToolOutput` does NOT call `Write-Host`
- Instead, it marshals the call to the WPF Dispatcher: `$dispatcher.InvokeAsync({ <append line to OutputBox> })`
- The marshal must be non-blocking (fire-and-forget from the Runspace thread) to avoid deadlocks

### Read-ToolChoice GUI intercept
When `$script:OutputSink -eq 'GUI'`, `Read-ToolChoice` must NOT call `Read-Host`. Instead:
- It posts the prompt + choices to the GUI via Dispatcher
- It then blocks on a `System.Threading.SemaphoreSlim` (or `ManualResetEventSlim`) until the user clicks a button
- The GUI's button handler sets the response value and releases the semaphore
- The function returns the choice string, exactly as the console version returns a string

### Tool execution Runspace
`Invoke-ToolWithGate` in GUI mode launches the tool in a PowerShell Runspace (not `Start-Job` — Runspaces share the session state including the GUI sink and the semaphore for `Read-ToolChoice`).

The Runspace must have access to:
- All script-scope variables (`$script:OutputSink`, `$script:RegistryData`, `$script:ToolRuns`, `$script:IsAdmin`, etc.)
- The WPF Dispatcher reference
- The `SemaphoreSlim` / response container for `Read-ToolChoice`

### Completed notification
When the Runspace completes, it fires a completion event back to the UI thread via Dispatcher to update the status bar, re-enable controls, and trigger scroll-to-bottom.

### Single-tool-at-a-time lock
The GUI enforces a single running tool constraint by disabling category nav, tool list, and the Run button during a run. No queue, no parallel runs.

---

## 14. Ticket Export

The "Export Ticket" button in the status bar opens `TicketExportDialog`.

The dialog calls `Export-TicketSummary` (no `$Path` argument — returns the string, same as the `T` key in the console menu). The full text is displayed in a multi-line read-only TextBox.

**"Copy to Clipboard"**: copies the text to `Clipboard.SetText()`. Button label briefly changes to "Copied!" for 1500 ms, then reverts. This is a micro-interaction — implement with a DispatcherTimer reset.

**"Save to Desktop"**: saves to `NMM-TicketSummary-{yyyyMMdd-HHmmss}.txt` on the Desktop (KFM/OneDrive-redirect aware, using `Environment.GetFolderPath(SpecialFolder.Desktop)`). On success, shows the path in the `SaveStatusLabel`. On failure, shows the error message.

**Close button** and **Escape key** dismiss the dialog without action.

The dialog can be opened multiple times during a session; each open calls `Export-TicketSummary` fresh, so it includes all runs up to that moment.

---

## 15. Status Bar

Left section:
- Text label, current state
- States: "Idle" | "Ready — {Tool Name}" | "Running: {Tool Name}..." | "Last run: {Tool Name} — SUCCESS" (green) | "Last run: {Tool Name} — WARNING" (amber) | "Last run: {Tool Name} — FAILED" (red) | "Cancelled: {Tool Name}"

Center-left:
- Indeterminate ProgressBar, visible only during a tool run, full-width thin bar just below the status text row (or directly below the header, spanning the full window width — architect's choice, whichever is easier in WPF)

Center:
- Session elapsed time label "Session: 00:14:22" updated on a 1-second DispatcherTimer starting at window open

Right section:
- "Export Ticket" Button
- Admin badge: green "[ADMIN]" or red "[NOT ADMIN]"

---

## 16. Non-Goals (v1 ships without)

These are explicitly excluded. Do not implement them. They are not oversights; they are deferred by design.

1. **Cancel running tool.** Runspace cancellation is possible in PowerShell but requires cooperative cancellation checks in every tool. No tools implement this today. Adding cancel would require modifying all 101 tools or accepting hard-abort (which can leave operations in a half-done state for destructive tools like profile repair). Deferred.
2. **Dark/light theme toggle.** Dark-only. One well-executed theme beats two mediocre ones.
3. **Persistent mode preference.** The 1/2 launch prompt does not remember the last choice between sessions.
4. **Multi-tool queue.** One tool at a time, matching the console mental model.
5. **Remote endpoint targeting.** The GUI runs on the endpoint being fixed, same as the console.
6. **Settings screen.** No GUI for `-LogPath` or other CLI parameters. Those remain CLI-only.
7. **Tool output search/filter.** The output pane is not searchable. Copy to clipboard + Ctrl+F in a text editor covers this need.
8. **Floating/detachable output pane.** Single fixed layout.
9. **Session persistence across launches.** Output pane clears on window close; usage.json persists naturally (handled by the existing `06-usage.ps1`).
10. **Right-click context menu on tools.** Single click to select, double-click to run, no context menus.
11. **Tool output color customization.** The Level→color map is fixed.
12. **Log file path configuration from GUI.** Use `-LogPath` CLI argument.
13. **Admin re-launch button.** If not elevated, the user must re-launch manually. Implementing UAC prompt from a WPF button is architecturally fragile; the console's `Invoke-ElevationCheck` is the canonical path.

---

## 17. Open Questions (RESOLVED 2026-06-27)

All five resolved by Matt on 2026-06-27. Each decision already matched the Friday
implementation, so no code changes were required; recorded here for the record.

1. **Default category on launch.** When usage data exists, Common Fixes is the default. When it doesn't (fresh machine), which category should be pre-selected: Diagnostics (most tools, most commonly reached) or Repair? Or should there be no default with a "Select a category" prompt state?
   - **Decision:** Common Fixes when usage data exists, else fall back to Diagnostics.
   - **Status:** Implemented (`09-ui-wpf.ps1`, lines 1074-1091).

2. **Output timestamp format.** The log file uses `[HH:mm:ss]`. Should the GUI output pane use the same `[HH:mm:ss]` format, or a relative time since the current tool started (e.g., "+0:03 line content"), or both? Both adds noise; one choice should win.
   - **Decision:** Absolute `[HH:mm:ss]`, matching the log file.
   - **Status:** Implemented (`09-ui-wpf.ps1`, `Add-GuiOutputRecord`).

3. **Disruptive typed confirm: case sensitivity.** Should typing "CONFIRM" in the ConfirmDialog be case-sensitive (must be uppercase, matching the heightened friction intent) or case-insensitive (less friction)? The console tools that use typed confirms (e.g., profile repair, RDP enable) use `Read-Host` and compare case-insensitively. Recommend matching: case-insensitive.
   - **Decision:** Case-insensitive, matching the console tools.
   - **Status:** Implemented (`09-ui-wpf.ps1`, ProceedButton enable check, `-eq 'CONFIRM'`).

4. **Window title bar content.** Options: just "NMM Toolkit v9", or include machine/user ("NMM Toolkit v9 - DESKTOP-ABCDEF\Matt"), or include admin status. The header bar already shows machine/user, so the title bar could be minimal.
   - **Decision:** "NMM Toolkit v9 - {COMPUTERNAME}". Machine\user and admin remain in the header bar.
   - **Status:** Implemented (`09-ui-wpf.ps1`, `$window.Title`).

5. **Output pane auto-clear on new tool run.** The spec says output persists across tool runs within a session. If Matt typically runs 10-15 tools per session, the pane will get long. Is accumulated-session output the right default, or should each new run clear the pane (with the previous run's output available elsewhere)?
   - **Decision:** Accumulate across runs; explicit "Clear Output" button only (3000-block cap trims oldest).
   - **Status:** Implemented (`09-ui-wpf.ps1`, `Add-GuiOutputRecord` block cap).

---

## 18. Handoff Notes

### WPF Implementer owns
- MainWindow.xaml and all XAML resource dictionaries (styles, data templates, colors as StaticResources)
- ConfirmDialog.xaml and TicketExportDialog.xaml
- The 1-second DispatcherTimer for session elapsed time
- Auto-scroll logic: scroll position tracking, pause/resume, "Scroll to Bottom" button visibility
- Category nav button selected-state visual
- Search box filtering (binding the ListBox ItemsSource to a filtered view in the ViewModel)
- Prompt area slide-in/slide-out animation
- "Copied!" transient label behavior in TicketExportDialog
- All WPF bindings and the ViewModel (MVVM is the recommended pattern; no code-behind business logic)

### App Architect owns
- The `'GUI'` output sink in `02-output.ps1`
- The `Read-ToolChoice` GUI intercept (semaphore + Dispatcher pattern)
- The Runspace setup: InitialSessionState carrying all script-scope variables, the Dispatcher reference, and the semaphore
- The Runspace completion callback (Dispatcher invoke to re-enable UI)
- `Start-GuiMenu` function in a new `src/core/09-ui-wpf.ps1` (or equivalent)
- The `1 = Console / 2 = GUI` prompt in `99-main.ps1`
- `Add-NmmUsage` call in the GUI run path (post-completion, matching console behavior)
- WPF assembly loading (`Add-Type -AssemblyName PresentationFramework` etc.)
- Ensuring build.ps1 includes the new GUI core file

### Recommended build order
1. Architect: add `'GUI'` sink to `02-output.ps1` + write `09-ui-wpf.ps1` with a stub `Start-GuiMenu` that opens an empty Window — proves WPF loads and the GUI sink routes output without crashing the console path. Wire the 1/2 prompt in `99-main.ps1`.
2. Architect: implement the Runspace with the real GUI output sink, running a single hardcoded test tool (e.g., system-uptime) and displaying output in a plain RichTextBox. Prove real-time streaming before any visual work begins. This is the most critical proof-of-concept.
3. WPF Implementer: build the full MainWindow layout in XAML with hardcoded/mock data. No live tool execution yet — just the visual shell with all panels, the color system, and the tool list populated from the live registry.
4. Architect + WPF Implementer: integrate — connect the ViewModel to the live registry for tool list and category nav, wire the Run button to the Runspace, connect output streaming to the real OutputBox.
5. Architect: implement `Read-ToolChoice` GUI intercept. Test with a tool that has an action menu (e.g., teams-camera-repair or credential-manager).
6. WPF Implementer: implement confirm gates (Modifies inline banner, Disruptive modal).
7. WPF Implementer: implement search, Common Fixes nav, session timer, status bar states, auto-scroll, Ticket Export dialog.
8. Final: test every screen state listed in section 5 with real tools in each risk category.
