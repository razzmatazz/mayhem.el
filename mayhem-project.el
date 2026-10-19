;;; mayhem-project.el --- Project page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A project's page, `*mayhem: owner/project*': its details and its
;; targets.  RET on a target opens its page.

;;; Code:

(require 'vui)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)

(declare-function mayhem-target-open "mayhem-target" (owner project target))

(mayhem-sync-define-resource project (owner project)
  :fetch (lambda (done) (mayhem--fetch-project owner project done)))

(define-derived-mode mayhem-project-mode mayhem-page-mode "Mayhem Project"
  "Major mode for a Mayhem project's page.")

(defun mayhem-project--target-row (owner project target now)
  "Return the row of TARGET, an alist, on PROJECT of OWNER's page at NOW."
  (let* ((slug (alist-get 'slug target))
         (run (alist-get 'latest_active_run target))
         (line (concat "  "
                       (propertize (format "%-30s" (or (alist-get 'target_name target) slug))
                                   'face 'mayhem-target)
                       " "
                       (propertize (format "%-5s" (or (alist-get 'type target) ""))
                                   'face 'mayhem-label)
                       (format " %5d runs" (or (alist-get 'n_runs target) 0))
                       (if run
                           (concat "  " (mayhem--run-status run) " "
                                   (propertize (or (mayhem--format-age
                                                    (alist-get 'created_at run) now)
                                                   "")
                                               'face 'mayhem-label))
                         "")
                       "\n")))
    (mayhem-row line (lambda () (mayhem-target-open owner project slug))
                "RET: open target")))

(defun mayhem-project--render (owner project data)
  "Return the vnodes of PROJECT of OWNER's page, showing DATA."
  (let* ((info (alist-get 'project data))
         (targets (alist-get 'targets data))
         (now (current-time)))
    (vui-fragment
     (mayhem-field "Branch" (alist-get 'default_branch info))
     (when (alist-get 'repository_url info)
       (mayhem-field "Repo" (alist-get 'repository_url info)))
     (mayhem-field "Defects"
                   (format "%d high, %d medium, %d low"
                           (or (alist-get 'n_defects_active_high info) 0)
                           (or (alist-get 'n_defects_active_medium info) 0)
                           (or (alist-get 'n_defects_active_low info) 0)))
     (mayhem-field "Updated" (mayhem--format-age (alist-get 'updated_at info) now))
     (vui-newline)
     (mayhem-heading (format "Targets (%d)" (length targets)))
     (if targets
         (apply #'vui-fragment
                (mapcar (lambda (target)
                          (mayhem-project--target-row owner project target now))
                        targets))
       (mayhem-notice "No targets")))))

(defun mayhem-project--skeleton ()
  "Return grey bars shaped like a project's page, shown until its data lands."
  (vui-fragment
   (mayhem-field "Branch" (mayhem-skeleton-bar 8))
   (mayhem-field "Defects" (mayhem-skeleton-bar 26))
   (mayhem-field "Updated" (mayhem-skeleton-bar 12))
   (vui-newline)
   (mayhem-heading "Targets")
   (mayhem-skeleton '(("  " 30 " " 5 "  " 9 "  " 20)
                      ("  " 24 "       " 5 "  " 9 "  " 18)
                      ("  " 28 "   " 5 "  " 9 "  " 22)))))

(vui-defcomponent mayhem-project-page (owner project)
  "The page of PROJECT of OWNER."
  :render
  (let ((snapshot (mayhem-sync-use-resource (list 'project owner project))))
    (vui-fragment
     (mayhem-heading (propertize (concat owner "/" project) 'face 'mayhem-project))
     (vui-newline)
     (mayhem-snapshot-view snapshot "project" (mayhem-project--skeleton)
                           (lambda (data) (mayhem-project--render owner project data))))))

(defun mayhem-project-open (owner project)
  "Open the page of PROJECT of OWNER."
  (mayhem-open-page (format "*mayhem: %s/%s*" owner project)
                    #'mayhem-project-mode
                    (lambda () (vui-component 'mayhem-project-page
                                              :owner owner :project project))
                    (list 'project owner project)))

(provide 'mayhem-project)
;;; mayhem-project.el ends here
