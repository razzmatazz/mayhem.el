# mayhem.el

An Emacs client for [Mayhem](https://mayhem.security/) ([app.mayhem.security](https://app.mayhem.security)), built with [vui.el](https://github.com/d12frosted/vui.el).

## Status

Early work in progress.  For now there is a single view: a dashboard of
your projects and their targets.

## Requirements

- Emacs 29.1 or later
- [vui.el](https://github.com/d12frosted/vui.el)
- The Mayhem CLI (`mayhem`), logged in
  (`mayhem login`).  All data comes from it; mayhem.el stores no
  credentials of its own.

## Usage

`M-x mayhem` opens the dashboard (`*mayhem*`).  It runs `mayhem list` in
the background, showing `:loading` in the mode line meanwhile, and lists
each project with its targets under it.  If the CLI fails, for example
because you are not logged in, its output is shown in place of the list.

| Key | Command |
|---|---|
| `g` | `mayhem-dashboard-refresh`: fetch again |
| `q` | quit the window |

Set `mayhem-program` if the CLI is not on your `PATH` as `mayhem`.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md).  `make
ci` compiles, lints and tests in a container.
