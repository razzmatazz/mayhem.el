;;; mayhem-core.el --- Mayhem CLI access for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Runs the `mayhem' CLI asynchronously and parses its output.  The
;; parsers are pure functions so they can be tested without the CLI.

;;; Code:

(require 'subr-x)

(defgroup mayhem nil
  "Emacs client for Mayhem."
  :group 'tools
  :prefix "mayhem-")

(defcustom mayhem-program "mayhem"
  "Name or path of the Mayhem CLI executable."
  :type 'string)

(defun mayhem--parse-list (output)
  "Parse OUTPUT of `mayhem list' into projects.
Each line naming a target is `project/target', or
`owner/project/target' when the CLI qualifies it with an owner.
Return a list of (PROJECT . TARGETS), both in output order; other
lines, such as the CLI's \"no projects\" notice, are ignored."
  (let (projects)
    (dolist (line (split-string output "\n" t "[ \t\r]+"))
      (when (string-match "\\`\\(?:[^/ \t]+/\\)?\\([^/ \t]+\\)/\\([^/ \t]+\\)\\'"
                          line)
        (let* ((project (match-string 1 line))
               (target (match-string 2 line))
               (cell (assoc project projects)))
          (if cell
              (setcdr cell (append (cdr cell) (list target)))
            (push (list project target) projects)))))
    (nreverse projects)))

(defun mayhem--run-async (args callback)
  "Run the Mayhem CLI with ARGS in the background.
Call CALLBACK with (OK OUTPUT) once it exits: OK is non-nil when
it exited with status 0, OUTPUT is its stdout and stderr, trimmed.
Run non-interactively, so the CLI never waits on a prompt."
  (let ((buf (generate-new-buffer " *mayhem-process*"))
        (process-environment (cons "MAYHEM_NONINTERACTIVE=1"
                                   process-environment)))
    (make-process
     :name "mayhem"
     :buffer buf
     :command (cons mayhem-program args)
     :connection-type 'pipe
     :noquery t
     :sentinel
     (lambda (proc _event)
       (unless (process-live-p proc)
         (let ((output (with-current-buffer buf
                         (string-trim (buffer-string)))))
           (kill-buffer buf)
           (funcall callback
                    (and (eq (process-status proc) 'exit)
                         (zerop (process-exit-status proc)))
                    output)))))))

(provide 'mayhem-core)
;;; mayhem-core.el ends here
