# User Interface Conventions

mayhem.el pages follow Magit and the rest of Emacs, so they behave as
users expect.

## Interactivity

| Situation | Approach |
|---|---|
| The whole line opens something | RET-able row: `vui-text` in a `vui-region` with a RET keymap, `mouse-face 'highlight`, `help-echo` |
| One control among others on a line | `vui-button` |
| A foldable block | `vui-collapsible` |

- Brackets mean an action (`[Stop]`, `[Load more]`); plain text is content.
  A page's identity (`project/target`) is never a button.
- `help-echo` reads `"RET: <imperative>"`, e.g. `"RET: open target"`.
- Build interactive parts from vui components, not hand-made text
  properties: only vui's elements are TAB stops.

## Loading, errors, actions

- **Loading** shows only in the mode line, `(Mayhem:loading)`.  Stale
  content stays until fresh data replaces it.  A section's count appears
  once known: `Projects`, then `Projects (3)`.
- **Errors**: show the error message where the data would be, after
  `Fetching <what> failed:` in the `error` face.  An empty result shows
  a notice such as `No projects` in `shadow`.
- **Actions** (stop or start a run) never block on the API: show
  "Stopping…" in place of the button, refresh when it returns, and on
  failure restore the button and report in the echo area.

## Layout

- Timestamps: relative age (`3 days ago`), exact time in `help-echo`.
- Text a user may copy (backtraces, logs) starts at column 0.

## Windows and buffers

- Open pages via `display-buffer`; from a mayhem page, reuse the selected
  window so RET drills down in place.
- `q` quits the window (back to the previous page), `g` refreshes.
- Name buffers after what they show: `*mayhem*`, `*mayhem: project*`,
  `*mayhem: project/target*`, `*mayhem: project/target/N*`.
