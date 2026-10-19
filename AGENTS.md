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

## Checking parens

Before reloading or `make ci`, check every edited file:

```bash
python3 tools/el-outline.py mayhem.el mayhem-core.el mayhem-sync.el
```

It exits 1 on unbalanced files and marks `← UNCLOSED` or `← SPANS INTO
NEXT FORM`.  To locate the break: `--trace DEFUN`, `--trace-line N`,
`--depth-at N`, `--close-map --lines A-B` (see the script's header).

## Reloading into Emacs

After edits, reload with one `eval-elisp` call (any value but `ok` is an
error):

```elisp
(let (results)
  (dolist (f (list "mayhem-core.el" "mayhem-sync.el" "mayhem.el"))
    (condition-case err
        (with-temp-buffer
          (insert-file-contents (expand-file-name f "/Users/bob/src/mayhem.el"))
          (emacs-lisp-mode)
          (eval-buffer)
          (push (cons f 'ok) results))
      (error (push (cons f (error-message-string err)) results))))
  (nreverse results))
```

- Load `mayhem-core.el` first, then `mayhem-sync.el`, and `mayhem.el` last.
- Don't kill the user's buffers; tell them to press `g`.  Kill only when a
  keymap changed (and `makunbound` the map first, as `defvar` won't
  rebind it) or a stale `.elc` shadows the source.  Say if you did.
- Never use `unload-feature`: it cascades into dependent features.

## "Function not known to be defined" warnings

Files compile in parallel, so add a `declare-function` in the caller:

```elisp
(declare-function mayhem-target-mode "mayhem-target" ())
```

This is safe because every entry point lives in `mayhem.el`, which
`require`s every file.
