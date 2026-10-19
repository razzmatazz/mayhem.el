;;; mayhem-target.el --- Target page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A target's page, `*mayhem: owner/project/target*': its details and
;; its latest runs.

;;; Code:

(require 'vui)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)

(mayhem-sync-define-resource target (owner project target)
  :fetch (lambda (done) (mayhem--fetch-target owner project target done)))

(define-derived-mode mayhem-target-mode mayhem-page-mode "Mayhem Target"
  "Major mode for a Mayhem target's page.")

(defun mayhem-target--run-line (run now)
  "Return the line of RUN, an alist, as of NOW."
  (concat "  "
          (format "#%-5s" (or (alist-get 'run_number run) "?"))
          (format " %-10s" (mayhem--run-status run))
          (format " %4d defects" (or (alist-get 'n_defects run) 0))
          "  "
          (propertize (format "%-12s" (or (alist-get 'branch_name run) ""))
                      'face 'mayhem-label)
          " "
          (propertize (or (mayhem--format-age (alist-get 'created_at run) now) "")
                      'face 'mayhem-label
                      'help-echo (alist-get 'created_at run))
          "\n"))

(defun mayhem-target--render (data)
  "Return the vnodes of a target's page, showing DATA."
  (let* ((info (alist-get 'target data))
         (runs (alist-get 'runs (alist-get 'runs data)))
         (count (or (alist-get 'count (alist-get 'runs data)) (length runs)))
         (now (current-time)))
    (vui-fragment
     (mayhem-field "Type" (alist-get 'type info))
     (when (alist-get 'url info)
       (mayhem-field "URL" (alist-get 'url info)))
     (mayhem-field "Updated" (mayhem--format-age (alist-get 'updated_at info) now))
     (vui-newline)
     (mayhem-heading (format "Runs (%d)" count))
     (if runs
         (apply #'vui-fragment
                (mapcar (lambda (run) (vui-text (mayhem-target--run-line run now)))
                        runs))
       (mayhem-notice "No runs"))
     (when (> count (length runs))
       (mayhem-notice (format "%d older runs not shown" (- count (length runs))))))))

(vui-defcomponent mayhem-target-page (owner project target)
  "The page of TARGET of PROJECT of OWNER."
  :render
  (let ((snapshot (mayhem-sync-use-resource (list 'target owner project target))))
    (vui-fragment
     (mayhem-heading (concat (propertize (concat owner "/" project) 'face 'mayhem-project)
                             "/"
                             (propertize target 'face 'mayhem-target)))
     (vui-newline)
     (mayhem-snapshot-view snapshot "target" #'mayhem-target--render))))

(defun mayhem-target-open (owner project target)
  "Open the page of TARGET of PROJECT of OWNER."
  (mayhem-open-page (format "*mayhem: %s/%s/%s*" owner project target)
                    #'mayhem-target-mode
                    (lambda () (vui-component 'mayhem-target-page
                                              :owner owner :project project
                                              :target target))))

(provide 'mayhem-target)
;;; mayhem-target.el ends here
