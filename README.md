# mayhem.el

An Emacs client for [Mayhem](https://mayhem.security/) ([app.mayhem.security](https://app.mayhem.security)), built with [vui.el](https://github.com/d12frosted/vui.el).

## Status

Early work in progress.  There is a dashboard of workspaces, and a page
for each workspace, project, target and run.

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
its latest runs; RET on a run opens its page, with its defects and,
for an API run, its endpoints.

| Key | Command |
|---|---|
| `RET` | open the workspace, project, target or run at point |
| `S-RET` | `mayhem-visit-other-window`: open it in another window |
| `g` | `mayhem-refresh`: fetch again (`gr` under Evil) |
| `q` | `mayhem-quit-window`: back to the previous page |

Set `mayhem-config-file` if your config lives elsewhere.  The cache is
kept in `mayhem-sync-directory`; deleting it is safe.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md).  `make
ci` compiles, lints and tests in a container.
