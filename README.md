# mayhem.el

An Emacs client for [Mayhem](https://mayhem.security/) ([app.mayhem.security](https://app.mayhem.security)), built with [vui.el](https://github.com/d12frosted/vui.el).

## Status

Early work in progress.  You can browse your workspaces, projects,
targets, runs, defects and test cases, read-only.

## Requirements

- Emacs 29.1 or later, built with SQLite (`(sqlite-available-p)`)
- [vui.el](https://github.com/d12frosted/vui.el)
- A Mayhem API token in `~/.config/mayhem/mayhem`, as written by the
  Mayhem CLI's `mayhem login`.  mayhem.el reads its `url` and `token`
  and stores no credentials of its own.

## Getting started

`M-x mayhem` opens the dashboard: who you are logged in as, and the
workspaces (users and orgs) whose projects you can see.  From there,
RET on anything opens its page.

Pages show cached data at once and refetch in the background;
`:loading` in the mode line means a fetch is under way.  If one fails,
say because your token expired, the error shows in the header line.

## Keys

| Key | Command |
|---|---|
| `RET` | open what is at point, or switch to the tab at point (also `o` under Evil) |
| `S-RET` | open it in another window (also `O` under Evil) |
| `g` | refresh the page (`gr` under Evil) |
| `C-c C-j` | jump to a workspace, project or target by name |
| `C-c C-o` | open this page in the web app, in a browser |
| `C-c C-v` | switch the page's view, say a test case's bytes between hex and text |
| `F` | filter a list of every defect or run, by severity, CWE, state, status or branch |
| `q` | go back to the previous page |

`mayhem-jump` (`C-c C-j`) works anywhere, so you may want it global:

```elisp
(keymap-global-set "C-c m" #'mayhem-jump)
```

## Pages

- **Workspace**: its projects and their targets.
- **Project**: its repository, remaining and fixed defects, how many
  targets pass their tests, a defect trend chart, and its targets
  (active and archived tabs), each with what its latest run found.
- **Target**: its latest run, with what it found, its line coverage,
  hardening, repository and image; its defect trend; and its latest
  runs and most severe defects, a few of each, with `[Show all 78 runs]`
  opening a page of every one, tallied and filterable.
- **Run**: status, when it started and how long it waited in the
  queue, how long it ran against its time limit and its CPU time, its
  repository, branch, commit and parent commit, the CI build and build
  ID that started it, its image, and each task (regression,
  exploitability, behavior, coverage), coloured by how it went with
  how long it took.  RET on `Mayhemfile` shows the Mayhemfile it was
  started with, read-only, in your YAML mode.  What the CLI overrode,
  the environment it added and the files sent are each a line, folded
  when too wide for one.  A code run also has a chart of test cases
  processed and defects found over time, as in the web app (once the
  run is done, folded in the header as `▶ Progress`), and its
  coverage, with the inputs each engine tested.  Its defects follow,
  the first 10 until `Show all` lists the rest, and its tests: counts,
  crashes, Valgrind errors, the corpus and the failing test cases, the
  first 10 of them likewise; an API run has its endpoints instead.
  RET on `Log` opens the run's event log, a page of its own; the field
  counts its errors and warnings.  A run that is still going, and its
  log, refresh themselves every 10 seconds.
- **Defect**: severity, CWE, the commit of the run that saw it,
  description and evidence: for an API defect the request, response
  and stack trace, for a crash the test cases that hit it (RET opens
  one), and one's reproducer and backtrace.
- **Test suite**: the optimized set of a target's test cases at the end
  of a run, newest first, each with its size, source, age and first
  bytes; RET on `Test suite` on the target page, or on `Optimized` on
  the run page's Tests, opens it.  `w` saves the test case at point to a
  file.  A finished run's suite is downloaded once and kept.
- **Test cases**: every test case of a run, the ones the optimized
  suite dropped too, newest first, each with its status, type, defects,
  source and execution time; filter them by status, type or source.
  RET on `All` on the run page's Tests, or on the run's count on its
  test suite page, opens it.
- **Test case**: its defects, how to reproduce it, its bytes, the
  target's output and the backtrace.

Repositories, branches, commits and CI builds are links, shown with
the repository's host (`github.com/owner/name`); RET follows them with
`browse-url`.  Branches and commits link on GitHub, GitLab and
Bitbucket.

Defect trends cover the last 12 months, 3 months, 30 days, 7 days or
24 hours; pick one with RET.  Only members of a workspace can see its
trends; others' pages leave the trend out.  Hover over a chart, or leave point on it, to see its numbers;
timestamps show the exact time the same way.

Pages follow their window's width up to `mayhem-max-width` columns
(100 by default): in a narrow window, titles and names are cut with
`…` and descriptions and charts narrow, so rows keep to one line.

## Web links

Links to the web app open in mayhem.el wherever Emacs follows a link,
for example:

- `https://app.mayhem.security/owner/project/target/1` (a run)
- `...?defect=N` (a defect)
- `.../1/tests?testcase=SHA` (a test case)

Links mayhem.el has no page for still go to the browser.
`M-x mayhem-browse-url` opens a pasted link.

## Customization

| Option | Default | What it does |
|---|---|---|
| `mayhem-open-urls` | `t` | open web app links in mayhem.el |
| `mayhem-max-width` | `100` | most columns a page takes; nil for the whole window |
| `mayhem-run-refresh-interval` | `10` | seconds between refreshes of a running run |
| `mayhem-sync-fresh-for` | `30` | seconds a page's data is reused before refetching |
| `mayhem-sync-settled-for` | a day | the same, for data that no longer changes: finished runs, defects, test cases |
| `mayhem-config-file` | `~/.config/mayhem/mayhem` | where your token is |
| `mayhem-sync-directory` | `~/.emacs.d/mayhem/` | where the cache is kept; deleting it is safe |

`g` always refetches, however fresh the data is.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md).  `make
ci` compiles, lints and tests in a container.

The API's own spec is in
[docs/mayhem-openapi.json](docs/mayhem-openapi.json); check it first for
endpoints and fields.  It lacks many that the web app and the CLI use:
[docs/mayhem-api-usage.md](docs/mayhem-api-usage.md) lists the ones
mayhem.el uses, and how to find others.
