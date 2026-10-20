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
| `RET` | open what is at point, or switch to the tab at point |
| `S-RET` | open it in another window |
| `g` | refresh the page (`gr` under Evil) |
| `C-c C-j` | jump to a workspace, project or target by name |
| `C-c C-o` | open this page in the web app, in a browser |
| `q` | go back to the previous page |

`mayhem-jump` (`C-c C-j`) works anywhere, so you may want it global:

```elisp
(keymap-global-set "C-c m" #'mayhem-jump)
```

## Pages

- **Workspace**: its projects and their targets.
- **Project**: remaining and fixed defects, how many targets pass
  their tests, a defect trend chart, and its targets (active and
  archived tabs), each with what its latest run found.
- **Target**: what its latest run found, its defect trend, and tabs
  for its defects (most severe first) and latest runs.
- **Run**: status, image and commit.  A code run also has a chart of
  test cases processed and defects found over time, as in the web
  app.  Tabs: Defects, Tests (counts and failing test cases), Coverage
  and Log; an API run has Defects, Endpoints and Log.  A run that is
  still going refreshes itself every 10 seconds.
- **Defect**: severity, CWE, description and evidence: for an API
  defect the request, response and stack trace, for a crash the test
  cases that hit it (RET opens one), and one's reproducer and
  backtrace.
- **Test case**: its defects, how to reproduce it, its bytes, the
  target's output and the backtrace.

Defect trends cover the last 12 months, 3 months, 30 days, 7 days or
24 hours; pick one with RET.  Only members of a workspace can see its
trends.  Hover over a chart, or leave point on it, to see its numbers;
timestamps show the exact time the same way.

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
| `mayhem-run-refresh-interval` | `10` | seconds between refreshes of a running run |
| `mayhem-sync-fresh-for` | `30` | seconds a page's data is reused before refetching |
| `mayhem-sync-settled-for` | a day | the same, for data that no longer changes: finished runs, defects, test cases |
| `mayhem-config-file` | `~/.config/mayhem/mayhem` | where your token is |
| `mayhem-sync-directory` | `~/.emacs.d/mayhem/` | where the cache is kept; deleting it is safe |

`g` always refetches, however fresh the data is.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md).  `make
ci` compiles, lints and tests in a container.
