# Using vui.el

Gotchas of vui.el as mayhem.el uses it.

- **Mounting.**  `vui-mount` enables `vui-mode` only if the buffer's mode
  doesn't derive from it, so set the page's mode first, then mount (see
  `mayhem` in `mayhem.el`).
- **Async data.**  Fetch in `:on-mount` or `vui-use-effect` and wrap the
  callback in `vui-async-callback`, so `vui-set-state` reaches the
  component.  The callback may run in any buffer: capture the page's
  buffer first to touch buffer-local state like `mode-line-process`.
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
