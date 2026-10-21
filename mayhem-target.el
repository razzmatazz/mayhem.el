;;; mayhem-target.el --- Target page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A target's page, `*mayhem: owner/project/target*', its type, code
;; or API, in its heading: its details; its
;; latest run's crashes, coverage, hardening, repository and image; and a chart of its active defects over time, as the web
;; app's target page has.  Below, its latest runs, and its most severe
;; defects, with the latest run's active ones tallied by severity, a
;; few of each; `[Show all 78 runs]' opens a page of every one.  RET on a
;; defect or run opens its page.

;;; Code:

(require 'vui)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)

(mayhem-sync-define-resource target (owner project target)
  :fetch (lambda (done) (mayhem--fetch-target owner project target done)))

(define-derived-mode mayhem-target-mode mayhem-page-mode "Mayhem Target"
  "Major mode for a Mayhem target's page.")

(declare-function mayhem-run-open "mayhem-run" (owner project target number))
(declare-function mayhem-testsuite-open "mayhem-testsuite" (owner project target run))
(declare-function mayhem-defect-open "mayhem-defect" (owner project target number &optional run))

(defconst mayhem-target--run-header
  '("Run" "Status" "Cov" "Defects" nil "Pass" "Branch" "Age")
  "The names of the columns of `mayhem-target--run-cells'.")

