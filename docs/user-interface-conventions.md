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
| A list longer than a glance (a target's runs or defects) | its first few rows, then `[Show all 78 runs]`, which opens a page with the whole list |
| A long list fetched whole, with no page of its own (a defect's test cases) | its first five rows, then `[Show all 65 test cases]`, which grows it in place, and `[Show fewer]` |
| A page of a whole list | under its heading, a tally of every item (`mayhem-tally`), then the facets it filters by (`mayhem-list-filter-bar`, `F`) |

- **Recent data at first glance.**  A page opens showing what changed
  lately, so the user can see how things stand without a keypress.
  Lists such as a target's runs and defects are therefore stacked one
  under another, each cut to its newest or most severe few rows, and
  not put behind tabs, where all but one would be hidden.  A list whose
  table header names it (`RUN`) needs no heading; one that does, such
  as defects under their tally, gives the whole count (`Defects (6)`).
  A button naming that count (`[Show all 78 runs]`,
  `[Show all 6 defects]`) opens the full list as a page of its own,
  rather than growing the list in place, so the sections below stay
  where they are and the long list can be fetched page by page.  A
  list that is fetched whole and has no page of its own, such as a
  defect's test cases or a run's defects, grows in place instead,
  past its first 10 or so.  Keep tabs for views of one list read one at
  a time, such as a project's active and archived targets.  Detail
  read apart from the rest, such as a run's log, is a page of its own,
  linked from a header field (`Log  24 events`).

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
  naming an enclosing page (owner, project, target) links to it; build
  it with `mayhem-page-heading`.  It starts with the server's host,
  plain: one rarely walks up to the dashboard, and a link there would
  only be one more TAB stop.  Its last part is the page itself, followed by
  the page's kind in grey (`host/o  workspace`, `host/o/p/t  code
  target`) when that part is a bare name, number or hash.  When the
  part says it already, leave the kind out (nil): the label would only
  repeat it.
- **A page below a target names itself after it.**  A run, a defect, or
  the list of every run or defect is a page of the target's: its
  breadcrumb ends at the target, linked, then says in grey what the
  target is and names the page in the heading's face
  (`host/o/p/t  code target, run #7`, `host/o/p/t  code target,
  defect !12`, `host/o/p/t  code target, runs`), with
  `mayhem-target-page-heading`.  A list the web app has no page for
  so adds no part that would read as a URL leading nowhere.  A list page has no heading of its own
  above the list either (`Runs (78)`): the whole page is the list.
  Pages below a run (its test suite, a test case) name the run too,
  linked: `host/o/p/t  code target, run #7, test case abcd1234`,
  `host/o/p/t  code target, run #7, test suite`.
- A long name in a heading is cut in the middle (`mayhem-cut-middle`),
  whole on hover.
  A field naming another page (`Run  run #7`) links to it, with
  `mayhem-page-link` or `mayhem-run-link`.
- **Say what a number is.**  Runs and defects are both numbered from 1
  within a target, so a bare `7` could be either.  A run's number is
  written `#7` and a defect's `!12`, everywhere.  In text the kind goes
  in front too: `run #7`, `defect !12`.  This holds even where the
  label beside it says the same (`Run  run #7`): the link reads right
  on its own, and is the same text wherever it appears.
  `mayhem-run-link` writes `run #N` for you.  A table column of numbers
  under a heading that already names them, such as a target's run list,
  drops the kind word (`#7`).
- **Say what a target tests.**  A code target and an API target show
  different things (tests and coverage, or endpoints), so a target's
  type is shown wherever the target is: its page's kind (`host/o/p/t
  code target`), its completion annotation (`code target`, `api
  target`), and a grey `code` or `api` beside it in the project's and
  workspace's lists.  Write it with `mayhem-target-type` and
  `mayhem-target-kind`.
- **Tally, then filter, a whole list.**  A page listing every defect or
  run of a target says how they split, the way the web app does
  (`4 high, 2 medium`, `73 completed, 5 stopped`), counting the whole
  list so the line keeps still while a filter is set.  Below it is a
  `Filter` line of a button per facet, as octocat.el's issue and PR
  lists have; `RET` on one, or `F`, picks its value from those in the
  list, and picking the one set clears it.  A set facet shows its value
  (`[Severity: high]`), and `[clear]` drops them all, followed by how
  many are left (`5 of 78`).  A blank line comes between the tally and
  the filter, and between the filter and the list.  The filter is
  buffer-local, kept across refreshes.  A page sets its facets in its mode
  (`mayhem-list-facets`).  The items are all fetched, so filtering is
  done here.
- **Name a table's columns.**  Every table (runs, defects, a defect's
  test cases) starts with a grey line naming its columns (`mayhem-columns` with a HEADER), so
  a bare `6` or `64/89` reads as what it is.  The names are in
  capitals, which reads as a header in any font, where bold may not.
  Keep them short, abbreviated where need be (`COV`, `PASS`), so they
  widen the table little if at all.  With the header saying what a
  column holds, its cells drop the words they would otherwise repeat:
  `6` under `DEFECTS`, not `6 defects`.  A name may span the columns
  after it (nil names in the HEADER) where they tell one thing: a
  count and its split by severity under `DEFECTS`, a level and its
  score under `SEVERITY`.  A spanning name can be a whole word, as it
  has the room.  A column empty in every row is left out, its name
  with it.
- **Show an empty field as `-`.**  A header field whose value the API
  left out (a defect's `State`, `First seen`) shows a grey `-`, which
  `mayhem-field` writes for you, so the line reads as known to be
  empty rather than broken.  Leave a field out only where it can't
  apply, such as `CI` on a run not started from CI.
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
- Large or fractional numbers in a table (`INPUTS/S`): short
  (`5.2k`, `137k`, `1.4M`) with `mayhem--format-count`, exact in
  `help-echo`.  Counts read as exact (defects, test cases) stay whole.
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
