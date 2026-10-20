# User Interface Conventions

mayhem.el pages follow Magit and the rest of Emacs, so they behave as
users expect.

## Interactivity

| Situation | Approach |
|---|---|
| The whole line opens something | RET-able row: `vui-text` in a `vui-region` with a RET keymap, `mouse-face 'highlight`, `help-echo` |
| One control among others on a line | `vui-button` |
| A link out of mayhem.el (a GitHub commit, a CI build) | `mayhem-link`, which follows it with `browse-url` |
| A foldable block | `vui-collapsible` |
| Parts of a page shown one at a time | `mayhem-tab-row`: the current tab a heading, the others buttons, kept in the page's state |

- Brackets mean an action (`[Stop]`, `[Load more]`); plain text is content.
  A page's own name is never a button.
- **Walk without a jump.**  A page's heading is a breadcrumb: each part
  naming an enclosing page (`Mayhem` for the dashboard, then owner,
  project, target, run) links to it; build it with `mayhem-page-heading`.
  A field naming another page (`Run  #7`) links to it, with
  `mayhem-page-link` or `mayhem-run-link`.
- `help-echo` reads `"RET: <imperative>"`, e.g. `"RET: open target"`.
- Build interactive parts from vui components, not hand-made text
  properties: only vui's elements are TAB stops.

## Loading, errors, actions

- **Loading** shows only in the mode line, `(Mayhem:loading)`.  Pages
  paint cached data at once; it stays until fresh data replaces it.
- **No data yet**: a **skeleton**, grey bars (`mayhem-skeleton`, face
  `mayhem-skeleton`) shaped like the content to come, with the real
  labels and headings, so the layout doesn't jump when it lands.  Every
  page part passes one to `mayhem-snapshot-view`.  A section's count appears
  once known: `Projects`, then `Projects (3)`.
- **A failed refresh** over shown data keeps the data and says so in the
  header line: `Refresh failed: MSG; g to retry`.
- **Errors** with no data: show the error message where the data would be, after
  `Fetching <what> failed:` in the `error` face.  An empty result shows
  a notice such as `No projects` in `shadow`.
- **Actions** (stop or start a run) never block on the API: show
  "Stopping…" in place of the button, refresh when it returns, and on
  failure restore the button and report in the echo area.

## Layout

- Timestamps: relative age (`3 days ago`), exact time in `help-echo`.
- Text a user may copy (backtraces, logs) starts at column 0.

## Windows and buffers

- Open pages with `mayhem-open-page` (through `mayhem-display-buffer`);
  from a mayhem page it reuses the selected window, so RET drills down in
  place.  `S-RET` (`mayhem-visit-other-window`) runs whatever RET does at
  point with the page shown in another window, so new rows need nothing
  extra.
- Every page's mode derives from `mayhem-page-mode`, which binds `g`, `q`
  and `S-RET`.
- `q` (`mayhem-quit-window`) quits the window, back to the previous
  page, deleting a window made for mayhem.el once it has no mayhem page
  left.  `g` refreshes; `mayhem-page-mode` sets `revert-buffer-function`,
  so `revert-buffer` (`gr` under Evil) does too.
- Name buffers after what they show: `*mayhem*`, `*mayhem: owner*`,
  `*mayhem: project*`,
  `*mayhem: project/target*`, `*mayhem: project/target/N*`, each
  `project` qualified by its owner (`owner/project`).
