;;; mayhem-run.el --- Run page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A run's page, `*mayhem: owner/project/target/N*': its status, commit
;; and image; for a code run, a chart of its progress, as the web app's
;; run page has.  Below, in tabs: its defects; for a code run its tests
;; (counts and failing test cases) and coverage, for an API run its
;; endpoints; and its event log, shown first for a failed run.  RET on a defect or test case opens
;; its page.  While the run is going, the page refetches every
;; `mayhem-run-refresh-interval' seconds.

;;; Code:

(require 'vui)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)
(require 'mayhem-defect)

(declare-function mayhem-testcase-open "mayhem-testcase" (owner project target run sha256))
(declare-function mayhem-testsuite-open "mayhem-testsuite" (owner project target run))

(defcustom mayhem-run-refresh-interval 10
  "Seconds between refetches of a run's page while the run is going."
  :type 'number
  :group 'mayhem)

(defconst mayhem-run--testcases-max-age 600
  "Seconds a run's test case results are reused.
The API sends each one's full report, so they are not refetched as
often as other data.")

(mayhem-sync-define-resource run-testcases (owner project target run)
  :fetch (lambda (done) (mayhem--fetch-run-testcases owner project target run done))
  :max-age mayhem-run--testcases-max-age)

(defconst mayhem-run--chart-width 60
  "Columns of a run's progress chart, at most.")

(defconst mayhem-run--chart-height 4
  "Rows of a run's progress chart.")

(mayhem-sync-define-resource run (owner project target number)
  :fetch (lambda (done) (mayhem--fetch-run owner project target number done))
  ;; A finished run no longer changes.
  :max-age (lambda (data)
             (if (mayhem-run--live-p (alist-get 'run data))
                 mayhem-sync-fresh-for
               mayhem-sync-settled-for)))

(define-derived-mode mayhem-run-mode mayhem-page-mode "Mayhem Run"
  "Major mode for a Mayhem run's page.")

(defun mayhem-run--defects (owner project target run defects)
  "Return the vnodes listing DEFECTS of RUN of TARGET of PROJECT of OWNER."
  (vui-fragment
   (if (null defects)
       (mayhem-notice "No defects")
     (apply #'vui-fragment
            (mapcar (lambda (defect)
                      (let ((level (or (alist-get 'severity_level defect) ""))
                            (number (alist-get 'defect_number defect)))
                        (mayhem-row
                         (list (propertize (format "%-7s" level)
                                           'face (mayhem-defect-severity-face level))
                               " "
                               (mayhem-fit (or (alist-get 'title defect) "")
                                           (string-width (or (alist-get 'title defect) "")))
                               (propertize (format "  defect #%s" number) 'face 'mayhem-label))
                         (lambda () (mayhem-defect-open owner project target number run))
                         "RET: open defect")))
                    defects)))))

(defun mayhem-run--endpoints (endpoints)
  "Return the vnodes listing ENDPOINTS of an API run."
  (if (null endpoints)
      (mayhem-notice "No endpoints")
    (let ((path-width (apply #'max 1 (mapcar (lambda (endpoint)
                                                (string-width (or (alist-get 'path endpoint) "")))
                                              endpoints))))
      (apply #'vui-fragment
             (mapcar (lambda (endpoint)
                       (let ((passing (alist-get 'passing endpoint))
                             (n (or (alist-get 'defects_total endpoint) 0)))
                         (mayhem-line
                          (list (format "%-7s" (or (alist-get 'method endpoint) ""))
                                (mayhem-fit (or (alist-get 'path endpoint) "") path-width t)
                                (propertize (if passing "  passing" "  failing")
                                            'face (if passing 'success 'error))
                                (propertize (format "  %d defect%s" n (if (= n 1) "" "s"))
                                            'face 'mayhem-label)
                                (if (alist-get 'covered endpoint) ""
                                  (propertize "  not covered" 'face 'mayhem-label))))))
                     endpoints)))))

(defun mayhem-run--live-p (run)
  "Return non-nil if RUN, an alist, is still pending or running."
  (and run (not (or (alist-get 'ended run) (alist-get 'failed run)
                    (alist-get 'stopped run)))))

(defun mayhem-run--elapsed-text (timestamp start)
  "Return TIMESTAMP as the time since START, the run's, such as \"4:52\".
The exact time is its `help-echo' and `mayhem-ts', as for an age."
  (if (not (and timestamp start))
      ""
    (let ((exact (format-time-string "%a %Y-%m-%d %H:%M:%S %Z"
                                     (encode-time (iso8601-parse timestamp)))))
      (propertize (mayhem--format-elapsed (mayhem--elapsed timestamp start))
                  'help-echo exact 'mayhem-ts exact))))

