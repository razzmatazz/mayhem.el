;;; mayhem-target.el --- Target page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A target's page, `*mayhem: owner/project/target*': its details, what
;; its latest run found, and a chart of its active defects over time,
;; as the web app's target page has.  Below, in tabs: its most severe
;; defects and its latest runs.  RET on either opens its page.

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

(defun mayhem-target--run-line (run now)
  "Return the line of RUN, an alist, as of NOW."
  (let ((all (or (alist-get 'n_testcase_reports run) 0))
        (lines (alist-get 'n_lines_total run)))
    (concat (format "#%-5s" (or (alist-get 'run_number run) "?"))
            (format " %-10s" (mayhem--run-status run))
            (propertize (if (and lines (> lines 0))
                            (format "%4d%%" (round (* 100.0 (or (alist-get 'n_lines_covered run) 0))
                                                   lines))
                          "    ")
                        'help-echo "Line coverage")
            (format " %4d defects" (or (alist-get 'n_defects run) 0))
            (propertize (format "  %4d/%-4d tests" (- all (or (alist-get 'n_crash_reports run) 0)) all)
                        'face 'mayhem-label 'help-echo "Passing tests of all")
            "  "
            (propertize (format "%-12s" (or (alist-get 'branch_name run)
                                            (alist-get 'started_by run) ""))
                        'face 'mayhem-label)
            " "
            (propertize (or (mayhem--format-age (alist-get 'created_at run) now) "")
                        'face 'mayhem-label)
            (when-let* ((counts (mayhem-severity-counts run)))
              (concat "  " counts))
            "\n")))

(defun mayhem-target--defect-line (defect now)
  "Return the line of DEFECT, an alist, as of NOW, as `mayhem-line' parts."
  (let ((level (or (alist-get 'severity_level defect) ""))
        (title (or (alist-get 'title defect) "")))
    (list (propertize (format "%-7s" level) 'face (mayhem-defect-severity-face level))
          (propertize (format "%4s " (or (alist-get 'severity defect) "")) 'face 'mayhem-label)
          (mayhem-fit title (string-width title))
          (propertize (concat (when-let* ((cwe (alist-get 'cwe_number defect)))
                                (format "  CWE-%s" cwe))
                              (format "  defect #%s" (alist-get 'defect_number defect))
                              (unless (equal (alist-get 'state defect) "open")
                                (format "  %s" (alist-get 'state defect)))
                              (when-let* ((run (alist-get 'last_seen_run_number defect)))
                                (format "  run %s" run))
                              "  ")
                      'face 'mayhem-label)
          (propertize (or (mayhem--format-age (alist-get 'last_seen defect) now) "")
                      'face 'mayhem-label))))

(defun mayhem-target--render (owner project target data tab on-tab)
  "Return the vnodes of TARGET of PROJECT of OWNER's page, showing DATA.
TAB is the key of the tab shown, `defects' or `runs', the first when
nil; ON-TAB is called with the other's key, to show it."
  (let* ((info (alist-get 'target data))
         (latest (alist-get 'latest data))
         (runs (alist-get 'runs (alist-get 'runs data)))
         (count (or (alist-get 'count (alist-get 'runs data)) (length runs)))
         (defects (alist-get 'defects (alist-get 'defects data)))
         (n-defects (or (alist-get 'count (alist-get 'defects data)) (length defects)))
         (tabs `((defects ,(format "Defects (%d)" n-defects))
                 (runs ,(format "Runs (%d)" count))))
         (shown (car (or (assq tab tabs) (car tabs))))
         (now (current-time)))
    (vui-fragment
     (mayhem-field "Type" (alist-get 'type info))
     (when (alist-get 'url info)
       (mayhem-field "URL" (alist-get 'url info)))
     (mayhem-field "Updated" (mayhem--format-age (alist-get 'updated_at info) now))
     (when latest
       (vui-fragment
        (mayhem-field "Defects" (concat (format "%d" (or (alist-get 'n_defects latest) 0))
                                        (when-let* ((counts (mayhem-severity-counts latest)))
                                          (concat "  " counts))
                                        (propertize "  in " 'face 'mayhem-label))
                      (let ((number (alist-get 'run_number latest)))
                        (mayhem-run-link owner project target number)))
        (mayhem-field "Crashes" (format "%d" (or (alist-get 'n_crash_reports latest) 0)))
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
     (mayhem-tab-row (mapcar (pcase-lambda (`(,key ,label))
                               (list label (format "RET: show %s" (downcase label))
                                     (unless (eq key shown)
                                       (lambda () (funcall on-tab key)))))
                             tabs))
     (pcase shown
       ('defects
        (vui-fragment
         (if defects
             (apply #'vui-fragment
                    (mapcar (lambda (defect)
                              (mayhem-row (mayhem-target--defect-line defect now)
                                          (lambda ()
                                            (mayhem-defect-open owner project target
                                                                (alist-get 'defect_number defect)))
                                          "RET: open defect"))
                            defects))
           (mayhem-notice "No defects"))
         (when (> n-defects (length defects))
           (mayhem-notice (format "%d less severe defects not shown"
                                  (- n-defects (length defects)))))))
       ('runs
        (vui-fragment
         (if runs
             (apply #'vui-fragment
                    (mapcar (lambda (run)
                              (let ((number (alist-get 'run_number run)))
                                (mayhem-row (mayhem-target--run-line run now)
                                            (lambda () (mayhem-run-open owner project target number))
                                            "RET: open run")))
                            runs))
           (mayhem-notice "No runs"))
         (when (> count (length runs))
           (mayhem-notice (format "%d older runs not shown" (- count (length runs)))))))))))

(defun mayhem-target--skeleton ()
  "Return grey bars shaped like a target's page, shown until its data lands."
  (vui-fragment
   (mayhem-field "Type" (mayhem-skeleton-bar 4))
   (mayhem-field "Updated" (mayhem-skeleton-bar 12))
   (mayhem-field "Defects" (mayhem-skeleton-bar 20))
   (mayhem-field "Crashes" (mayhem-skeleton-bar 3))
   (vui-newline)
   (mayhem-trend-skeleton)
   (mayhem-skeleton (make-list 8 '(6 " " 10 " " 30 "  " 12)))))

(vui-defcomponent mayhem-target-page (owner project target)
  "The page of TARGET of PROJECT of OWNER."
  :state ((tab nil))
  :render
  (let ((snapshot (mayhem-sync-use-resource (list 'target owner project target))))
    (vui-fragment
     (mayhem-page-heading owner project target)
     (vui-newline)
     (mayhem-snapshot-view snapshot "target" (mayhem-target--skeleton)
                           (lambda (data)
                             (mayhem-target--render owner project target data tab
                                                    (lambda (key) (vui-set-state :tab key))))))))

(defun mayhem-target-open (owner project target)
  "Open the page of TARGET of PROJECT of OWNER."
  (mayhem-open-page (format "*mayhem: %s/%s/%s*" owner project target)
                    #'mayhem-target-mode
                    (lambda () (vui-component 'mayhem-target-page
                                              :owner owner :project project
                                              :target target))
                    (list 'target owner project target)))

(provide 'mayhem-target)
;;; mayhem-target.el ends here
