[CmdletBinding()]
param(
    [string]$Tool,        # run one tool by slug or legacy number, then exit
    [switch]$Silent,      # no prompts; Read-ToolChoice returns declared defaults
    [switch]$Force,       # allow Disruptive tools under -Silent
    [switch]$ListTools,   # print the tool inventory and exit
    [string]$LogPath,     # directory for the session log file
    [ValidateSet('Auto','Console','GUI')][string]$Mode = 'Auto'
)
