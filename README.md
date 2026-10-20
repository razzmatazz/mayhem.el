# mayhem.el

An Emacs client for [Mayhem](https://mayhem.security/) ([app.mayhem.security](https://app.mayhem.security)), built with [vui.el](https://github.com/d12frosted/vui.el).

## Status

Early work in progress.  There is a dashboard of workspaces, and a page
for each workspace, project, target, run and defect.

## Requirements

- Emacs 29.1 or later, built with SQLite (`(sqlite-available-p)`)
- [vui.el](https://github.com/d12frosted/vui.el)
- A Mayhem API token in `~/.config/mayhem/mayhem`, as written by the
  Mayhem CLI's `mayhem login`.  mayhem.el reads its `url` and `token`
  and stores no credentials of its own.

## Usage

`M-x mayhem` opens the dashboard (`*mayhem*`), listing the workspaces
(users and orgs) that own the projects visible to you.  It paints
at once from a local cache, then refetches from the Mayhem API in the
background, showing `:loading` in the mode line meanwhile.  If a
request fails, for example because the token is missing or expired, the
error shows in place of the list, or in the header line over cached
data.

RET opens what is at point in the same window; S-RET opens it in
another window.  A workspace's page lists its projects with their
targets, a project's page its details and targets, and a target's page
its latest runs; RET on a run opens its page.  A code run's page charts
the test cases processed and defects found over time; below, in tabs,
are its defects, tests (counts and failing test cases), coverage and
event log, or for an API run its defects, endpoints and event log.  A run page refetches every 10
seconds (`mayhem-run-refresh-interval`) while the run is going.  RET on
a defect opens its page: its CWE and description, and its evidence: the
stack trace, request and response of an API defect, or the backtrace
and reproducer of a crash.  RET on a test case opens its page: its
defects, how to reproduce it, its bytes, output and backtrace.

| Key | Command |
|---|---|
| `RET` | open the workspace, project, target, run, defect or test case at point |
| `S-RET` | `mayhem-visit-other-window`: open it in another window |
| `g` | `mayhem-refresh`: fetch again (`gr` under Evil) |
| `C-c C-o` | `mayhem-browse`: open the page in the web app, in a browser |
| `C-c C-j` | `mayhem-jump`: open a workspace, project or target, read with completion |
| `q` | `mayhem-quit-window`: back to the previous page |

The dashboard shows who you are logged in as, and the host.
`mayhem-jump` completes on the cache, as the API has no search, and
refetches it behind the prompt: what lands shows on the next
keystroke.  It works anywhere; bind it globally if you like:

```elisp
(keymap-global-set "C-c m" #'mayhem-jump)
```

Links to the web app (`https://app.mayhem.security/owner/project/target/1`,
a defect's `...?defect=N`, or a test case's `.../1/tests?testcase=SHA`) open in mayhem.el's page for them,
wherever Emacs follows a link, once mayhem.el is loaded; links it has
no page for still go to the browser.  `M-x mayhem-browse-url` opens a
pasted one.  Set `mayhem-open-urls` to nil to turn this off.

Set `mayhem-config-file` if your config lives elsewhere.  The cache is
kept in `mayhem-sync-directory`; deleting it is safe.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md).  `make
ci` compiles, lints and tests in a container.
