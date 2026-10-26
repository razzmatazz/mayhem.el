;;; mayhem-testsuite.el --- Test suite page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.
;; SPDX-License-Identifier: GPL-3.0-or-later

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
;;
;; Every test case of run N, `*mayhem: owner/project/target/N/testcases*',
;; is a page of its own: the suite keeps only those adding coverage,
;; and its count may be smaller than the run's.  It comes from the run's
;; test case results, so no files are downloaded.

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

(defconst mayhem-testsuite--header
  '("Test case" "Status" "Type" "Size" "Source" "Age")
  "The names of the columns of `mayhem-testsuite--cells'.
The first bytes follow them, under `mayhem-testsuite--bytes-name'.")

(defconst mayhem-testsuite--bytes-name "Bytes"
  "The name of the column of a test case's first bytes.")

(defun mayhem-testsuite--cells (file info now)
  "Return the cells of FILE's line, as of NOW, for `mayhem-columns'.
FILE is as the `testsuite' resource has it; INFO is as for
`mayhem-testsuite--sorted'.  The first bytes are left to the row, which
fits them to the page."
  (pcase-let* ((`(,sha ,size ,_) file)
               (tc (gethash sha info)))
    (list (propertize (substring sha 0 (min 8 (length sha))) 'mayhem-sha256 sha)
          (if tc (mayhem-testcase-status (alist-get 'n_defects tc)) "")
          (propertize (if tc (mayhem-testcase-type (alist-get 'is_regression tc)) "")
                      'face 'mayhem-label)
          (propertize (file-size-human-readable size) 'face 'mayhem-label)
          (propertize (or (alist-get 'source tc) "") 'face 'mayhem-label)
          (propertize (or (mayhem--format-age (alist-get 'created_at tc) now) "")
                      'face 'mayhem-label))))

(defun mayhem-testsuite--rows (owner project target run files info now)
  "Return the table of FILES of the test suite of RUN, as of NOW.
RUN is a run of TARGET of PROJECT of OWNER; INFO is as for
`mayhem-testsuite--sorted'.  Each row is RET-able and ends in the test
case's first bytes, cut to the page."
  (let* ((lines (mayhem-columns (mapcar (lambda (file) (mayhem-testsuite--cells file info now))
                                        files)
                                '(3) mayhem-testsuite--header))
         ;; Lines are trimmed; pad them so the bytes line up.
         (width (apply #'max 0 (mapcar #'string-width lines)))
         (bytes-width (apply #'max 0 (mapcar (lambda (file) (string-width (nth 2 file))) files))))
    (apply #'vui-fragment
           (vui-text (concat (string-pad (car lines) width) "  "
                             (propertize (upcase mayhem-testsuite--bytes-name) 'face 'mayhem-label)
                             "\n"))
           (seq-mapn (lambda (file line)
                       (mayhem-row
                        (list (string-pad line width) "  "
                              (mayhem-fit (nth 2 file) bytes-width))
                        (lambda () (mayhem-testcase-open owner project target run (car file)))
                        "RET: open test case"))
                     files (cdr lines)))))

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
       (mayhem-field "Test cases" (format "%d" (length files))
                     (when testcases
                       (vui-fragment
                        (propertize " of " 'face 'mayhem-label)
                        (mayhem-page-link (format "%d in the run" (length testcases))
                                          "RET: open every test case of the run"
                                          (lambda ()
                                            (mayhem-testcases-open owner project target run))))))
       (mayhem-field "Size" (file-size-human-readable
                             (apply #'+ (mapcar #'cadr files))))
       (when-let* ((sources (mayhem-testsuite--sources files info)))
         (mayhem-field "Sources" sources))
       (vui-newline)
       ;; The table's header names it; a heading would only repeat it.
       (if (null files)
           (mayhem-notice "No test cases")
         (mayhem-testsuite--rows owner project target run files info now))))))

(defun mayhem-testsuite--skeleton ()
  "Return grey bars shaped like a test suite's page, shown until its data lands."
  (vui-fragment
   (mayhem-field "Test cases" (mayhem-skeleton-bar 3))
   (mayhem-field "Size" (mayhem-skeleton-bar 6))
   (mayhem-field "Sources" (mayhem-skeleton-bar 24))
   (vui-newline)
   (mayhem-skeleton (make-list 8 '(8 "  " 7 "  " 10 "  " 5 "  " 10 "  " 14 "  " 24)))))

(vui-defcomponent mayhem-testsuite-page (owner project target run)
  "The page of the test suite of RUN of TARGET of PROJECT of OWNER."
  :render
  (let ((suite (mayhem-sync-use-resource (list 'testsuite owner project target run)))
        (testcases (mayhem-sync-use-resource (list 'run-testcases owner project target run))))
    (vui-fragment
     (mayhem-target-page-heading
      (list (mayhem-run-link owner project target run nil '(link mayhem-section-heading))
            ", test suite")
      owner project target)
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

;;;; Every test case of a run

(define-derived-mode mayhem-testcases-mode mayhem-page-mode "Mayhem Test Cases"
  "Major mode for the page of every test case of a Mayhem run."
  (setq-local mayhem-list-facets
              `(("Status" . ,#'mayhem-testcases--status)
                ("Type" . ,(lambda (tc) (mayhem-testcase-type (alist-get 'is_regression tc))))
                ("Source" . ,(lambda (tc) (alist-get 'source tc))))))

(defconst mayhem-testcases--header
  '("Test case" "Status" "Type" "Defects" nil "Source" "Time" "Age")
  "The names of the columns of `mayhem-testcases--cells'.")

(defun mayhem-testcases--status (tc)
  "Return TC's status, \"passing\" or \"failing\", without its face."
  (substring-no-properties (mayhem-testcase-status (alist-get 'n_defects tc))))

(defun mayhem-testcases--cells (tc now)
  "Return the cells of TC's line, as of NOW, for `mayhem-columns'.
TC is as `run-testcases' has it."
  (let ((sha (alist-get 'sha256 tc)))
    (list (substring sha 0 (min 8 (length sha)))
          (mayhem-testcase-status (alist-get 'n_defects tc))
          (propertize (mayhem-testcase-type (alist-get 'is_regression tc)) 'face 'mayhem-label)
          (format "%d" (or (alist-get 'n_defects tc) 0))
          (mayhem-testcase-severities tc)
          (propertize (or (alist-get 'source tc) "") 'face 'mayhem-label)
          (propertize (mayhem--format-ms (alist-get 'execution_time tc))
                      'face 'mayhem-label)
          (propertize (or (mayhem--format-age (alist-get 'created_at tc) now) "")
                      'face 'mayhem-label))))

(defun mayhem-testcases--rows (owner project target run testcases)
  "Return the table of TESTCASES of RUN, a RET-able row each.
RUN is a run of TARGET of PROJECT of OWNER."
  (let ((now (current-time)))
    (mayhem-table
     (mayhem-columns (mapcar (lambda (tc) (mayhem-testcases--cells tc now)) testcases)
                     '(3 6) mayhem-testcases--header)
     testcases
     (lambda (tc) (mayhem-testcase-open owner project target run (alist-get 'sha256 tc)))
     "RET: open test case")))

(vui-defcomponent mayhem-testcases-page (owner project target run)
  "The page of every test case of RUN of TARGET of PROJECT of OWNER, newest first."
  :render
  (let ((snapshot (mayhem-sync-use-resource (list 'run-testcases owner project target run))))
    (vui-fragment
     (mayhem-target-page-heading
      (list (mayhem-run-link owner project target run nil '(link mayhem-section-heading))
            ", test cases")
      owner project target)
     (vui-newline)
     (mayhem-snapshot-view
      snapshot "test cases"
      (mayhem-skeleton (make-list 8 '(8 "  " 7 "  " 10 "  " 7 "  " 8 "  " 5 "  " 12)))
      (lambda (testcases)
        (let* ((testcases (sort (copy-sequence testcases)
                                (lambda (a b) (string> (or (alist-get 'created_at a) "")
                                                       (or (alist-get 'created_at b) "")))))
               (shown (mayhem-list-filtered testcases)))
          (vui-fragment
           (mayhem-tally testcases #'mayhem-testcases--status '("failing" "passing")
                         (lambda (status) (if (equal status "failing") 'error 'success)))
           (when testcases
             (vui-fragment (vui-newline) (mayhem-list-filter-bar testcases shown)))
           (vui-newline)
           (cond (shown (mayhem-testcases--rows owner project target run shown))
                 (testcases (mayhem-notice "No test cases match the filter"))
                 (t (mayhem-notice "No test cases"))))))))))

(defun mayhem-testcases-open (owner project target run)
  "Open the page of every test case of RUN of TARGET of PROJECT of OWNER."
  (mayhem-open-page (format "*mayhem: %s/%s/%s/%s/testcases*" owner project target run)
                    #'mayhem-testcases-mode
                    (lambda () (vui-component 'mayhem-testcases-page
                                 :owner owner :project project
                                 :target target :run run))
                    (list 'testcases owner project target run)))

(provide 'mayhem-testsuite)
;;; mayhem-testsuite.el ends here