(defun mayhem-run--percent (covered total)
  "Return COVERED of TOTAL as \"39.25%  2972 of 7572\", or nil without a TOTAL."
  (when (and covered total (> total 0))
    (concat (format "%.2f%%" (/ (* 100.0 covered) total))
            (propertize (format "  %d of %d" covered total) 'face 'mayhem-label))))

(defun mayhem-run--coverage (run)
  "Return the vnodes of the coverage of RUN, a code run."
  (vui-fragment
   (mayhem-field "Lines" (mayhem-run--percent (alist-get 'n_lines_covered run)
                                              (alist-get 'n_lines_total run)))
   (mayhem-field "Blocks" (mayhem-run--percent (alist-get 'n_blocks_covered run)
                                               (alist-get 'n_blocks_total run)))
   (mayhem-field "Functions" (mayhem-run--percent (alist-get 'n_functions_covered run)
                                                  (alist-get 'n_functions_total run)))
   (mayhem-field "Behaviors" (format "%s edges" (or (alist-get 'edges_covered run) 0)))
   (mayhem-field "Inputs" (concat (format "%s tested" (or (alist-get 'tests_run run) 0))
                                  (when-let* ((rate (alist-get 'tests_per_second run)))
                                    (propertize (format "  %s per second" rate)
                                                'face 'mayhem-label))))))

(defun mayhem-run--test-counts (owner project target number run)
  "Return the vnodes of how many test cases RUN, a code run, has, by kind.
RUN is run NUMBER of TARGET of PROJECT of OWNER."
  (let* ((all (or (alist-get 'n_testcase_reports run) 0))
         (regression (or (alist-get 'n_regression_testcase_reports run) 0))
         (failing (or (alist-get 'n_regression_defect_reports run) 0))
         (optimized (alist-get 'n_optimized_set_testcases run)))
    (vui-fragment
     (mayhem-field "All" (format "%d test case%s" all (if (= all 1) "" "s")))
     (mayhem-field "Regression" (format "%d of %d passing" (- regression failing) regression))
     (mayhem-field "New" (format "%d discovered" (- all regression)))
     (when optimized
       (mayhem-field "Optimized"
                     (mayhem-page-link (format "%d test case%s" optimized
                                               (if (= optimized 1) "" "s"))
                                       "RET: open test suite"
                                       (lambda ()
                                         (mayhem-testsuite-open owner project target number)))
                     " in the suite")))))

(defun mayhem-run--chart (run progress now)
  "Return the vnodes charting PROGRESS of RUN, a code run, as of NOW.
Like the web app's chart: test cases processed over the time since the
run started, a dot where more defects were found.  Each column's time
and counts are its `help-echo'.  Nothing before the run starts."
  (when-let* ((start (alist-get 'started_at run))
              ((alist-get 'testcases progress)))
    (let* ((most (apply #'max 0 (mapcar #'cdr (alist-get 'testcases progress))))
           (margin (max 4 (length (number-to-string most))))
           (pad (make-string (1+ margin) ?\s))
           (width (max 10 (min mayhem-run--chart-width (- (mayhem-page-width) (1+ margin)))))
           (span (if-let* ((end (alist-get 'ended_at run)))
                     (mayhem--elapsed end start)
                   (float-time (time-subtract now (encode-time (iso8601-parse start))))))
           (series (lambda (key)
                     (mayhem--step-series (mapcar (pcase-lambda (`(,ts . ,n))
                                                    (cons (mayhem--elapsed ts start) n))
                                                  (alist-get key progress))
                                          span width)))
           (tests (funcall series 'testcases))
           (defects (funcall series 'defects))
           (tips (seq-mapn (lambda (i n d)
                             (format "%s  %d test case%s, %d defect%s"
                                     (mayhem--format-elapsed (* span (/ (1+ i) (float width))))
                                     n (if (= n 1) "" "s") d (if (= d 1) "" "s")))
                           (number-sequence 0 (1- width)) tests defects))
           (tip (lambda (string)
                  (let ((s (copy-sequence string)))
                    (seq-do-indexed (lambda (text i)
                                      (put-text-property i (1+ i) 'help-echo text s)
                                      (put-text-property i (1+ i) 'mayhem-ts text s))
                                    tips)
                    s)))
           (top (apply #'max 0 tests))
           (rows (mayhem--bar-rows tests mayhem-run--chart-height))
           (dots (apply #'string (seq-mapn (lambda (d prev) (if (> d prev) ?● ?\s))
                                           defects (cons 0 defects))))
           (end (mayhem--format-elapsed span)))
      (vui-fragment
       (vui-newline)
       (mayhem-heading "Progress")
       (vui-text
        (concat
         pad (propertize (concat (propertize "▆" 'face 'mayhem-target)
                                 " test cases processed  "
                                 (propertize "●" 'face 'error) " defects found")
                         'face 'mayhem-label)
         "\n"
         (mapconcat (lambda (row)
                      (concat (propertize (format (format "%%%ds " margin)
                                                  (if (eq row (car rows)) top ""))
                                          'face 'mayhem-label)
                              (propertize (funcall tip row) 'face 'mayhem-target)
                              "\n"))
                    rows "")
         pad (propertize (funcall tip dots) 'face 'error) "\n"
         pad (propertize (concat "0:00" (make-string (max 1 (- width 4 (length end))) ?\s) end)
                         'face 'mayhem-label)
         "\n"))))))

(defun mayhem-run--tests (owner project target number run failing)
  "Return the vnodes listing FAILING, the failing test cases of RUN.
RUN is run NUMBER of TARGET of PROJECT of OWNER."
  (let ((start (alist-get 'started_at run)))
    (vui-fragment
     (mayhem-heading (format "Failing tests (%d)" (length failing)))
     (if (null failing)
         (mayhem-notice "No failing tests")
       (apply #'vui-fragment
              (mapcar (lambda (test)
                        (let ((sha (alist-get 'sha256 test))
                              (n (or (alist-get 'n_defects test) 0)))
                          (mayhem-row
                           (concat (substring sha 0 (min 8 (length sha)))
                                   (propertize (if (alist-get 'is_regression test)
                                                   "  regression" "  new       ")
                                               'face 'mayhem-label)
                                   (format "  %3d defect%s " n (if (= n 1) " " "s"))
                                   (propertize
                                    (format "%5dms  " (round (* 1000 (or (alist-get 'execution_time test)
                                                                         0))))
                                    'face 'mayhem-label)
                                   (mayhem-run--elapsed-text (alist-get 'created_at test) start)
                                   "  "
                                   (mapconcat
                                    (lambda (level)
                                      (propertize (format "%d %s" (alist-get (intern level) test) level)
                                                  'face (mayhem-defect-severity-face level)))
                                    (seq-filter (lambda (level) (> (alist-get (intern level) test) 0))
                                                '("high" "medium" "low"))
                                    ", ")
                                   "\n")
                           (lambda () (mayhem-testcase-open owner project target number sha))
                           "RET: open test case")))
                      failing))))))

(vui-defcomponent mayhem-run-tests-tab (owner project target number run)
  "The Tests tab of RUN, run NUMBER of TARGET of PROJECT of OWNER.
A test case fails when it shows a defect, crash or not; it is its own
component so a run's test case results are fetched only once it shows."
  :render
  (let ((snapshot (mayhem-sync-use-resource
                   (list 'run-testcases owner project target number))))
    (vui-fragment
     (mayhem-run--test-counts owner project target number run)
     (vui-newline)
     (mayhem-snapshot-view
      snapshot "test cases"
      (vui-fragment
       (mayhem-heading "Failing tests")
       (mayhem-skeleton '((8 "  " 10 "  " 10 "  " 7 "  " 12) (8 "  " 10 "  " 10 "  " 7 "  " 12))))
      (lambda (tests)
        (mayhem-run--tests owner project target number run
                           (seq-filter (lambda (test) (> (or (alist-get 'n_defects test) 0) 0))
                                       tests)))))))

(defun mayhem-run--phase (phase)
  "Return the name the web app gives to PHASE, an event's."
  (pcase phase
    ("dynamic_analysis" "behavior")
    ("static_analysis" "exploitability")
    ("regression_testing" "regression")
    ("coverage_analysis" "coverage")
    ((or 'nil "") "")
    (_ (replace-regexp-in-string "_" " " phase))))

(defconst mayhem-run--event-indent 26
  "Column at which an event's description starts.")

(defconst mayhem-run--event-width 70
  "Column at which an event's description is wrapped, from its start, at most.")

(defun mayhem-run--events (events)
  "Return the vnodes of the event log EVENTS of a run, newest first."
  (vui-fragment
   (if (null events)
       (mayhem-notice "No events")
     (vui-text
      (mapconcat
       (lambda (event)
         (let* ((at (encode-time (iso8601-parse (alist-get 'created_at event))))
                (exact (format-time-string "%a %Y-%m-%d %H:%M:%S %Z" at))
                (level (or (alist-get 'event_level event) 1))
                (face (cond ((>= level 3) 'error) ((= level 2) 'warning)
                            ((= level 0) 'mayhem-label))))
           (concat (propertize (format-time-string "%H:%M:%S" at)
                               'face 'mayhem-label 'help-echo exact 'mayhem-ts exact)
                   (propertize (format "  %-16s" (mayhem-run--phase (alist-get 'event_phase event)))
                               'face 'mayhem-label)
                   ;; Wrapped, with the lines after the first under it.
                   (let ((desc (replace-regexp-in-string
                                "\n" (concat "\n" (make-string mayhem-run--event-indent ?\s))
                                (string-fill (string-trim (or (alist-get 'event_desc event) ""))
                                             (max 20 (min mayhem-run--event-width
                                                          (- (mayhem-page-width)
                                                             mayhem-run--event-indent)))))))
                     (if face (propertize desc 'face face) desc))
                   "\n")))
       events "")))))

(defun mayhem-run--tabs (run data)
  "Return the tabs of the page of RUN, showing DATA, as (KEY LABEL).
RUN is the alist from DATA's `run'."
  (let ((count (lambda (label key)
                 (format "%s (%d)" label (length (alist-get key data))))))
    (if (alist-get 'api_run run)
        `((defects ,(funcall count "Defects" 'defects))
          (endpoints ,(funcall count "Endpoints" 'endpoints))
          (events ,(funcall count "Log" 'events)))
      `((defects ,(funcall count "Defects" 'defects))
        (tests ,(format "Tests (%d)" (or (alist-get 'n_testcase_reports run) 0)))
        (coverage "Coverage")
        (events ,(funcall count "Log" 'events))))))

(defun mayhem-run--tab (owner project target number run data tab)
  "Return the vnodes of TAB, a key of `mayhem-run--tabs', of RUN.
RUN is run NUMBER of TARGET of PROJECT of OWNER, from DATA."
  (pcase tab
    ('defects (mayhem-run--defects owner project target number (alist-get 'defects data)))
    ('tests (vui-component 'mayhem-run-tests-tab :owner owner :project project
                           :target target :number number :run run))
    ('events (mayhem-run--events (alist-get 'events data)))
    ('coverage (mayhem-run--coverage run))
    ('endpoints (mayhem-run--endpoints (alist-get 'endpoints data)))))

(defun mayhem-run--render (owner project target number data tab on-tab)
  "Return the vnodes of run NUMBER of TARGET of PROJECT of OWNER, showing DATA.
TAB is the key of the tab shown; when nil or not the run's, the
log for a failed run, which says why, else the first.  ON-TAB is
called with the key of another one, to show it."
  (let* ((run (alist-get 'run data))
         (image (alist-get 'docker_pullable run))
         (factors (alist-get 'n_exploitability_factors_total run))
         (code (not (alist-get 'api_run run)))
         (tabs (mayhem-run--tabs run data))
         (shown (car (or (assq tab tabs)
                         (and (alist-get 'failed run) (assq 'events tabs))
                         (car tabs))))
         (now (current-time)))
    (vui-fragment
     (mayhem-field "Status" (concat (mayhem-run-status run)
                                    (when-let* ((d (alist-get 'description run)))
                                      (propertize (concat "  " d) 'face 'mayhem-label))))
     (mayhem-field "Started" (concat (or (mayhem--format-age (alist-get 'started_at run) now)
                                         "not yet")
                                     (when-let* ((by (alist-get 'started_by run)))
                                       (propertize (concat "  by " by) 'face 'mayhem-label))))
     (mayhem-field "Duration" (mayhem--format-duration (alist-get 'duration run)))
     (mayhem-scm-fields run)
     (when image
       (mayhem-field "Image" (if-let* ((digest (alist-get 'fetched_docker_image_digest run)))
                                 (propertize image 'help-echo digest)
                               image)))
     (when (and factors (> factors 0))
       (mayhem-field "Hardening"
                     (format "%s of %s exploitability factors" (or (alist-get 'n_exploitability_factors_passing run) 0)
                             factors)))
     (when code
       (mayhem-run--chart run (alist-get 'progress data) now))
     (vui-newline)
     (mayhem-tab-row (mapcar (pcase-lambda (`(,key ,label))
                               (list label (format "RET: show %s" (downcase label))
                                     (unless (eq key shown)
                                       (lambda () (funcall on-tab key)))))
                             tabs))
     (mayhem-run--tab owner project target number run data shown))))

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
   (mayhem-skeleton '((6 " " 28) (6 " " 36) (6 " " 22) (6 " " 30)))))

(vui-defcomponent mayhem-run-page (owner project target number)
  "The page of run NUMBER of TARGET of PROJECT of OWNER."
  :state ((tab nil))
  :render
  (let* ((spec (list 'run owner project target number))
         (snapshot (mayhem-sync-use-resource spec))
         (live (mayhem-run--live-p (alist-get 'run (plist-get snapshot :data)))))
    (vui-use-effect (live)
      (when live
        (let* ((buf (current-buffer))
               (timer nil))
          (setq timer (run-with-timer mayhem-run-refresh-interval mayhem-run-refresh-interval
                                      (lambda ()
                                        (if (buffer-live-p buf)
                                            (mayhem-sync-request spec t)
                                          (cancel-timer timer)))))
          (lambda () (cancel-timer timer)))))
    (vui-fragment
     (mayhem-page-heading owner project target (format " run #%s" number))
     (vui-newline)
     (mayhem-snapshot-view snapshot "run" (mayhem-run--skeleton)
                           (lambda (data)
                             (mayhem-run--render owner project target number data tab
                                                 (lambda (key) (vui-set-state :tab key))))))))

(defun mayhem-run-open (owner project target number)
  "Open the page of run NUMBER of TARGET of PROJECT of OWNER."
  (mayhem-open-page (format "*mayhem: %s/%s/%s/%s*" owner project target number)
                    #'mayhem-run-mode
                    (lambda () (vui-component 'mayhem-run-page
                                              :owner owner :project project
                                              :target target :number number))
                    (list 'run owner project target number)))

(provide 'mayhem-run)
;;; mayhem-run.el ends here
