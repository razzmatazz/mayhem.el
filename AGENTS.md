# Agent Instructions

Read [README.md](README.md), [CONTRIBUTING.md](CONTRIBUTING.md) (code
conventions), [docs/user-interface-conventions.md](docs/user-interface-conventions.md)
and [docs/using-vui.md](docs/using-vui.md) first.

## Rules

- **Never commit or modify git state.**  The developer handles commits.
- **Run `make ci` after every change** and fix all errors and warnings.
  Run it once at a time: parallel runs clobber each other's output.
- **Talk to Mayhem through its REST API** (`mayhem--api-get`); use the
  `mayhem` CLI only for what the API cannot do.
- **Call only declared dependencies** (`Package-Requires` in `mayhem.el`).
- **Keep comments minimal**: the why, not the what.  Docs should still
  tell a newcomer what a feature does, why, and how to use or extend it.
- **Never edit source files through Emacs** (`eval-elisp`, buffer edits);
  the buffer and the file drift apart.  Use file tools or the shell.

## Screenshots

[docs/screenshots](docs/screenshots/README.md) shows every page,
drawn from the made-up data in `test/screenshots/fixtures.el`.

- **After changing what a page shows, or adding one, run `make
  screenshots`** and check the diff of the `.txt` files it rewrites:
  they should change as you meant, and nothing else.  Read the PNGs of
  the pages you changed too.
- A new page or view gets a shot: add a marker to
  `docs/screenshots/README.md`, with a line on what it shows.
- If it fails naming a resource with no fixture, add one to
  `fixtures.el` in the shape its fetch gives.  When a resource's shape
  changes, update its fixture likewise.
- Keep fixtures made up: never real workspaces, people, hashes or
  anything from the user's cache.

## Checking parens

Before reloading or `make ci`, check every edited file:

```bash
python3 tools/el-outline.py mayhem*.el
```

It exits 1 on unbalanced files and marks `← UNCLOSED` or `← SPANS INTO
NEXT FORM`.  To locate the break: `--trace DEFUN`, `--trace-line N`,
`--depth-at N`, `--close-map --lines A-B` (see the script's header).

## Reloading into Emacs

After edits, reload and redraw every open page with one `eval-elisp`
call (any value but `ok` is an error; the second list names the pages
redrawn):

```elisp
(let (results)
  (dolist (f (list "mayhem-core.el" "mayhem-sync.el" "mayhem-vui.el" "mayhem-mayhemfile.el"
                  "mayhem-workspace.el" "mayhem-project.el" "mayhem-target.el"
                  "mayhem-defect.el" "mayhem-run.el" "mayhem-testcase.el"
                  "mayhem-testsuite.el" "mayhem-search.el"
                  "mayhem.el"))
    (condition-case err
        (with-temp-buffer
          (insert-file-contents (expand-file-name f "/Users/bob/src/mayhem.el"))
          (emacs-lisp-mode)
          (eval-buffer)
          (push (cons f 'ok) results))
      (error (push (cons f (error-message-string err)) results))))
  (list (nreverse results)
        (delq nil (mapcar (lambda (b)
                            (when-let* (((string-prefix-p "*mayhem" (buffer-name b)))
                                        (instance (vui-get-instance b)))
                              (condition-case err
                                  (progn (vui-rerender instance) (buffer-name b))
                                (error (format "%s: %s" (buffer-name b)
                                               (error-message-string err))))))
                          (buffer-list)))))
```

- Load `mayhem-core.el` first, then `mayhem-sync.el`, `mayhem-vui.el`,
  `mayhem-mayhemfile.el`, the page files, and `mayhem.el` last.
- `vui-rerender` draws a page with the reloaded functions and keeps its
  state (folds, tab, filters).  `g` (`mayhem-refresh`) won't: it
  refetches, and data that hasn't changed doesn't redraw.  Reopening
  doesn't either: `mayhem-open-page` reuses a mounted page.
- A mounted component keeps its old `vui-defcomponent` render and
  props, so after changing one, remount the pages that show it: this
  reopens each, back in its windows at its point, losing its folds.

  ```elisp
  (delq nil
    (mapcar (lambda (buf)
              (when-let* (((string-prefix-p "*mayhem" (buffer-name buf)))
                          ((vui-get-instance buf))
                          (page (buffer-local-value 'mayhem-page buf)))
                (let ((name (buffer-name buf))
                      (windows (get-buffer-window-list buf nil t))
                      (pt (with-current-buffer buf (point))))
                  (condition-case err
                      (progn
                        (kill-buffer buf)
                        (save-window-excursion (mayhem-open page))
                        (when-let* ((new (get-buffer name)))
                          (dolist (w windows) (set-window-buffer w new))
                          (with-current-buffer new (goto-char (min pt (point-max)))))
                        name)
                    (error (format "%s: %s" name (error-message-string err)))))))
            (buffer-list)))
  ```

- Otherwise don't kill the user's buffers.  Kill only when a keymap
  changed (and `makunbound` the map first, as `defvar` won't rebind
  it) or a stale `.elc` shadows the source.  Say if you did.
- Never use `unload-feature`: it cascades into dependent features.

## Checking a page in Emacs

Read what a page shows, and drive it, through its buffer, never
through keys: under evil, `g` is a prefix, not `mayhem-refresh`.

```elisp
(with-current-buffer "*mayhem: OWNER/PROJECT/TARGET/RUN*"
  (buffer-substring-no-properties (point-min) (min (point-max) 2000)))
```

- Press a button or fold by its text: `(search-forward "▶ Source")`,
  then `(push-button (match-beginning 0))`.  vui redraws after the
  handler returns, so read the result in a second call; folds unfold
  over a few frames, so a fold read at once may be half open.
- Bind `case-fold-search` to nil when searching a page: `Overrides`
  otherwise matches `3 overrides` on the line above, and the press
  lands on the wrong button.
- The user may be using the page: read it before pressing, so a fold
  they opened isn't closed.
- Leave a page as you found it: close folds you opened.
- If a call is refused as blocked, the user may not have approved it
  yet: ask, then retry.

## melpazoid

`make ci` runs MELPA's review checks, which rule out:

- top-level `define-key`, `setq` or `add-hook`: bind keys in the map's
  `defvar`, and make a hook's function its `defvar` default, as
  `mayhem-sync-change-functions` does;
- `ignore-errors`: catch only the error meant (`condition-case`).

## "Function not known to be defined" warnings

Files compile in parallel, so add a `declare-function` in the caller:

```elisp
(declare-function mayhem-target-mode "mayhem-target" ())
```

This is safe because every entry point lives in `mayhem.el`, which
`require`s every file.  `make lint` checks each with `check-declare`;
prefix the file with `ext:` for a C primitive some builds lack.
