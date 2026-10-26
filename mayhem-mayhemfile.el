;;; mayhem-mayhemfile.el --- Major mode for Mayhemfiles  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; `mayhem-mayhemfile-mode', for files named `Mayhemfile' or
;; `*.Mayhemfile' and for the Mayhemfile a run page shows.  A
;; Mayhemfile is YAML, so the mode derives from whichever YAML mode the
;; user has (`yaml-ts-mode' if only its grammar is there, else
;; `prog-mode'); `mayhem-mayhemfile-mode-hook' is for Mayhemfile-only
;; settings.
;;
;; A Mayhemfile visited from disk is checked with Flymake, by `mayhem
;; validate --no-docker' (`mayhem-mayhemfile-validate-command'): the API
;; has no validation endpoint, and the CLI checks it against Mayhem's
;; own schema (keys, types, task names, versions, file versus network
;; input), pointing at the line and column of each error.  It reports
;; one error at a time, and needs `mayhem login'.  Flymake from Emacs
;; 30 on runs it only on files under `trusted-content', as the CLI
;; may fetch what a Mayhemfile names.  The format is
;; documented at https://app.mayhem.security/docs/code-testing/reference/mayhemfile/.

;;; Code:

(require 'flymake)

(defcustom mayhem-mayhemfile-validate-command '("mayhem" "validate" "--no-docker")
  "Command checking a Mayhemfile, given `-f FILE DIRECTORY' after it.
Nil turns off checking Mayhemfiles with Flymake."
  :type '(choice (const :tag "Off" nil) (repeat string))
  :group 'mayhem)

(defun mayhem--yaml-mode ()
  "Return the major mode the user gives YAML files, or nil."
  (let ((mode (assoc-default "x.yaml" auto-mode-alist #'string-match)))
    (when (consp mode) (setq mode (car mode)))
    (setq mode (alist-get mode major-mode-remap-alist mode))
    (cond ((functionp mode) mode)
          ((and (fboundp 'yaml-ts-mode) (fboundp 'treesit-language-available-p)
                (treesit-language-available-p 'yaml))
           #'yaml-ts-mode))))

(defun mayhem--mayhemfile-parent-mode ()
  "Turn on the user's YAML mode, or `prog-mode' without one."
  (funcall (or (mayhem--yaml-mode) #'prog-mode)))

;;;###autoload
(define-derived-mode mayhem-mayhemfile-mode mayhem--mayhemfile-parent-mode "Mayhemfile"
  "Major mode for Mayhemfiles, Mayhem's YAML run configuration.
A Mayhemfile visited from disk is checked with Flymake; see
`mayhem-mayhemfile-validate-command'."
  (add-hook 'flymake-diagnostic-functions #'mayhem-mayhemfile-flymake nil t)
  (when (and buffer-file-name mayhem-mayhemfile-validate-command
             (executable-find (car mayhem-mayhemfile-validate-command)))
    (flymake-mode 1)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\(?:/\\|\\.\\)Mayhemfile\\'" . mayhem-mayhemfile-mode))

;;;; Validation

(defconst mayhem-mayhemfile--boilerplate
  (concat "\\`\\(?:Error: \\)?\\(?:Mayhemfile contains errors\\|Source Mayhemfile \\|"
          "Invalid configuration\\|Error materializing default\\|-->\\|\\'\\)")
  "Matches the CLI's ERROR lines that only frame the errors it located.")

(defun mayhem-mayhemfile--split-unexpected (message)
  "Split MESSAGE into one message per key it names as unexpected.
The CLI names them all in one, which then marks no key."
  (if (string-match "\\`\\(.*(\\)\\('.+'\\) were unexpected)\\'" message)
      (let ((head (match-string 1 message)))
        (mapcar (lambda (key) (concat head key " was unexpected)"))
                (split-string (match-string 2 message) ", ")))
    (list message)))

(defun mayhem-mayhemfile--parse-validate (output)
  "Return the errors in OUTPUT, of `mayhem-mayhemfile-validate-command'.
Each is (LINE COLUMN END-COLUMN MESSAGE), LINE from 1 and the
columns from 0.  An error the CLI did not place has nil LINE and
COLUMN; one placed without its extent has nil END-COLUMN.  Placed
errors leave out the unplaced ones, which only head them."
  (let (placed unplaced line pending)
    (dolist (text (split-string output "\n"))
      (cond
       ;; A line of the Mayhemfile, quoted with its number...
       ((string-match "\\`ERROR \\([0-9]+\\) | " text)
        (setq line (string-to-number (match-string 1 text))))
       ;; ...then carets under the error, and what it is.
       ((string-match "\\`ERROR +| \\( *\\)\\(\\^+\\) ?\\(.*\\)" text)
        (let ((col (length (match-string 1 text))))
          (when (and line (not (string-empty-p (match-string 3 text))))
            (push (list line col (+ col (length (match-string 2 text)))
                        (match-string 3 text))
                  placed))))
       ;; A YAML syntax error, as PyYAML words it.
       ((string-match "\\`  in \"<unicode string>\", line \\([0-9]+\\), column \\([0-9]+\\):" text)
        (push (list (string-to-number (match-string 1 text))
                    (1- (string-to-number (match-string 2 text)))
                    nil (or pending "YAML syntax error"))
              placed))
       ((string-match "\\`ERROR \\(?:Error: \\)?\\(?:YAML parsing error: \\)?\\(.*\\)" text)
        (let ((message (string-trim (match-string 1 text))))
          (setq pending message)
          (unless (string-match-p mayhem-mayhemfile--boilerplate message)
            (dolist (one (mayhem-mayhemfile--split-unexpected message))
              (push (list nil nil nil one) unplaced)))))
       ((not (string-match-p "\\`\\(?:WARNING\\|Suggestion\\| \\)" text))
        (setq pending (string-trim text)))))
    (delete-dups (nreverse (or placed unplaced)))))

(defun mayhem-mayhemfile--region (line col end-col message)
  "Return (BEG . END) in the current buffer of an error at LINE and COL.
END-COL is where it ends on LINE, or nil.  Without a LINE, it is the
key MESSAGE says was unexpected, else the first line."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (cond
       (line
        (forward-line (1- line))
        (let ((eol (line-end-position)))
          (if end-col
              (let ((end (min eol (+ (point) (max end-col (1+ col))))))
                (forward-char (min col (- eol (point))))
                ;; The CLI underlines an unexpected key with its indent.
                (skip-chars-forward " \t" end)
                (cons (point) end))
            (forward-char (min col (- eol (point))))
            (if (looking-at "[^ \t\n]+")
                (cons (point) (match-end 0))
              (cons (line-beginning-position) eol)))))
       ((and (string-match "'\\([^']+\\)' was unexpected" message)
             (re-search-forward (concat "^[ \t]*\\(?:- \\)?\\("
                                        (regexp-quote (match-string 1 message))
                                        "\\)[ \t]*:")
                                nil t))
        (cons (match-beginning 1) (match-end 1)))
       (t (cons (point-min) (line-end-position)))))))

(defvar-local mayhem-mayhemfile--process nil
  "The check of the buffer's Mayhemfile under way, if any.")

(defun mayhem-mayhemfile-flymake (report-fn &rest _)
  "Check the buffer's Mayhemfile for Flymake, calling REPORT-FN.
See `mayhem-mayhemfile-validate-command'."
  (unless (and mayhem-mayhemfile-validate-command
               (executable-find (car mayhem-mayhemfile-validate-command)))
    (error "Cannot find %s" (car mayhem-mayhemfile-validate-command)))
  (when (process-live-p mayhem-mayhemfile--process)
    (kill-process mayhem-mayhemfile--process))
  (let* ((source (current-buffer))
         (file (make-temp-file "mayhem-Mayhemfile"))
         ;; Testsuite paths are relative to the Mayhemfile's package.
         (dir (if buffer-file-name
                  (file-name-directory buffer-file-name)
                temporary-file-directory)))
    (save-restriction
      (widen)
      (write-region nil nil file nil 'silent))
    (setq mayhem-mayhemfile--process
          (make-process
           :name "mayhem-mayhemfile-flymake"
           :noquery t
           :connection-type 'pipe
           :buffer (generate-new-buffer " *mayhem-mayhemfile-flymake*")
           :command (append mayhem-mayhemfile-validate-command
                            (list "-f" file (directory-file-name (expand-file-name dir))))
           :sentinel
           (lambda (proc _event)
             (unless (process-live-p proc)
               (unwind-protect
                   (if (not (and (buffer-live-p source)
                                 (eq proc (buffer-local-value 'mayhem-mayhemfile--process source))))
                       (flymake-log :debug "Canceling obsolete check %s" proc)
                     (let ((output (with-current-buffer (process-buffer proc) (buffer-string))))
                       (with-current-buffer source
                         (funcall report-fn
                                  (and (/= 0 (process-exit-status proc))
                                       (mapcar
                                        (pcase-lambda (`(,line ,col ,end-col ,message))
                                          (let ((region (mayhem-mayhemfile--region
                                                         line col end-col message)))
                                            (flymake-make-diagnostic source (car region) (cdr region)
                                                                     :error message)))
                                        (or (mayhem-mayhemfile--parse-validate output)
                                            (list (list nil nil nil
                                                          (string-trim
                                                           (replace-regexp-in-string
                                                            "^WARNING .*\n" "" output)))))))))))
                 (kill-buffer (process-buffer proc))
                 (delete-file file))))))))

(provide 'mayhem-mayhemfile)

;;; mayhem-mayhemfile.el ends here
