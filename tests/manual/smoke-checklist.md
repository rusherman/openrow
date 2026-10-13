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

## Targeting regression checks

- Browser controls exposing only AXPosition/AXSize still receive labels.
- A zero-size structural parent does not hide a visible child button.
- A selectable/actionable row and its auxiliary button remain separately targetable.
- Text-field internals do not create a duplicate label inside the field.
- Wrapped and very small links click the link rather than an adjacent element.
- A partially clipped control gets a point inside its visible portion.
- Scroll content outside the viewport is omitted.
- Move/cover a labelled control before selecting it: it is revalidated; no unrelated click occurs.
- Repeated activations do not accumulate duplicate AX wrappers or consume the target limit.
- During a large scan, `Esc` and a second activation cancel promptly; no late labels appear.
- Switching apps while scanning cancels the old scan and does not draw labels for the previous app.
- Search typing remains responsive and does not re-query AX metadata.
- Labels on monitors with negative origins remain aligned; each screen has one shared canvas.
- A scan timeout or rendering error releases the keyboard hook; normal typing still works.

For a disposable local fixture:

1. Run `python3 -m http.server 8768 --bind 127.0.0.1 --directory tests/manual` from the repo and open `http://127.0.0.1:8768/targeting-smoke.html` in Chrome.
2. From Hammerspoon Console, run `dofile("/absolute/path/to/openrow/tests/manual/targeting-smoke.lua")`, then `_openrowQA.scan()`.
3. Schedule `hs.timer.doAfter(3, function() _openrowQA.click("qa button") end)` and bring the fixture tab to the front. The page must show `Button clicks: 1`. Repeat with `qa wrapped link`; the page must show `Link clicks: 1`.
4. Close the fixture tab, stop the HTTP server, and clear `_openrowQA=nil` in the console.

This fixture does not replace the application matrix above.
