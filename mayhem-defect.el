;;; mayhem-defect.el --- Defect page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A defect's page, `*mayhem: owner/project/target/defect-N*': its
;; severity, CWE and description, and its evidence.  For an API defect
;; that is the server's stack trace and the request and response that
;; showed it; for a code defect, the crash, its backtrace and how to
;; reproduce it, and the test cases that hit it.

;;; Code:

(require 'subr-x)
(require 'vui)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)

(declare-function mayhem-testcase-open "mayhem-testcase" (owner project target run sha256))

(defconst mayhem-defect--fill-width 72
  "Column at which a defect's description is wrapped, at most.")

(mayhem-sync-define-resource defect (owner project target number run)
  :fetch (lambda (done) (mayhem--fetch-defect owner project target number run done))
  :max-age mayhem-sync-settled-for)

(define-derived-mode mayhem-defect-mode mayhem-page-mode "Mayhem Defect"
  "Major mode for a Mayhem defect's page.")

(defun mayhem-defect--evidence-fields (owner project target source evidence)
  "Return the fields of EVIDENCE of a defect from SOURCE, \"api\" or \"code\".
The defect is of TARGET of PROJECT of OWNER."
  (pcase source
    ("api"
     (when (alist-get 'path evidence)
       (mayhem-field "Endpoint" (concat (alist-get 'method evidence) " "
                                        (alist-get 'path evidence)
                                        (when-let* ((name (alist-get 'endpoint_name evidence)))
                                          (propertize (concat "  " name) 'face 'mayhem-label))))))
    ("code"
     (vui-fragment
      (mayhem-field "Crash" (string-join
                             (delq nil (list (alist-get 'crash_type evidence)
                                             (when-let* ((n (alist-get 'signal_number evidence)))
                                               (format "signal %s" n))))
                             ", "))
      (when-let* ((run (alist-get 'run_number evidence))
                  (sha (alist-get 'sha256 evidence)))
        (mayhem-field "Example" (mayhem-run-link owner project target run)
                      ", test case "
                      (mayhem-page-link (substring sha 0 (min 8 (length sha)))
                                        "RET: open test case"
                                        (lambda ()
                                          (mayhem-testcase-open owner project target run
                                                                sha)))))))))

(defconst mayhem-defect--testcases-shown 5
  "Most test cases a defect's page lists until asked for all of them.")

(defun mayhem-defect--testcases (owner project target evidence)
  "Return the table of the test cases in EVIDENCE of a code defect.
The defect is of TARGET of PROJECT of OWNER.  It lists the first
`mayhem-defect--testcases-shown', and a button the rest."
  (let* ((testcases (alist-get 'testcases evidence))
         (count (or (alist-get 'count evidence) 0))
         (lines (mayhem-columns
                 (mapcar (lambda (test)
                           (let ((sha (alist-get 'sha256 test)))
                             (list (substring sha 0 (min 8 (length sha)))
                                   (format "#%s" (alist-get 'run_number test))
                                   (propertize
                                    (format "%dms" (round (* 1000 (or (alist-get 'execution_time test)
                                                                       0))))
                                    'face 'mayhem-label))))
                         testcases)
                 '(2) '("Test case" "Run" "Time"))))
    (vui-fragment
     ;; The table's header names it; a heading would only repeat it.
     (vui-newline)
     (if (null testcases)
         (mayhem-notice "No test cases")
       (vui-fragment
        (vui-text (concat (car lines) "\n"))
        (vui-component
         'mayhem-unfold-list
         :limit mayhem-defect--testcases-shown :what "test cases"
         :rows (seq-mapn (lambda (test line)
                           (mayhem-row (concat line "\n")
                                       (lambda ()
                                         (mayhem-testcase-open owner project target
                                                               (alist-get 'run_number test)
                                                               (alist-get 'sha256 test)))
                                       "RET: open test case"))
                         testcases (cdr lines)))))
     (when (> count (length testcases))
       (mayhem-notice (format "%d more in the web app" (- count (length testcases))))))))

(defun mayhem-defect--evidence-blocks (source evidence)
  "Return the sections of EVIDENCE of a defect from SOURCE, trace last.
SOURCE is \"api\" or \"code\"."
  (pcase source
    ("api"
     (vui-fragment
      (mayhem-block "Request" (alist-get 'request evidence))
      (mayhem-block "Response" (alist-get 'response evidence))
      (mayhem-block "Stack trace" (alist-get 'stacktrace evidence))))
    ("code"
     (vui-fragment
      (mayhem-block "Reproduce"
                            (when-let* ((cmd (alist-get 'repro_cmdline evidence)))
                              (mayhem-command cmd)))
      (mayhem-block "Backtrace"
                            (if-let* ((frames (alist-get 'frames evidence)))
                                (mayhem-backtrace frames)
                              (alist-get 'backtrace evidence)))))))

(defun mayhem-defect--render (owner project target data)
  "Return the vnodes of a defect of TARGET of PROJECT of OWNER, showing DATA."
  (let* ((defect (alist-get 'defect data))
         (level (alist-get 'severity_level defect))
         (now (current-time)))
    (vui-fragment
     (mayhem-field "Title" (alist-get 'title defect))
     (mayhem-field "Severity" (concat (propertize (or level "") 'face
                                                  (mayhem-defect-severity-face level))
                                      (when-let* ((score (alist-get 'severity defect)))
                                        (propertize (format "  %s" score) 'face 'mayhem-label))))
     (mayhem-field "State" (alist-get 'state defect))
     (when-let* ((cwe (alist-get 'cwe_number defect)))
       (mayhem-field "CWE" (mayhem-link (format "CWE-%s" cwe)
                                        (or (alist-get 'cwe_link defect)
                                            (format "https://cwe.mitre.org/data/definitions/%s.html"
                                                    cwe)))
                     (concat "  " (or (alist-get 'cwe_type defect) ""))))
     (mayhem-field "Class" (alist-get 'defect_class_name defect))
     (mayhem-field "First seen" (mayhem--format-age (alist-get 'first_seen defect) now))
     (mayhem-field "Last seen" (mayhem--format-age (alist-get 'last_seen defect) now))
     (when-let* ((run (alist-get 'run data)))
       (mayhem-field "Run" (mayhem-run-link owner project target run)))
     (when-let* ((scm (alist-get 'scm data)))
       (mayhem-source-fold scm))
     (mayhem-defect--evidence-fields owner project target
                                     (alist-get 'source defect) (alist-get 'evidence data))
     (mayhem-block "Description"
                           (string-fill (or (alist-get 'description defect) "")
                                        (max 20 (min mayhem-defect--fill-width
                                                     (mayhem-page-width)))))
     (when (equal (alist-get 'source defect) "code")
       (mayhem-defect--testcases owner project target (alist-get 'evidence data)))
     (mayhem-defect--evidence-blocks (alist-get 'source defect) (alist-get 'evidence data)))))

(defun mayhem-defect--skeleton ()
  "Return grey bars shaped like a defect's page, shown until its data lands."
  (vui-fragment
   (mayhem-field "Title" (mayhem-skeleton-bar 30))
   (mayhem-field "Severity" (mayhem-skeleton-bar 10))
   (mayhem-field "State" (mayhem-skeleton-bar 6))
   (mayhem-field "CWE" (mayhem-skeleton-bar 40))
   (mayhem-field "Class" (mayhem-skeleton-bar 20))
   (mayhem-field "First seen" (mayhem-skeleton-bar 12))
   (mayhem-field "Last seen" (mayhem-skeleton-bar 22))
   (vui-newline)
   (mayhem-skeleton '((60) (52) (64) (40)))
   (vui-newline)
   (mayhem-notice "TEST CASE  RUN  TIME" 'mayhem-label)
   (mayhem-skeleton '((24) (24) (24)))))

(vui-defcomponent mayhem-defect-page (owner project target number run)
  "The page of defect NUMBER of TARGET of PROJECT of OWNER, as RUN saw it."
  :render
  (let ((snapshot (mayhem-sync-use-resource (list 'defect owner project target number run))))
    (vui-fragment
     (mayhem-target-page-heading (format "defect !%s" number) owner project target)
     (vui-newline)
     (mayhem-snapshot-view snapshot "defect" (mayhem-defect--skeleton)
                           (lambda (data)
                             (mayhem-defect--render owner project target data))))))

(defun mayhem-defect-open (owner project target number &optional run)
  "Open the page of defect NUMBER of TARGET of PROJECT of OWNER.
RUN, a run number, is the run whose evidence an API defect shows; else
its last run's, when the API names it."
  (mayhem-open-page (format "*mayhem: %s/%s/%s/defect-%s%s*" owner project target number
                            (if run (format "@%s" run) ""))
                    #'mayhem-defect-mode
                    (lambda () (vui-component 'mayhem-defect-page
                                              :owner owner :project project
                                              :target target :number number :run run))
                    (list 'defect owner project target number run)))

(provide 'mayhem-defect)
;;; mayhem-defect.el ends here
