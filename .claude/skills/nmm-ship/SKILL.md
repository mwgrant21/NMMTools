---
name: nmm-ship
description: Release the NMMToolkit build - full build, full test suite, copy dist to the Desktop deployment copy, sync to the private repo (mwgrant21/Claude-Files) with a descriptive commit message, push. Use when asked to "ship", "release", or "sync nmm". Hard-stops on any red gate.
---

# NMM Ship

Working directory: `C:\Users\IT\Desktop\NMMToolkit`. Run the gates IN ORDER;
any failure = STOP, report the failing output, ship nothing.

## Gate 0 - clean tree

`git status --porcelain` in NMMToolkit. Uncommitted changes to `src\` or
`tests\`? STOP and tell the user what is uncommitted - ship only committed
work.

## Gate 1 - build

    .\build.ps1

Any throw (parse gate, analyzer gate) = STOP.

## Gate 2 - tests

    Invoke-Pester .\tests

Any failed test = STOP. Report the failure names and output.

## Step 3 - deploy copy

    Copy-Item dist\NMMTools.ps1 "$env:USERPROFILE\Desktop\nmmtools.ps1" -Force

The Desktop copy is what sync.ps1 reads - this step is what makes the new
build shippable.

## Step 4 - stage and diff

    & "$env:USERPROFILE\Claude-Files\nmm-toolkit\sync.ps1" -StageOnly

If it prints "No changes to sync" - report that and stop (nothing to ship).
Otherwise read the staged change:

    git -C "$env:USERPROFILE\Claude-Files" --no-pager diff --cached --stat

and read the NMMToolkit commits since the last ship - use the date of the previous nmm-toolkit commit in Claude-Files (git -C "$env:USERPROFILE\Claude-Files" log -1 --format=%ci -- nmm-toolkit/) as the --since anchor for git log in NMMToolkit - to know WHAT is in this release.

## Step 5 - commit message and push

Compose a message: first line "NMMTools vX.Y.Z - <one-line summary>", then
a bullet per tool added/changed (from the NMMToolkit commits). Then:

Version = the v number stamped in the dist\NMMTools.ps1 header (set by build.ps1 -Version, default currently 9.1.0). Bump build.ps1's default first if this release warrants a version change.

    & "$env:USERPROFILE\Claude-Files\nmm-toolkit\sync.ps1" -Message "<the message>"

sync.ps1 handles commit + pull --rebase + push. If it reports a rebase
conflict or push failure, report verbatim and stop - never force-push.

## Step 6 - report

Version shipped, gates passed (build, N tests), diff stat, commit message
used, push result.
