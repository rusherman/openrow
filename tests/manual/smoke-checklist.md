# OpenRow Manual Smoke Checklist

Run before tagging a release. Each row: PASS / FAIL / N/A + one-line note.

| App | Verify | Result |
|---|---|---|
| Finder list view | each row has 1 label; click opens folder | |
| Safari arbitrary page | links / inputs / buttons all labelled; no missed dropdown | |
| Claude Code chat list | each conversation row has exactly 1 label; no AXStaticText label on section headers | |
| VS Code | file tree, tabs, status bar, activity bar all clickable | |
| System Settings | left categories + right toggles labelled and clickable | |
| Top menu bar | File / Edit / etc. each labelled | |
| Status icons (Wi-Fi, battery, IME) | each icon clickable to open its menu | |
| Notification center | dismiss-able items labelled | |

## Steps to run

1. `bash scripts/install.sh` (copies spoon to ~/.hammerspoon and reloads)
2. For each app in the table: open it, focus its main window, press Cmd+Shift+Space, verify the row.
3. Enter findings in the Result column.
