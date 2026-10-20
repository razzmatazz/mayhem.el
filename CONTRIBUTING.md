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

## Development

`make ci` compiles, lints and tests in a container (Docker or Podman).  It
must pass before you send changes.

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
  mirrored in `Eask`.

UI conventions (RET-able rows, buttons, windows, buffer names) are in
[docs/user-interface-conventions.md](docs/user-interface-conventions.md).
