# Using vui.el

Gotchas of vui.el as mayhem.el uses it.

- **Mounting.**  `vui-mount` enables `vui-mode` only if the buffer's mode
  doesn't derive from it, so set the page's mode first, then mount (see
  `mayhem` in `mayhem.el`).
- **Async data.**  Pages don't fetch: they read a sync resource with
  `mayhem-sync-use-resource` (see "Reading the sync store" below).  For
  anything else async, fetch in `vui-use-effect` and wrap the callback
  in `vui-async-callback`, so `vui-set-state` reaches the component.
  The callback may run in any buffer: capture the page's buffer first
  to touch buffer-local state like `mode-line-process`.
- **Timers.**  Cancel them on unmount (return a cleanup function), and
  stop them from the callback when done: setting unchanged state does not
  re-render, so nothing else will.
- **Layout.**  `vui-collapsible` indents only its first body line; pass
  `:indent 0` when rows indent themselves.  For rows, use `propertize`d
  `vui-text`, not `vui-button`, so segments keep their faces.
- **Update in place; don't remount.**  To change what a page shows, pass
  new props or state; a part that must start afresh takes the new value
  as its `:key`.  A remount reruns every fetch and loses folds.  Worse,
  vui runs handlers inside a `let` of `vui--root-instance`, so a
  `vui-mount` from a handler is undone on return and leaves the new
  page's effects running.  Remount only to start over (`g`, opening a
  page), and from a handler defer it with `(run-at-time 0 nil ...)`.

## Reading the sync store

Pages read their data from the sync layer (`mayhem-sync.el`), so they
paint at once from a local SQLite store and refetch behind.  Define a
resource beside its page, and read it during render:

```elisp
(mayhem-sync-define-resource projects ()
  :fetch #'mayhem--fetch-projects)     ; called with DONE, gets (OK DATA)

(let ((snapshot (mayhem-sync-use-resource '(projects))))
  (plist-get snapshot :data))           ; also :fetched-at :error :loading
```

- Opening a page fetches each resource unless it was fetched within
  `mayhem-sync-fresh-for` (30 s).  `g` calls `mayhem-sync-refresh`,
  which refetches them all; the page stays until new data lands.
- A fetch that returns the stored data renders nothing.  One that
  changes it re-renders every page reading it, from the root, so a
  component reading a resource must not be `:memo`.
- `:fetched-at` is nil until the first success; tell "no data yet"
  from "empty" by it.  `mayhem-snapshot-view` does: it shows the data,
  else a skeleton, else the error.  A failed refresh keeps the data and sets
  `:error`, shown in the header line.
- Data is stored printed, so it must be plain Lisp data.  A change to
  its shape bumps `mayhem-sync--schema`, which recreates the store.
- Only the basics of octocat.el's sync plan are here; entities shared
  between resources, mutations and prefetch come when pages need them.
