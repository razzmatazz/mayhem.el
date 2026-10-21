;;; mayhem-testsuite.el --- Test suite page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A target's test suite, `*mayhem: owner/project/target/N/testsuite*':
;; the optimized set of its test cases at the end of run N, newest
;; first, each with whether it passes, whether it is new or a
;; regression, its size, where it came from, its age and its first
;; bytes.  RET on one opens its page; `w' saves its file.
;;
;; The API gives a suite only as a tarball of its files.  It is unpacked
;; as it lands: each file goes to the store's file table, by the sha256
;; of its bytes, and the resource keeps their names, sizes and previews.
;; A finished run's suite no longer changes, so it is fetched once.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'vui)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)
(require 'mayhem-run)
(require 'mayhem-testcase)

(defconst mayhem-testsuite--live-max-age 600
  "Seconds a going run's test suite is reused.
Each fetch downloads every file of the suite, so it is not refetched as
often as other data.")

(mayhem-sync-define-resource testsuite (owner project target run)
  :fetch (lambda (done)
           (mayhem--fetch-testsuite
            owner project target run
            (lambda (ok data)
              (if (not ok)
                  (funcall done nil data)
                (let ((files (alist-get 'files data)))
                  (condition-case err
                      (progn
                        (mayhem-sync-put-files files)
                        (funcall done t
                                 `((live . ,(alist-get 'live data))
                                   (files . ,(mapcar (pcase-lambda (`(,sha . ,bytes))
                                                       (list sha (length bytes)
                                                             (mayhem--bytes-preview bytes)))
                                                     files)))))
                    (error (funcall done nil (error-message-string err)))))))))
  :max-age (lambda (data)
             (if (alist-get 'live data) mayhem-testsuite--live-max-age t)))

(defvar-keymap mayhem-testsuite-mode-map
  :parent mayhem-page-mode-map
  "w" #'mayhem-testsuite-save-file)

(define-derived-mode mayhem-testsuite-mode mayhem-page-mode "Mayhem Test Suite"
  "Major mode for a Mayhem target's test suite page.

\\{mayhem-testsuite-mode-map}")

(defun mayhem-testsuite--sorted (files info)
  "Return FILES, as the `testsuite' resource has them, newest first.
INFO maps a sha256 to its test case, as `run-testcases' has it; those
it lacks come last."
  (let ((created (lambda (file)
                   (or (alist-get 'created_at (gethash (car file) info)) ""))))
    (sort (copy-sequence files)
          (lambda (a b) (string> (funcall created a) (funcall created b))))))

(defun mayhem-testsuite--sources (files info)
  "Return how many of FILES came from each source, as \"9 libfuzzer, 2 mayhem\".
INFO is as for `mayhem-testsuite--sorted'.  Nil when INFO knows none."
  (let (counts)
    (dolist (file files)
      (when-let* ((source (alist-get 'source (gethash (car file) info))))
        (cl-incf (alist-get source counts 0 nil #'equal))))
    (and counts
         (mapconcat (pcase-lambda (`(,source . ,n)) (format "%d %s" n source))
                    (sort counts (lambda (a b) (> (cdr a) (cdr b))))
                    ", "))))

(defun mayhem-testsuite--row (owner project target run file info now)
  "Return the row of FILE of the test suite of RUN, as of NOW.
RUN is a run of TARGET of PROJECT of OWNER; INFO is as for
`mayhem-testsuite--sorted'."
  (pcase-let* ((`(,sha ,size ,preview) file)
               (tc (gethash sha info)))
    (mayhem-row
     (list (propertize (substring sha 0 (min 8 (length sha))) 'mayhem-sha256 sha)
           (format "  %-7s" (if tc (mayhem-testcase-status (alist-get 'n_defects tc)) ""))
           (propertize (format "  %-10s" (if tc (mayhem-testcase-type (alist-get 'is_regression tc))
                                           ""))
                       'face 'mayhem-label)
           (propertize (format "  %5s" (file-size-human-readable size))
                       'face 'mayhem-label)
           (propertize (format "  %-10s" (or (alist-get 'source tc) ""))
                       'face 'mayhem-label)
           (propertize (format "  %-14s" (or (mayhem--format-age (alist-get 'created_at tc) now)
                                             ""))
                       'face 'mayhem-label)
           (mayhem-fit preview (string-width preview)))
     (lambda () (mayhem-testcase-open owner project target run sha))
     "RET: open test case")))

(defun mayhem-testsuite--render (owner project target run data testcases)
  "Return the vnodes of the test suite of RUN, showing DATA.
RUN is a run of TARGET of PROJECT of OWNER.  TESTCASES are the target's,
as `run-testcases' has them, or nil before they land."
  (let ((info (make-hash-table :test #'equal))
        (now (current-time)))
    (dolist (tc testcases)
      (puthash (alist-get 'sha256 tc) tc info))
    (let ((files (mayhem-testsuite--sorted (alist-get 'files data) info)))
      (vui-fragment
       (when (alist-get 'live data)
         (mayhem-field "Status" (propertize "the run is going; the suite still changes"
                                            'face 'warning)))
       (mayhem-field "Size" (file-size-human-readable
                             (apply #'+ (mapcar #'cadr files))))
       (when-let* ((sources (mayhem-testsuite--sources files info)))
         (mayhem-field "Sources" sources))
       (vui-newline)
       (mayhem-heading (format "Test cases (%d)" (length files)))
       (if (null files)
           (mayhem-notice "No test cases")
         (apply #'vui-fragment
                (mapcar (lambda (file)
                          (mayhem-testsuite--row owner project target run file info now))
                        files)))))))

(defun mayhem-testsuite--skeleton ()
  "Return grey bars shaped like a test suite's page, shown until its data lands."
  (vui-fragment
   (mayhem-field "Size" (mayhem-skeleton-bar 6))
   (mayhem-field "Sources" (mayhem-skeleton-bar 24))
   (vui-newline)
   (mayhem-heading "Test cases")
   (mayhem-skeleton (make-list 8 '(8 "  " 7 "  " 10 "  " 5 "  " 10 "  " 14 "  " 24)))))

(vui-defcomponent mayhem-testsuite-page (owner project target run)
  "The page of the test suite of RUN of TARGET of PROJECT of OWNER."
  :render
  (let ((suite (mayhem-sync-use-resource (list 'testsuite owner project target run)))
        (testcases (mayhem-sync-use-resource (list 'run-testcases owner project target run))))
    (vui-fragment
     (mayhem-page-heading nil owner project target
                          (mayhem-run-link owner project target run (format "#%s" run)
                                           '(link mayhem-section-heading))
                          "tests")
     (vui-newline)
     (mayhem-snapshot-view suite "test suite" (mayhem-testsuite--skeleton)
                           (lambda (data)
                             (mayhem-testsuite--render owner project target run data
                                                       (plist-get testcases :data)))))))

(defun mayhem-testsuite-open (owner project target run)
  "Open the page of the test suite of RUN of TARGET of PROJECT of OWNER."
  (mayhem-open-page (format "*mayhem: %s/%s/%s/%s/testsuite*" owner project target run)
                    #'mayhem-testsuite-mode
                    (lambda () (vui-component 'mayhem-testsuite-page
                                              :owner owner :project project
                                              :target target :run run))
                    (list 'testsuite owner project target run)))

(defun mayhem-testsuite-save-file (sha256 file)
  "Save the file of the test case SHA256, the one at point, as FILE.
It comes from the store, where its test suite put it."
  (interactive
   (let ((sha (or (get-text-property (line-beginning-position) 'mayhem-sha256)
                  (user-error "Mayhem: No test case at point"))))
     (list sha (read-file-name "Save test case as: " nil nil nil sha))))
  (let ((bytes (or (mayhem-sync-file sha256)
                   (user-error "Mayhem: Test case %s is not stored; g to fetch its suite"
                               (substring sha256 0 (min 8 (length sha256))))))
        (file (if (file-directory-p file) (expand-file-name sha256 file) file)))
    (when (and (file-exists-p file)
               (not (y-or-n-p (format "%s exists; overwrite? " file))))
      (user-error "Mayhem: Not saved"))
    (let ((coding-system-for-write 'binary))
      (write-region bytes nil file))
    (message "Mayhem: Saved %s" (abbreviate-file-name file))))

(provide 'mayhem-testsuite)
;;; mayhem-testsuite.el ends here
