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

- **Anything outside Mayhem links to its own page.**  A repository,
  branch, commit, CI build, Docker image or CWE entry is shown as a
  link (`mayhem-link`) to where it lives on the web, so one RET takes
  the user there instead of a copy-paste and a search.  Build the URL
  from what the API gives (`mayhem--repo-url`, `mayhem--image-url`);
  when there is no page to point to (an image in a private registry, a
  repository on an unknown host), show plain text rather than a link
  that leads nowhere.  Rows that open a page on RET carry no links
  inside them, so RET has one meaning on the line.
- Brackets mean an action (`[Stop]`, `[Load more]`); plain text is content.
  A page's own name is never a button.
- **Walk without a jump.**  A page's heading is a breadcrumb: each part
  naming an enclosing page (the server's host for the dashboard, then
  owner, project, target, run) links to it; build it with
  `mayhem-page-heading`.  Its last part is the page itself, followed by
  the page's kind in grey (`host/o/p/t/#7 run`,
  `host/o workspace`), since that part is often a bare name or
  number.  A long name in it is cut in the middle
  (`mayhem-cut-middle`), whole on hover.
  A field naming another page (`Run  run #7`) links to it, with
  `mayhem-page-link` or `mayhem-run-link`.
- **Say what a number is.**  Runs and defects are both numbered from 1
  within a target, so a bare `7` could be either.  A run's number is
  written `#7` and a defect's `!12`, everywhere.  In text the kind goes
  in front too: `run #7`, `defect !12`.  This holds even where the
  label beside it says the same (`Run  run #7`): the link reads right
  on its own, and is the same text wherever it appears.
  `mayhem-run-link` writes `run #N` for you.  A page heading, where
  each part is short, drops the kind word before a number
  (`o/p/t/#7/abcd1234 test case`), and so does a table column of numbers
  under a heading that already names them, such as a target's run
  list (`#7`).
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

- **Colour says how something went**, so a list can be read at a
  glance: `success` (green) for what went well (a completed run, a
  passing test case), `error` (red) for what failed (a failed run, a
  failing test case, a high-severity defect), `warning` (yellow) for
  what is still going or needs a look (a running run, a medium
  defect), and `mayhem-label` (grey) for what ended without a verdict
  or hasn't started (stopped, pending).  Use the shared helpers so a
  status is the same colour on every page: `mayhem-run-status` for a
  run, `mayhem-testcase-status` for a test case,
  `mayhem-defect-severity-face` for a defect.  Colour only the
  status word itself, never the whole row.
- Timestamps: relative age (`3 days ago`), exact time in `help-echo`.
- Table rows, notices and charts start at column 0; only a tree (the
  workspace's targets under their projects) indents.
- A page keeps within `mayhem-page-width`: its window's width, at most
  `mayhem-max-width`.  vui re-renders a page when its window's width
  changes.  A row whose title or name can be long builds its line with
  `mayhem-line` parts, the long one a `mayhem-fit` (padded to the
  table's longest, cut with `…` when the window is too narrow); tab
  bars span the page width, wrapped text and charts narrow with it.
- A tab bar is followed directly by what its tab shows, no blank line.
- What the user may not see (a defect trend outside one's workspaces)
  is left out, heading and all, not replaced by a notice.
- Text a user may copy (backtraces, logs) starts at column 0.

## Windows and buffers

- Open pages with `mayhem-open-page` (through `mayhem-display-buffer`);
  from a mayhem page it reuses the selected window, so RET drills down in
  place.  `S-RET` (`mayhem-visit-other-window`) runs whatever RET does at
  point with the page shown in another window, so new rows need nothing
  extra.
- Every page's mode derives from `mayhem-page-mode`, which binds `g`, `q`,
  `S-RET` (and `o` and `O` under Evil) and `C-c C-v`.
- **One page, two views.**  `C-c C-v` (`mayhem-toggle-view`) switches
  a page between two ways of showing the same data, such as a test
  case's bytes as a hex dump or as plain text.  It is one key on every
  page, so users learn it once; on a page with a single view it says
  so.  To give a page a second view, set `mayhem-views` in its mode to
  the two views' names (they show in the echo area on each switch), and
  render the second while `mayhem-other-view` is non-nil.  The choice
  is the buffer's, so it survives `g`.
- `q` (`mayhem-quit-window`) quits the window, back to the previous
  page, deleting a window made for mayhem.el once it has no mayhem page
  left.  `g` refreshes; `mayhem-page-mode` sets `revert-buffer-function`,
  so `revert-buffer` (`gr` under Evil) does too.
- Name buffers after what they show: `*mayhem*`, `*mayhem: owner*`,
  `*mayhem: project*`,
  `*mayhem: project/target*`, `*mayhem: project/target/N*`, each
  `project` qualified by its owner (`owner/project`).
