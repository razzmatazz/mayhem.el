;;; mayhem-testcase.el --- Test case page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A test case's page, `*mayhem: owner/project/target/N/testcase-SHA*',
;; as a run saw it: whether it failed, the defects it shows, how to
;; reproduce it, its bytes, the target's output and its backtrace.
;; RET on a defect opens its page.

;;; Code:

(require 'subr-x)
(require 'vui)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)
(require 'mayhem-defect)

(mayhem-sync-define-resource testcase (owner project target run sha256)
  :fetch (lambda (done) (mayhem--fetch-testcase owner project target run sha256 done)))

(define-derived-mode mayhem-testcase-mode mayhem-page-mode "Mayhem Test Case"
  "Major mode for a Mayhem test case's page.")

(defun mayhem-testcase--defects (owner project target run defects)
  "Return the vnodes listing DEFECTS of a test case of RUN.
RUN is a run of TARGET of PROJECT of OWNER."
  (vui-fragment
   (vui-newline)
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

(defun mayhem-testcase--render (owner project target run data)
  "Return the vnodes of a test case of RUN, showing DATA.
RUN is a run of TARGET of PROJECT of OWNER."
  (let* ((test (alist-get 'testcase data))
         (start (alist-get 'started_at (alist-get 'run data)))
         (n (length (alist-get 'defects test)))
         (at (alist-get 'created_at test)))
    (vui-fragment
     (mayhem-field "Status" (if (> n 0)
                                (propertize "failing" 'face 'error)
                              (propertize "passing" 'face 'success)))
     (mayhem-field "Type" (if (alist-get 'is_regression test) "regression" "new"))
     (mayhem-field "Run" (format "#%s" run))
     (when (and at start)
       (mayhem-field "Seen" (concat (mayhem--format-elapsed (mayhem--elapsed at start))
                                    (propertize " into the run" 'face 'mayhem-label))))
     (mayhem-field "Errors" (format "%s at runtime" (or (alist-get 'n_valgrind_errors test) 0)))
     (when-let* ((secs (alist-get 'execution_time test)))
       (mayhem-field "Execution" (format "%dms" (round (* 1000 secs)))))
     (when (alist-get 'crashed test)
       (mayhem-field "Crash" (string-join
                              (delq nil (list (alist-get 'crash_type test)
                                              (when-let* ((sig (alist-get 'signal_number test)))
                                                (format "signal %s" sig))
                                              (when-let* ((addr (alist-get 'faulting_address test)))
                                                (format "at %s" addr))))
                              ", ")))
     (mayhem-testcase--defects owner project target run (alist-get 'defects test))
     (mayhem-block "Reproduce" (when-let* ((cmd (alist-get 'repro_cmdline test)))
                                 (mayhem--split-command cmd)))
     (mayhem-block "Test case" (alist-get 'hexdump test))
     (mayhem-block "Output" (alist-get 'output test))
     (mayhem-block "Backtrace" (if-let* ((frames (alist-get 'frames test)))
                                   (mayhem-backtrace frames)
                                 (alist-get 'backtrace test))))))

(defun mayhem-testcase--skeleton ()
  "Return grey bars shaped like a test case's page, shown until its data lands."
  (vui-fragment
   (mayhem-field "Status" (mayhem-skeleton-bar 7))
   (mayhem-field "Type" (mayhem-skeleton-bar 10))
   (mayhem-field "Run" (mayhem-skeleton-bar 3))
   (mayhem-field "Seen" (mayhem-skeleton-bar 16))
   (mayhem-field "Errors" (mayhem-skeleton-bar 12))
   (mayhem-field "Execution" (mayhem-skeleton-bar 6))
   (vui-newline)
   (mayhem-heading "Defects")
   (mayhem-skeleton '(("  " 6 " " 28) ("  " 6 " " 36) ("  " 6 " " 22)))))

(vui-defcomponent mayhem-testcase-page (owner project target run sha256)
  "The page of test case SHA256 of RUN of TARGET of PROJECT of OWNER."
  :render
  (let ((snapshot (mayhem-sync-use-resource
                   (list 'testcase owner project target run sha256))))
    (vui-fragment
     (mayhem-heading (concat (propertize (concat owner "/" project) 'face 'mayhem-project)
                             "/"
                             (propertize target 'face 'mayhem-target)
                             (format " #%s test case %s" run
                                     (substring sha256 0 (min 8 (length sha256))))))
     (vui-newline)
     (mayhem-snapshot-view snapshot "test case" (mayhem-testcase--skeleton)
                           (lambda (data)
                             (mayhem-testcase--render owner project target run data))))))

(defun mayhem-testcase-open (owner project target run sha256)
  "Open the page of test case SHA256 of RUN of TARGET of PROJECT of OWNER."
  (mayhem-open-page (format "*mayhem: %s/%s/%s/%s/testcase-%s*" owner project target run
                            (substring sha256 0 (min 8 (length sha256))))
                    #'mayhem-testcase-mode
                    (lambda () (vui-component 'mayhem-testcase-page
                                              :owner owner :project project
                                              :target target :run run :sha256 sha256))
                    (list 'testcase owner project target run sha256)))

(provide 'mayhem-testcase)
;;; mayhem-testcase.el ends here
