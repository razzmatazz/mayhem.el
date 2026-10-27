# mayhem.el

An Emacs client for [Mayhem](https://mayhem.security/) ([app.mayhem.security](https://app.mayhem.security)), built with [vui.el](https://github.com/d12frosted/vui.el).

![A run in mayhem.el](docs/screenshots/run.png)

Browse what Mayhem found, in Emacs buffers that read like the web
app's pages, with cached data shown at once:

- **Dashboard and workspaces**: who you are, your projects and their targets
- **Projects and targets**: defects, defect trends, latest runs, coverage
- **Runs**: how they went, progress, coverage, defects, tests and the event log
- **Defects and test cases**: evidence, reproducers, bytes, output, backtraces
- **Mayhemfiles**: a major mode that checks them with `mayhem validate`
- **Web app links**: open in mayhem.el wherever you follow them in Emacs

It is early work in progress, and read-only.  See [every
page](docs/screenshots/README.md), drawn from made-up data.

> **Note:** This project was largely written with the assistance of LLMs (Claude).
> Source files carry an `Assisted-by:` header line per the [MELPA attribution convention](https://github.com/melpa/melpa/blob/master/CONTRIBUTING.org).

## Getting started

You need:

- **Emacs 29.1 or later**, built with SQLite (`(sqlite-available-p)`
  returns `t`).
- **A Mayhem API token**, in `~/.config/mayhem/mayhem` as the Mayhem
  CLI's `mayhem login` writes it.  mayhem.el reads its `url` and
  `token` and stores no credentials of its own.
- **[vui.el](https://melpa.org/#/vui)**, from MELPA.
- Optionally **the Mayhem CLI** on your `PATH`, to check Mayhemfiles.

Then clone this repository and load it:

```emacs-lisp
(add-to-list 'load-path "/path/to/mayhem.el")
(require 'mayhem)
```

`mayhem-jump` works from any buffer, so you may want it global:

```emacs-lisp
(keymap-global-set "C-c m" #'mayhem-jump)
```

| Command | Opens |
|---------|-------|
| `M-x mayhem` | Your dashboard |
| `M-x mayhem-jump` | A workspace, project or target, by name |
| `M-x mayhem-browse-url` | A pasted web app link |

[Using mayhem.el](docs/usage.md) walks through every page.

## Keybindings

| Key | Action |
|-----|--------|
| `RET` | Open the thing at point, or switch to the tab at point (Evil: also `o`) |
| `S-RET` | The same, in another window (Evil: `O`) |
| `q` | Back to the previous page |
| `g` / `gr` | Refresh the page |
| `C-c C-j` | Jump to a workspace, project or target |
| `C-c C-o` | Open this page in the web app |
| `C-c C-v` | Another view, say a test case's bytes as hex or text |
| `F` | Filter a list of every defect, run or test case |
| `w` | Save the test case at point to a file |

## More

- [Using mayhem.el](docs/usage.md): every page, options and caching, in detail
- [Screenshots](docs/screenshots/README.md): every page, pictured
- [CONTRIBUTING.md](CONTRIBUTING.md): code conventions, building, testing, CI

`M-x mayhem-doctor` reports, as text to paste into a bug report, which
files are loaded (and whether a compiled one is stale), the cache's
size and largest entries, and how long `mayhem-jump` takes to open.  It
names your workspaces, projects and targets, but not your token.

## License

[GNU General Public License](LICENSE).
