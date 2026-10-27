# Contributing to mayhem.el

## AI-assisted code

AI assistance is fine, but you are the first and most thorough reviewer of
its output.  Mark it with a
[Linux-style `Assisted-by:` line](https://docs.kernel.org/process/coding-assistants.html#attribution)
after the `Author:` header:

```elisp
;; Author: Your Name <you@example.com>
;; Assisted-by: Claude:claude-opus-5-5
```

## Building and testing

Everything runs in a Docker (or Podman) container, so you need no local
Emacs.  Dependencies come from the `Package-Requires` header of
`mayhem.el`, via [Eldev](https://github.com/emacs-eldev/eldev).

| Command | Does |
|---------|------|
| `make ci` | Compile, lint and test on Emacs 31.1, then run melpazoid |
| `make ci EMACS=29.1` | The same on another release |
| `make ci-all` | 29.1, 30.2 and 31.1 at once, as CI does |
| `make screenshots` | Redraw [docs/screenshots](docs/screenshots/README.md) from made-up data (see [Updating](docs/screenshots/README.md#updating)) |
| `make bench` | Time `mayhem-jump`'s search on a large made-up cache (`BENCH_TARGETS=8000` for another size) |

`make ci-all` must pass before you send changes.

Lint covers `checkdoc`, `package-lint`, `check-declare` and
`elisp-lint`, which wants every line indented as stock Emacs indents
it, no tabs or trailing whitespace, and at most 100 columns.
[melpazoid](https://github.com/riscy/melpazoid) runs MELPA's review
checks; any finding fails the build, and its reports land in `.ci/`.
It is pinned by `MELPAZOID_COMMIT` in the `Makefile`.

Each container runs as your user, with no capabilities, no network
but to fetch, and the tree read-only but `.eldev/` and
`docs/screenshots/`.

GitHub Actions runs the same on all three releases, on every push and
pull request ([test.yml](.github/workflows/test.yml)).

## The Mayhem API

The API's own spec is in
[docs/mayhem-openapi.json](docs/mayhem-openapi.json); check it first for
endpoints and fields.  It lacks many that the web app and the CLI use:
[docs/mayhem-api-usage.md](docs/mayhem-api-usage.md) lists the ones
mayhem.el uses, and how to find others.  How pages cache and refetch
is in [docs/mayhem-sync.md](docs/mayhem-sync.md).

## Code conventions

- **Mayhem through its REST API.**  Request with `mayhem--api-get` (or
  `mayhem--api-get-all` for paged lists); shape responses in pure, tested
  functions in `mayhem-core.el`.  See
  [docs/mayhem-api-usage.md](docs/mayhem-api-usage.md) for how.  Look up
  endpoints and fields in the API's OpenAPI spec,
  [docs/mayhem-openapi.json](docs/mayhem-openapi.json), first.  It
  lacks many (`testsuite.tar`, `testcase-result`): find those in the
  web app's JS bundle or the CLI, as mayhem-api-usage.md says.  Fall
  back to the `mayhem` CLI only for what the API cannot do.
- **Entry points live in `mayhem.el`.**  Every `;;;###autoload` command is
  defined there, and `mayhem.el` `require`s every other file, so any
  command a user runs has everything loaded.  Put a new view's mode and
  logic in its own `mayhem-<feature>.el`, deriving from `mayhem-page-mode`
  and opened with `mayhem-open-page` (`mayhem-vui.el`).
- **vui.el for every buffer.**  Each page is a vui component in a mode
  derived from `vui-mode`.  Read [docs/using-vui.md](docs/using-vui.md)
  first.
- **Functional core.**  Functions take what they need as arguments and
  return a value; side effects stay in commands, effects and async
  callbacks.  Render code must not select windows, move point, change
  global state or prompt: vui re-renders from timers, often in an
  unselected window.
- **Pages read the sync store** (`mayhem-sync-use-resource`), never
  fetch directly, so they paint at once from cache; see
  [docs/using-vui.md](docs/using-vui.md).
- **Loading shows in the mode line** (`mode-line-process`), never by
  clearing the buffer: stale content stays until fresh data arrives.
- **Dependencies** are exactly the `Package-Requires` of `mayhem.el`,
  from which Eldev takes them too.

UI conventions (RET-able rows, buttons, windows, buffer names) are in
[docs/user-interface-conventions.md](docs/user-interface-conventions.md).
