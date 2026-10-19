# mayhem.el

An Emacs client for [Mayhem](https://mayhem.security/) ([app.mayhem.security](https://app.mayhem.security)), built with [vui.el](https://github.com/d12frosted/vui.el).

## Status

Early work in progress.  For now there is a single view: a dashboard of
your projects and their targets.

## Requirements

- Emacs 29.1 or later
- [vui.el](https://github.com/d12frosted/vui.el)
- A Mayhem API token in `~/.config/mayhem/mayhem`, as written by the
  Mayhem CLI's `mayhem login`.  mayhem.el reads its `url` and `token`
  and stores no credentials of its own.

## Usage

`M-x mayhem` opens the dashboard (`*mayhem*`).  It fetches every project
visible to you from the Mayhem API in the background, showing `:loading`
in the mode line meanwhile, and lists each `owner/project` with its
targets under it.  If a request fails, for example because the token is
missing or expired, the error is shown in place of the list.

| Key | Command |
|---|---|
| `g` | `mayhem-dashboard-refresh`: fetch again |
| `q` | quit the window |

Set `mayhem-config-file` if your config lives elsewhere.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md).  `make
ci` compiles, lints and tests in a container.