(defun mayhem-target--run-cells (run now)
  "Return the cells of RUN's line, an alist, as of NOW, for `mayhem-columns'."
  (let ((all (or (alist-get 'n_testcase_reports run) 0))
        (lines (alist-get 'n_lines_total run)))
    (list (format "#%s" (or (alist-get 'run_number run) "?"))
          (mayhem-run-status run)
          (if (and lines (> lines 0))
              (propertize (format "%d%%" (round (* 100.0 (or (alist-get 'n_lines_covered run) 0))
                                                lines))
                          'help-echo "Line coverage")
            "")
          (format "%d" (or (alist-get 'n_defects run) 0))
          (or (mayhem-severity-counts run) "")
          (propertize (format "%d/%d" (- all (or (alist-get 'n_crash_reports run) 0)) all)
                      'face 'mayhem-label 'help-echo "Passing tests of all")
          (propertize (or (alist-get 'branch_name run) (alist-get 'started_by run) "")
                      'face 'mayhem-label)
          (propertize (or (mayhem--format-age (alist-get 'created_at run) now) "")
                      'face 'mayhem-label))))

(defconst mayhem-target--defect-header
  '("Id" "Severity" nil "Title" "CWE" "State" "Seen" "Age")
  "The names of the columns of `mayhem-target--defect-cells'.")

(defconst mayhem-target--title-width 50
  "Most columns a defect's title takes in a list; longer ones are cut.")

(defun mayhem-target--defect-cells (defect id now)
  "Return the cells of DEFECT's line, an alist, as of NOW, for `mayhem-columns'.
ID is its number, as \"!N\"."
  (let ((level (or (alist-get 'severity_level defect) ""))
        (title (or (alist-get 'title defect) "")))
    (list id
          (propertize level 'face (mayhem-defect-severity-face level))
          (propertize (format "%s" (or (alist-get 'severity defect) "")) 'face 'mayhem-label)
          (propertize (truncate-string-to-width title mayhem-target--title-width nil nil "…")
                      'help-echo title)
          (propertize (if-let* ((cwe (alist-get 'cwe_number defect))) (format "CWE-%s" cwe) "")
                      'face 'mayhem-label)
          (propertize (let ((state (alist-get 'state defect)))
                        (if (and state (not (equal state "open"))) state ""))
                      'face 'mayhem-label)
          (propertize (if-let* ((run (alist-get 'last_seen_run_number defect)))
                          (format "run #%s" run)
                        "")
                      'face 'mayhem-label)
          (propertize (or (mayhem--format-age (alist-get 'last_seen defect) now) "")
                      'face 'mayhem-label))))

;; Each list shows its first few rows; the full one is a page of its own.
(defun mayhem-target--rows (lines items open help-echo)
  "Return LINES, from `mayhem-columns' with a header, as a table of ITEMS.
The header is plain; each line after it is a RET-able row calling OPEN
with its item.  HELP-ECHO is the rows'."
  (apply #'vui-fragment
         (vui-text (concat (car lines) "\n"))
         (seq-mapn (lambda (item line)
                     (mayhem-row (concat line "\n") (lambda () (funcall open item)) help-echo))
                   items (cdr lines))))

(defun mayhem-target--defect-rows (owner project target defects now)
  "Return a table of the defects of TARGET, as of NOW, a RET-able row each.
TARGET is of PROJECT of OWNER; DEFECTS are the ones shown, most severe
first."
  (mayhem-target--rows
   (mayhem-columns (seq-mapn (lambda (defect id) (mayhem-target--defect-cells defect id now))
                             defects (mayhem-defect-ids defects))
                   '(2) mayhem-target--defect-header)
   defects
   (lambda (defect)
     (mayhem-defect-open owner project target (alist-get 'defect_number defect)))
   "RET: open defect"))

(defun mayhem-target--run-rows (owner project target runs now)
  "Return a table with a RET-able row for each run of TARGET, as of NOW.
TARGET is of PROJECT of OWNER; RUNS are the ones shown, newest first."
  (mayhem-target--rows
   (mayhem-columns (mapcar (lambda (run) (mayhem-target--run-cells run now)) runs)
                   '(2 3 5) mayhem-target--run-header)
   runs
   (lambda (run) (mayhem-run-open owner project target (alist-get 'run_number run)))
   "RET: open run"))

(defun mayhem-target--show-more (shown count what on-click)
  "Return a button opening the full list, for one showing SHOWN of COUNT.
WHAT names the items, as in `[Show all 6 defects]'; ON-CLICK opens the
list.  Nil when it shows them all."
  (when (> count shown)
    (vui-fragment
     (vui-button (format "Show all %d %s" count what)
                 :help-echo (format "RET: open the list of every one of the %s" what)
                 :on-click on-click)
     (vui-newline))))

(defun mayhem-target--defect-tally (owner project target latest)
  "Return the line counting LATEST's active defects by severity, or nil.
LATEST is the latest run of TARGET of PROJECT of OWNER."
  (when latest
    (vui-fragment
     (vui-text (or (mayhem-severity-counts latest)
                   (propertize "none" 'face 'mayhem-label)))
     (vui-text " active in the latest " :face 'mayhem-label)
     (mayhem-run-link owner project target (alist-get 'run_number latest))
     (vui-newline)
     (vui-newline))))

(defun mayhem-target--render (owner project target data)
  "Return the vnodes of TARGET of PROJECT of OWNER's page, showing DATA."
  (let* ((info (alist-get 'target data))
         (latest (alist-get 'latest data))
         (runs (alist-get 'runs (alist-get 'runs data)))
         (count (or (alist-get 'count (alist-get 'runs data)) (length runs)))
         (defects (alist-get 'defects (alist-get 'defects data)))
         (n-defects (or (alist-get 'count (alist-get 'defects data)) (length defects)))
         (now (current-time)))
    (vui-fragment
     (when (alist-get 'url info)
       (mayhem-field "URL" (alist-get 'url info)))
     (mayhem-field "Updated" (mayhem--format-age (alist-get 'updated_at info) now))
     ;; The fields below come from the latest run; a target has none of
     ;; its own, and each run may have its own image and repository.
     (when latest
       (vui-fragment
        (mayhem-field "Crashes" (format "%d" (or (alist-get 'n_crash_reports latest) 0)))
        (let ((covered (alist-get 'n_lines_covered latest))
              (total (alist-get 'n_lines_total latest)))
          (when (and covered total (> total 0))
            (mayhem-field "Coverage" (format "%.2f%% of lines" (/ (* 100.0 covered) total)))))
        (mayhem-hardening-field latest)
        (mayhem-repo-field (alist-get 'scm_remote_origin latest))
        (mayhem-image-field latest)
        (when-let* ((suite (alist-get 'n_optimized_set_testcases latest)))
          (mayhem-field "Test suite"
                        (mayhem-page-link (format "%d test case%s" suite (if (= suite 1) "" "s"))
                                          "RET: open test suite"
                                          (lambda ()
                                            (mayhem-testsuite-open owner project target
                                                                   (alist-get 'run_number
                                                                              latest))))))))
     (vui-newline)
     (mayhem-trend-view owner project target)
     (if runs
         (mayhem-target--run-rows owner project target runs now)
       (mayhem-notice "No runs"))
     (mayhem-target--show-more (length runs) count "runs"
                               (lambda () (mayhem-target-runs-open owner project target)))
     (vui-newline)
     (mayhem-heading (format "Defects (%d)" n-defects))
     (mayhem-target--defect-tally owner project target latest)
     (if defects
         (mayhem-target--defect-rows owner project target defects now)
       (mayhem-notice "No defects"))
     (mayhem-target--show-more (length defects) n-defects "defects"
                               (lambda () (mayhem-target-defects-open owner project target))))))

(defun mayhem-target--skeleton ()
  "Return grey bars shaped like a target's page, shown until its data lands."
  (vui-fragment
   (mayhem-field "Updated" (mayhem-skeleton-bar 12))
   (mayhem-field "Crashes" (mayhem-skeleton-bar 3))
   (vui-newline)
   (mayhem-trend-skeleton)
   (mayhem-skeleton (make-list 5 '(4 "  " 9 "  " 3 "  " 9 "  " 9 "  " 12)))
   (vui-newline)
   (mayhem-heading "Defects")
   (mayhem-skeleton (make-list 5 '(6 " " 10 " " 30 "  " 12)))))

(vui-defcomponent mayhem-target-page (owner project target)
  "The page of TARGET of PROJECT of OWNER."
  :render
  (let ((snapshot (mayhem-sync-use-resource (list 'target owner project target))))
    (vui-fragment
     (mayhem-page-heading (mayhem-target-kind (alist-get 'type (alist-get 'target
                                                                          (plist-get snapshot :data))))
                          owner project target)
     (vui-newline)
     (mayhem-snapshot-view snapshot "target" (mayhem-target--skeleton)
                           (lambda (data) (mayhem-target--render owner project target data))))))

(defun mayhem-target-open (owner project target)
  "Open the page of TARGET of PROJECT of OWNER."
  (mayhem-open-page (format "*mayhem: %s/%s/%s*" owner project target)
                    #'mayhem-target-mode
                    (lambda () (vui-component 'mayhem-target-page
                                              :owner owner :project project
                                              :target target))
                    (list 'target owner project target)))

;;;; Every defect or run

(mayhem-sync-define-resource target-defects (owner project target)
  :fetch (lambda (done) (mayhem--fetch-target-defects owner project target done)))

(mayhem-sync-define-resource target-runs (owner project target)
  :fetch (lambda (done) (mayhem--fetch-target-runs owner project target done)))

(define-derived-mode mayhem-target-defects-mode mayhem-page-mode "Mayhem Defects"
  "Major mode for the page of every defect of a Mayhem target."
  (setq-local mayhem-list-facets
              `(("Severity" . ,(lambda (d) (alist-get 'severity_level d)))
                ("CWE" . ,(lambda (d) (when-let* ((cwe (alist-get 'cwe_number d)))
                                        (format "CWE-%s" cwe))))
                ("State" . ,(lambda (d) (alist-get 'state d))))))

(define-derived-mode mayhem-target-runs-mode mayhem-page-mode "Mayhem Runs"
  "Major mode for the page of every run of a Mayhem target."
  (setq-local mayhem-list-facets
              `(("Status" . ,#'mayhem--run-status)
                ("Branch" . ,(lambda (r) (alist-get 'branch_name r))))))

(vui-defcomponent mayhem-target-defects-page (owner project target)
  "The page of every defect of TARGET of PROJECT of OWNER, most severe first."
  :render
  (let ((snapshot (mayhem-sync-use-resource (list 'target-defects owner project target))))
    (vui-fragment
     (mayhem-target-page-heading "defects" owner project target)
     (vui-newline)
     (mayhem-snapshot-view
      snapshot "defects"
      (vui-fragment
       (mayhem-skeleton (make-list 8 '(6 " " 10 " " 30 "  " 12))))
      (lambda (defects)
        (let ((shown (mayhem-list-filtered defects)))
          (vui-fragment
           (mayhem-tally defects (lambda (d) (alist-get 'severity_level d))
                         mayhem-severities #'mayhem-defect-severity-face)
           (when defects
             (vui-fragment (vui-newline) (mayhem-list-filter-bar defects shown)))
           (vui-newline)
           (cond (shown (mayhem-target--defect-rows owner project target shown (current-time)))
                 (defects (mayhem-notice "No defects match the filter"))
                 (t (mayhem-notice "No defects"))))))))))

(vui-defcomponent mayhem-target-runs-page (owner project target)
  "The page of every run of TARGET of PROJECT of OWNER, newest first."
  :render
  (let ((snapshot (mayhem-sync-use-resource (list 'target-runs owner project target))))
    (vui-fragment
     (mayhem-target-page-heading "runs" owner project target)
     (vui-newline)
     (mayhem-snapshot-view
      snapshot "runs"
      (vui-fragment
       (mayhem-skeleton (make-list 8 '(4 "  " 9 "  " 3 "  " 9 "  " 9 "  " 12))))
      (lambda (runs)
        (let ((shown (mayhem-list-filtered runs)))
          (vui-fragment
           (mayhem-tally runs #'mayhem--run-status
                         '("running" "pending" "completed" "stopped" "failed")
                         #'mayhem-run-status-face)
           (when runs
             (vui-fragment (vui-newline) (mayhem-list-filter-bar runs shown)))
           (vui-newline)
           (cond (shown (mayhem-target--run-rows owner project target shown (current-time)))
                 (runs (mayhem-notice "No runs match the filter"))
                 (t (mayhem-notice "No runs"))))))))))

(defun mayhem-target-defects-open (owner project target)
  "Open the page of every defect of TARGET of PROJECT of OWNER."
  (mayhem-open-page (format "*mayhem: %s/%s/%s/defects*" owner project target)
                    #'mayhem-target-defects-mode
                    (lambda () (vui-component 'mayhem-target-defects-page
                                              :owner owner :project project
                                              :target target))
                    (list 'target-defects owner project target)))

(defun mayhem-target-runs-open (owner project target)
  "Open the page of every run of TARGET of PROJECT of OWNER."
  (mayhem-open-page (format "*mayhem: %s/%s/%s/runs*" owner project target)
                    #'mayhem-target-runs-mode
                    (lambda () (vui-component 'mayhem-target-runs-page
                                              :owner owner :project project
                                              :target target))
                    (list 'target-runs owner project target)))

(provide 'mayhem-target)
;;; mayhem-target.el ends here
