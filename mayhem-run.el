;;; mayhem-run.el --- Run page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A run's page, `*mayhem: owner/project/target/N*': its status, commit
;; and counts, its defects, and, for an API run, its endpoints.  RET on
;; a defect opens its page.

;;; Code:

(require 'vui)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)
(require 'mayhem-defect)

(mayhem-sync-define-resource run (owner project target number)
  :fetch (lambda (done) (mayhem--fetch-run owner project target number done)))

(define-derived-mode mayhem-run-mode mayhem-page-mode "Mayhem Run"
  "Major mode for a Mayhem run's page.")

(defun mayhem-run--defects (owner project target run defects)
  "Return the vnodes listing DEFECTS of RUN of TARGET of PROJECT of OWNER."
  (vui-fragment
   (mayhem-heading (format "Defects (%d)" (length defects)))
   (if (null defects)
       (mayhem-notice "No defects")
     (apply #'vui-fragment
            (mapcar (lambda (defect)
                      (let ((level (or (alist-get 'severity_level defect) ""))
                            (number (alist-get 'defect_number defect)))
                        (mayhem-row
                         (concat "  "
                                 (propertize (format "%-7s" level)
                                             'face (mayhem-defect-severity-face level))
                                 " "
                                 (or (alist-get 'title defect) "")
                                 (propertize (format "  #%s" number) 'face 'mayhem-label)
                                 "\n")
                         (lambda () (mayhem-defect-open owner project target number run))
                         "RET: open defect")))
                    defects)))))

(defun mayhem-run--endpoints (endpoints)
  "Return the vnodes listing ENDPOINTS of an API run."
  (vui-fragment
   (vui-newline)
   (mayhem-heading (format "Endpoints (%d)" (length endpoints)))
   (apply #'vui-fragment
          (mapcar (lambda (endpoint)
                    (let ((passing (alist-get 'passing endpoint))
                          (n (or (alist-get 'defects_total endpoint) 0)))
                      (vui-text
                       (concat "  "
                               (format "%-7s" (or (alist-get 'method endpoint) ""))
                               (format "%-40s" (or (alist-get 'path endpoint) ""))
                               (propertize (if passing "passing" "failing")
                                           'face (if passing 'success 'error))
                               (propertize (format "  %d defect%s" n (if (= n 1) "" "s"))
                                           'face 'mayhem-label)
                               (if (alist-get 'covered endpoint) ""
                                 (propertize "  not covered" 'face 'mayhem-label))
                               "\n"))))
                  endpoints))))

(defun mayhem-run--render (owner project target number data)
  "Return the vnodes of run NUMBER of TARGET of PROJECT of OWNER, showing DATA."
  (let* ((run (alist-get 'run data))
         (revision (alist-get 'revision run))
         (now (current-time)))
    (vui-fragment
     (mayhem-field "Status" (concat (mayhem--run-status run)
                                    (when-let* ((d (alist-get 'description run)))
                                      (propertize (concat "  " d) 'face 'mayhem-label))))
     (mayhem-field "Started" (concat (or (mayhem--format-age (alist-get 'started_at run) now)
                                         "not yet")
                                     (when-let* ((by (alist-get 'started_by run)))
                                       (propertize (concat "  by " by) 'face 'mayhem-label))))
     (mayhem-field "Duration" (mayhem--format-duration (alist-get 'duration run)))
     (mayhem-field "Branch" (alist-get 'branch_name run))
     (when revision
       (mayhem-field "Commit" (concat (substring revision 0 (min 7 (length revision)))
                                      (when-let* ((s (alist-get 'scm_commit_subject run)))
                                        (concat "  " s)))))
     (unless (alist-get 'api_run run)
       (mayhem-field "Tests" (format "%s run, %s edges covered"
                                     (or (alist-get 'tests_run run) 0)
                                     (or (alist-get 'edges_covered run) 0))))
     (vui-newline)
     (mayhem-run--defects owner project target number (alist-get 'defects data))
     (when (alist-get 'api_run run)
       (mayhem-run--endpoints (alist-get 'endpoints data))))))

(defun mayhem-run--skeleton ()
  "Return grey bars shaped like a run's page, shown until its data lands."
  (vui-fragment
   (mayhem-field "Status" (mayhem-skeleton-bar 22))
   (mayhem-field "Started" (mayhem-skeleton-bar 20))
   (mayhem-field "Duration" (mayhem-skeleton-bar 6))
   (mayhem-field "Branch" (mayhem-skeleton-bar 8))
   (mayhem-field "Commit" (mayhem-skeleton-bar 30))
   (vui-newline)
   (mayhem-heading "Defects")
   (mayhem-skeleton '(("  " 6 " " 28) ("  " 6 " " 36) ("  " 6 " " 22) ("  " 6 " " 30)))))

(vui-defcomponent mayhem-run-page (owner project target number)
  "The page of run NUMBER of TARGET of PROJECT of OWNER."
  :render
  (let ((snapshot (mayhem-sync-use-resource (list 'run owner project target number))))
    (vui-fragment
     (mayhem-heading (concat (propertize (concat owner "/" project) 'face 'mayhem-project)
                             "/"
                             (propertize target 'face 'mayhem-target)
                             (format " #%s" number)))
     (vui-newline)
     (mayhem-snapshot-view snapshot "run" (mayhem-run--skeleton)
                           (lambda (data)
                             (mayhem-run--render owner project target number data))))))

(defun mayhem-run-open (owner project target number)
  "Open the page of run NUMBER of TARGET of PROJECT of OWNER."
  (mayhem-open-page (format "*mayhem: %s/%s/%s/%s*" owner project target number)
                    #'mayhem-run-mode
                    (lambda () (vui-component 'mayhem-run-page
                                              :owner owner :project project
                                              :target target :number number))))

(provide 'mayhem-run)
;;; mayhem-run.el ends here
