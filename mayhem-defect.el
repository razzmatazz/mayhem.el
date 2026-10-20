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
;; reproduce it.

;;; Code:

(require 'subr-x)
(require 'vui)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)

(defconst mayhem-defect--fill-width 72
  "Column at which a defect's description is wrapped.")

(mayhem-sync-define-resource defect (owner project target number run)
  :fetch (lambda (done) (mayhem--fetch-defect owner project target number run done))
  :max-age mayhem-sync-settled-for)

(define-derived-mode mayhem-defect-mode mayhem-page-mode "Mayhem Defect"
  "Major mode for a Mayhem defect's page.")

(defun mayhem-defect--evidence-fields (source evidence)
  "Return the fields of EVIDENCE of a defect from SOURCE, \"api\" or \"code\"."
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
      (mayhem-field "Test cases" (format "%s" (or (alist-get 'count evidence) 0)))))))

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
                              (mayhem--split-command cmd)))
      (mayhem-block "Backtrace"
                            (if-let* ((frames (alist-get 'frames evidence)))
                                (mayhem-backtrace frames)
                              (alist-get 'backtrace evidence)))))))

(defun mayhem-defect--render (data)
  "Return the vnodes of a defect's page, showing DATA."
  (let* ((defect (alist-get 'defect data))
         (level (alist-get 'severity_level defect))
         (now (current-time)))
    (vui-fragment
     (mayhem-heading (or (alist-get 'title defect) ""))
     (vui-newline)
     (mayhem-field "Severity" (concat (propertize (or level "") 'face
                                                  (mayhem-defect-severity-face level))
                                      (when-let* ((score (alist-get 'severity defect)))
                                        (propertize (format "  %s" score) 'face 'mayhem-label))))
     (mayhem-field "State" (alist-get 'state defect))
     (when (alist-get 'cwe_number defect)
       (mayhem-field "CWE" (format "CWE-%s  %s" (alist-get 'cwe_number defect)
                                   (or (alist-get 'cwe_type defect) ""))))
     (mayhem-field "Class" (alist-get 'defect_class_name defect))
     (mayhem-field "First seen" (mayhem--format-age (alist-get 'first_seen defect) now))
     (mayhem-field "Last seen" (mayhem--format-age (alist-get 'last_seen defect) now))
     (when-let* ((run (alist-get 'run data)))
       (mayhem-field "Run" (format "#%s" run)))
     (mayhem-defect--evidence-fields (alist-get 'source defect) (alist-get 'evidence data))
     (mayhem-block "Description"
                           (string-fill (or (alist-get 'description defect) "")
                                        mayhem-defect--fill-width))
     (mayhem-defect--evidence-blocks (alist-get 'source defect) (alist-get 'evidence data)))))

(defun mayhem-defect--skeleton ()
  "Return grey bars shaped like a defect's page, shown until its data lands."
  (vui-fragment
   (mayhem-skeleton '((30)))
   (vui-newline)
   (mayhem-field "Severity" (mayhem-skeleton-bar 10))
   (mayhem-field "State" (mayhem-skeleton-bar 6))
   (mayhem-field "CWE" (mayhem-skeleton-bar 40))
   (mayhem-field "Class" (mayhem-skeleton-bar 20))
   (mayhem-field "First seen" (mayhem-skeleton-bar 12))
   (mayhem-field "Last seen" (mayhem-skeleton-bar 22))
   (vui-newline)
   (mayhem-skeleton '((60) (52) (64) (40)))))

(vui-defcomponent mayhem-defect-page (owner project target number run)
  "The page of defect NUMBER of TARGET of PROJECT of OWNER, as RUN saw it."
  :render
  (let ((snapshot (mayhem-sync-use-resource (list 'defect owner project target number run))))
    (vui-fragment
     (mayhem-heading (concat (propertize (concat owner "/" project) 'face 'mayhem-project)
                             "/"
                             (propertize target 'face 'mayhem-target)
                             (format " defect #%s" number)))
     (vui-newline)
     (mayhem-snapshot-view snapshot "defect" (mayhem-defect--skeleton)
                           #'mayhem-defect--render))))

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
