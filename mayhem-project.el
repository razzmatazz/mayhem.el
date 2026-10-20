;;; mayhem-project.el --- Project page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A project's page, `*mayhem: owner/project*': its details, its
;; remaining and fixed defects, a chart of them over time, as the web
;; app's project page has, and, in tabs, its active and archived targets
;; with what their latest run found.  RET on a target opens its page.

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
         (run (alist-get 'latest target))
         (lines (alist-get 'n_lines_total run))
         (all (or (alist-get 'n_testcase_reports run) 0))
         (factors (alist-get 'n_exploitability_factors_total run))
         (line (concat "  "
                       (propertize (format "%-5s" (or (alist-get 'type target) ""))
                                   'face 'mayhem-label)
                       (propertize (format "%-30s" (or (alist-get 'target_name target) slug))
                                   'face 'mayhem-target)
                       (if (not run)
                           (propertize (format " %5d runs" (or (alist-get 'n_runs target) 0))
                                       'face 'mayhem-label)
                         (concat
                          (propertize (if (and lines (> lines 0))
                                          (format "%5d%%"
                                                  (round (* 100.0 (or (alist-get 'n_lines_covered run) 0))
                                                         lines))
                                        "      ")
                                      'help-echo "Line coverage")
                          (format " %4d defects" (or (alist-get 'n_defects run) 0))
                          (propertize (if (and factors (> factors 0))
                                          (format "  %d/%d" (or (alist-get 'n_exploitability_factors_passing
                                                                           run)
                                                                0)
                                                  factors)
                                        "     ")
                                      'face 'mayhem-label 'help-echo "Exploitability factors")
                          (propertize (format "  %4d/%-4d tests"
                                              (- all (or (alist-get 'n_crash_reports run) 0)) all)
                                      'face 'mayhem-label 'help-echo "Passing tests of all")
                          "  "
                          (propertize (or (mayhem--format-age (alist-get 'created_at run) now) "")
                                      'face 'mayhem-label)
                          (when-let* ((counts (mayhem-severity-counts run)))
                            (concat "  " counts))))
                       "\n")))
    (mayhem-row line (lambda () (mayhem-target-open owner project slug))
                "RET: open target")))

(defun mayhem-project--defects (info kind)
  "Return INFO's defects of KIND, \"active\" or \"fixed\", as \"9  3 high, 6 medium\"."
  (let ((total (apply #'+ (mapcar (lambda (level)
                                    (or (alist-get (intern (format "n_defects_%s_%s" kind level))
                                                   info)
                                        0))
                                  mayhem-severities))))
    (concat (format "%d" total)
            (when-let* ((counts (mayhem-severity-counts info kind)))
              (concat "  " counts)))))

(defun mayhem-project--render (owner project data tab on-tab)
  "Return the vnodes of PROJECT of OWNER's page, showing DATA.
TAB is the key of the tab shown, `active' or `archived', the first when
nil; ON-TAB is called with the other's key, to show it."
  (let* ((info (alist-get 'project data))
         (totals (alist-get 'totals data))
         (targets (alist-get 'targets data))
         (archived (seq-filter (lambda (target) (alist-get 'is_archived target)) targets))
         (active (seq-remove (lambda (target) (alist-get 'is_archived target)) targets))
         (tabs `((active ,(format "Targets (%d)" (length active)) ,active)
                 (archived ,(format "Archived (%d)" (length archived)) ,archived)))
         (shown (or (assq tab tabs) (car tabs)))
         (now (current-time)))
    (vui-fragment
     (mayhem-repo-field (alist-get 'repository_url info))
     (let ((branch (alist-get 'default_branch info)))
       (mayhem-field "Branch" (and branch
                                   (mayhem-repo-link (mayhem--repo
                                                      (alist-get 'repository_url info))
                                                     branch 'branch branch))))
     (mayhem-field "Defects" (concat (mayhem-project--defects info "active")
                                     (propertize "  remaining" 'face 'mayhem-label)))
     (mayhem-field "Fixed" (mayhem-project--defects info "fixed"))
     (when-let* ((n (alist-get 'targets totals)))
       (mayhem-field "Passing" (format "%d of %d target%s passing their tests"
                                       (or (alist-get 'latest_targets_passing_tests totals) 0)
                                       n (if (= n 1) "" "s"))))
     (when-let* ((runs (alist-get 'runs totals)))
       (mayhem-field "Runs" (format "%d" runs)))
     (mayhem-field "Updated" (mayhem--format-age (alist-get 'updated_at info) now))
     (vui-newline)
     (vui-component 'mayhem-trend :owner owner :project project :target nil)
     (vui-newline)
     (mayhem-tab-row (mapcar (pcase-lambda (`(,key ,label ,_))
                               (list label (format "RET: show %s" (downcase label))
                                     (unless (eq key (car shown))
                                       (lambda () (funcall on-tab key)))))
                             tabs)
                     70)
     (vui-newline)
     (if (nth 2 shown)
         (apply #'vui-fragment
                (mapcar (lambda (target)
                          (mayhem-project--target-row owner project target now))
                        (nth 2 shown)))
       (mayhem-notice (if (eq (car shown) 'archived) "No archived targets" "No targets"))))))

(defun mayhem-project--skeleton ()
  "Return grey bars shaped like a project's page, shown until its data lands."
  (vui-fragment
   (mayhem-field "Branch" (mayhem-skeleton-bar 8))
   (mayhem-field "Defects" (mayhem-skeleton-bar 26))
   (mayhem-field "Fixed" (mayhem-skeleton-bar 20))
   (mayhem-field "Updated" (mayhem-skeleton-bar 12))
   (vui-newline)
   (mayhem-heading "Defect trend")
   (mayhem-skeleton (make-list mayhem-trend--height (list "       " mayhem-trend--width)))
   (vui-newline)
   (mayhem-skeleton '(("  " 30 " " 5 "  " 9 "  " 20)
                      ("  " 24 "       " 5 "  " 9 "  " 18)
                      ("  " 28 "   " 5 "  " 9 "  " 22)))))

(vui-defcomponent mayhem-project-page (owner project)
  "The page of PROJECT of OWNER."
  :state ((tab nil))
  :render
  (let ((snapshot (mayhem-sync-use-resource (list 'project owner project))))
    (vui-fragment
     (mayhem-heading (propertize (concat owner "/" project) 'face 'mayhem-project))
     (vui-newline)
     (mayhem-snapshot-view snapshot "project" (mayhem-project--skeleton)
                           (lambda (data)
                             (mayhem-project--render owner project data tab
                                                     (lambda (key) (vui-set-state :tab key))))))))

(defun mayhem-project-open (owner project)
  "Open the page of PROJECT of OWNER."
  (mayhem-open-page (format "*mayhem: %s/%s*" owner project)
                    #'mayhem-project-mode
                    (lambda () (vui-component 'mayhem-project-page
                                              :owner owner :project project))
                    (list 'project owner project)))

(provide 'mayhem-project)
;;; mayhem-project.el ends here
