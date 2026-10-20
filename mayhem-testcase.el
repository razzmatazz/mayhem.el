;;; mayhem-testcase.el --- Test case page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A test case's page, `*mayhem: owner/project/target/N/testcase-SHA*',
;; as a run saw it: whether it failed, the defects it shows, how to
;; reproduce it, its bytes, the target's output and its backtrace.
;; RET on a defect opens its page; C-c C-v shows the bytes as text
;; rather than in hex.

;;; Code:

(require 'subr-x)
(require 'vui)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)
(require 'mayhem-defect)

(mayhem-sync-define-resource testcase (owner project target run sha256)
  :fetch (lambda (done) (mayhem--fetch-testcase owner project target run sha256 done))
  :max-age mayhem-sync-settled-for)

(define-derived-mode mayhem-testcase-mode mayhem-page-mode "Mayhem Test Case"
  "Major mode for a Mayhem test case's page.
\\[mayhem-toggle-view] shows its bytes as text rather than in hex."
  (setq-local mayhem-views '("bytes in hex" "bytes as text")))

(defun mayhem-testcase--defects (owner project target run defects)
  "Return the vnodes listing DEFECTS of a test case of RUN.
RUN is a run of TARGET of PROJECT of OWNER."
  (vui-fragment
   (vui-newline)
   (mayhem-heading (format "Defects (%d)" (length defects)))
   (if (null defects)
       (mayhem-notice "No defects")
     (apply #'vui-fragment
            (seq-mapn (lambda (defect id)
                        (let ((level (or (alist-get 'severity_level defect) ""))
                              (number (alist-get 'defect_number defect)))
                          (mayhem-row
                           (list id "  "
                                 (propertize (format "%-7s" level)
                                             'face (mayhem-defect-severity-face level))
                                 " "
                                 (mayhem-fit (or (alist-get 'title defect) "")
                                             (string-width (or (alist-get 'title defect) ""))))
                           (lambda () (mayhem-defect-open owner project target number run))
                           "RET: open defect")))
                      defects (mayhem-defect-ids defects))))))

(defun mayhem-testcase--render (owner project target run data)
  "Return the vnodes of a test case of RUN, showing DATA.
RUN is a run of TARGET of PROJECT of OWNER."
  (let* ((test (alist-get 'testcase data))
         (start (alist-get 'started_at (alist-get 'run data)))
         (n (length (alist-get 'defects test)))
         (at (alist-get 'created_at test)))
    (vui-fragment
     (mayhem-field "Status" (mayhem-testcase-status n))
     (mayhem-field "Type" (mayhem-testcase-type (alist-get 'is_regression test)))
     (when-let* ((source (alist-get 'testcase_source test)))
       (mayhem-field "Source" source))
     (mayhem-field "Run" (mayhem-run-link owner project target run))
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
     (mayhem-block "Test case" (if mayhem-other-view
                                   (mayhem--bytes-text
                                    (mayhem--hexdump-bytes (alist-get 'hexdump test)))
                                 (alist-get 'hexdump test)))
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
   (mayhem-field "Source" (mayhem-skeleton-bar 8))
   (mayhem-field "Seen" (mayhem-skeleton-bar 16))
   (mayhem-field "Errors" (mayhem-skeleton-bar 12))
   (mayhem-field "Execution" (mayhem-skeleton-bar 6))
   (vui-newline)
   (mayhem-heading "Defects")
   (mayhem-skeleton '((6 " " 28) (6 " " 36) (6 " " 22)))))

(vui-defcomponent mayhem-testcase-page (owner project target run sha256)
  "The page of test case SHA256 of RUN of TARGET of PROJECT of OWNER."
  :render
  (let ((snapshot (mayhem-sync-use-resource
                   (list 'testcase owner project target run sha256))))
    (vui-fragment
     (mayhem-page-heading "test case" owner project target
                          (mayhem-run-link owner project target run (format "#%s" run)
                                           '(link mayhem-section-heading))
                          (substring sha256 0 (min 8 (length sha256))))
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
