;;; mayhem-run.el --- Run page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A run's page, `*mayhem: owner/project/target/N*': its status, commit
;; and image, and its Mayhemfile, which RET shows as a file; for a code
;; run, a chart of its progress, as the web app's run page has.  Below,
;; in tabs: its defects; for a code run its tests (counts and failing
;; test cases) and coverage, for an API run its endpoints; and its
;; event log, shown first for a failed run.  What the CLI overrode,
;; the environment it added and the files sent are each a header line,
;; folded when too wide for one.  RET on a defect or test case opens
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
  ;; A finished run no longer changes, once a later one says it is not
  ;; the latest.
  :max-age (lambda (data)
             (let ((run (alist-get 'run data)))
               (if (or (mayhem-run--live-p run) (not (alist-get 'next_run_number run)))
                   mayhem-sync-fresh-for
                 mayhem-sync-settled-for))))

(define-derived-mode mayhem-run-mode mayhem-page-mode "Mayhem Run"
  "Major mode for a Mayhem run's page.")

(defun mayhem-run--defects (owner project target run defects)
  "Return the vnodes listing DEFECTS of RUN of TARGET of PROJECT of OWNER."
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
                     defects (mayhem-defect-ids defects)))))

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
                                                'face 'mayhem-label))))
   (when-let* ((engines (mayhem-run--engines run)))
     (mayhem-field "Engines" engines))))

(defun mayhem-run--engines (run)
  "Return how many inputs each engine of RUN tested, or nil if none did."
  (let ((parts (delq nil
                     (mapcar (pcase-lambda (`(,key . ,name))
                               (let ((n (or (alist-get key run) 0)))
                                 (when (> n 0) (format "%s %d" name n))))
                             '((tests_run_mfuzz . "Mayhem fuzzer")
                               (tests_run_libfuzz . "libFuzzer")
                               (tests_run_honggfuzz . "honggfuzz")
                               (tests_run_symexec . "symbolic execution"))))))
    (and parts (string-join parts ", "))))

(defun mayhem-run--test-counts (owner project target number run)
  "Return the vnodes of how many test cases RUN, a code run, has, by kind.
RUN is run NUMBER of TARGET of PROJECT of OWNER."
  (let* ((all (or (alist-get 'n_testcase_reports run) 0))
         (regression (or (alist-get 'n_regression_testcase_reports run) 0))
         (failing (or (alist-get 'n_regression_defect_reports run) 0))
         (optimized (alist-get 'n_optimized_set_testcases run))
         (starting (alist-get 'n_starting_testcases run))
         (measured (alist-get 'n_initial_coverage_collection_processed run))
         (to-measure (alist-get 'n_initial_coverage_collection_total run))
         (corpus (alist-get 'n_total_testsuite_size run))
         (queued (alist-get 'triage_queue_size run))
         (split (lambda (key)
                  (propertize (format "  %d new, %d regression"
                                      (or (alist-get (intern (format "n_behavior_%s" key)) run) 0)
                                      (or (alist-get (intern (format "n_regression_%s" key)) run) 0))
                              'face 'mayhem-label))))
    (vui-fragment
     (mayhem-field "All" (format "%d test case%s" all (if (= all 1) "" "s")))
     (mayhem-field "Regression" (format "%d of %d passing" (- regression failing) regression))
     (mayhem-field "New" (format "%d discovered" (- all regression)))
     (when starting
       (mayhem-field "Starting" (format "%d test case%s" starting (if (= starting 1) "" "s"))
                     (when (and to-measure (> to-measure 0))
                       (propertize (format "  coverage of %d of %d measured"
                                           (or measured 0) to-measure)
                                   'face 'mayhem-label))))
     (when-let* ((n (alist-get 'n_crash_reports run)))
       (mayhem-field "Crashes" (format "%d" n) (funcall split "crash_reports")))
     (when-let* ((n (alist-get 'n_valgrind_errors run)))
       (mayhem-field "Memory" (format "%d Valgrind error%s" n (if (= n 1) "" "s"))
                     (funcall split "valgrind_errors")))
     (when (and corpus (> corpus 0))
       (mayhem-field "Corpus" (format "%d test case%s" corpus (if (= corpus 1) "" "s"))
                     (when-let* ((kept (alist-get 'n_optimized_testsuite_size run)))
                       (propertize (format "  %d after optimizing" kept) 'face 'mayhem-label))))
     ;; Only a live run's queue says anything about its progress.
     (when (and queued (> queued 0) (mayhem-run--live-p run))
       (mayhem-field "Triage" (format "%d test case%s queued" queued (if (= queued 1) "" "s"))))
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

(defun mayhem-run--duration (run)
  "Return how long RUN went on for, with its time limit beside it."
  (let ((real (mayhem--format-duration (alist-get 'elapsed_real_time run)))
        (limit (mayhem--format-duration (alist-get 'duration run))))
    (concat (or real "")
            (when limit
              (propertize (concat (if real "  " "") "limit " limit) 'face 'mayhem-label)))))

(defun mayhem-run--yaml-mode ()
  "Return the major mode the user gives YAML files, or nil."
  (let ((mode (assoc-default "Mayhemfile.yaml" auto-mode-alist #'string-match)))
    (when (consp mode) (setq mode (car mode)))
    (and (functionp mode) mode)))

(defun mayhem-run-show-mayhemfile (owner project target number text)
  "Show TEXT, the Mayhemfile of run NUMBER of TARGET of PROJECT of OWNER.
It is read-only, in the mode YAML files get; `q' goes back."
  (let ((buffer (get-buffer-create (format "*mayhem: %s/%s/%s/%s Mayhemfile*"
                                           owner project target number))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert text))
      (let ((mode (mayhem-run--yaml-mode)))
        (if (and mode (not (eq major-mode mode)))
            (funcall mode)
          (unless mode (fundamental-mode))))
      (goto-char (point-min))
      (set-buffer-modified-p nil)
      (view-mode 1))
    (mayhem-display-buffer buffer)))

(defun mayhem-run--mayhemfile-field (owner project target number run)
  "Return the Mayhemfile field of RUN, run NUMBER of TARGET of PROJECT of OWNER.
RET on it shows the Mayhemfile."
  (when-let* ((text (alist-get 'mayhemfile_flat run)))
    (let ((lines (length (split-string (string-trim-right text) "\n"))))
      (mayhem-field "Mayhemfile"
                    (mayhem-page-link (format "%d line%s" lines (if (= lines 1) "" "s"))
                                      "RET: view Mayhemfile"
                                      (lambda ()
                                        (mayhem-run-show-mayhemfile owner project target
                                                                    number text)))))))

(defun mayhem-run--task-face (phase)
  "Return the face of the status of PHASE, one of a run's tasks."
  (cond ((alist-get 'failed phase) 'error)
        ((alist-get 'stopped phase) 'mayhem-label)
        ((equal (alist-get 'status phase) "completed") 'success)
        ((equal (alist-get 'status phase) "running") 'warning)
        (t 'mayhem-label)))

(defun mayhem-run--task-status (phase)
  "Return the status of PHASE, one of a run's tasks, such as \"completed\"."
  (cond ((alist-get 'failed phase) "failed")
        ((alist-get 'stopped phase) "stopped")
        (t (or (alist-get 'status phase) "pending"))))

(defun mayhem-run--tasks (run)
  "Return the tasks of RUN on a line, in the order they started.
Each is coloured by how it went, with how long it took; its status
and start are its `help-echo'."
  (let ((start (alist-get 'started_at run))
        (phases (sort (copy-sequence (alist-get 'phases run))
                      (lambda (a b)
                        (let ((a (alist-get 'started_at a)) (b (alist-get 'started_at b)))
                          (and a (or (not b) (string< a b))))))))
    (mapconcat
     (lambda (phase)
       (let* ((status (mayhem-run--task-status phase))
              (from (alist-get 'started_at phase))
              (took (mayhem--format-duration
                     (or (alist-get 'elapsed_real_time phase)
                         (when-let* ((to (alist-get 'ended_at phase)) ((stringp from)))
                           (mayhem--elapsed to from)))))
              (help (concat status (when (and from start)
                                     (concat ", started at "
                                             (mayhem--format-elapsed (mayhem--elapsed from start)))))))
         (concat (propertize (mayhem-run--phase (alist-get 'phase_name phase))
                             'face (mayhem-run--task-face phase) 'help-echo help)
                 (when took (propertize (concat " " took) 'face 'mayhem-label 'help-echo help)))))
     phases "  ")))

(defun mayhem-run--pairs (pairs &optional separator)
  "Return PAIRS, an alist, as KEY VALUE lines from column 0, for copying.
SEPARATOR goes between them; without it, the values line up."
  (let ((width (apply #'max 0 (mapcar (lambda (pair) (string-width (format "%s" (car pair))))
                                      pairs))))
    (vui-text (mapconcat (pcase-lambda (`(,key . ,value))
                           (concat (if separator
                                       (format "%s%s" key separator)
                                     (string-pad (format "%s" key) (+ width 2)))
                                   (mayhem--format-value value) "\n"))
                         pairs ""))))

(defun mayhem-run--field-or-fold (key title line summary open on-open body)
  "Return the field TITLE showing LINE, or a fold of BODY if LINE is too wide.
The fold is titled TITLE and SUMMARY and named KEY; it is unfolded
when OPEN.  ON-OPEN is called with KEY and whether it is to be."
  (if (<= (+ 12 (string-width line)) (mayhem-page-width))
      (mayhem-field title line)
    (vui-fragment
     ;; The arrow and its space stand in for two of a field label's columns.
     (vui-collapsible :key key
                      :title (concat (string-pad title (max 10 (1+ (length title)))) summary)
                      :title-face 'mayhem-label :indent 0
                      :expanded open
                      :on-toggle (lambda (open) (funcall on-open key open))
                      body)
     ;; Folded, its title line has no newline of its own.
     (unless open (vui-newline)))))

(defun mayhem-run--started-with (run open on-open)
  "Return the fields of what the CLI started RUN with, beyond its Mayhemfile.
What it overrode, the environment it added and the files sent, each
on a line, or folded when too wide for one.  OPEN lists the keys of
those unfolded; ON-OPEN is as for `mayhem-run--field-or-fold'."
  (let ((overrides (alist-get 'overrides run))
        (env (alist-get 'env_vars run))
        (files (alist-get 'run_files run))
        (line (lambda (pairs separator)
                (mapconcat (pcase-lambda (`(,k . ,v)) (format "%s%s%s" k separator
                                                              (mayhem--format-value v)))
                           pairs "  ")))
        (count (lambda (n what) (format "%d %s%s" n what (if (= n 1) "" "s")))))
    (vui-fragment
     (when overrides
       (mayhem-run--field-or-fold 'overrides "Overrides" (funcall line overrides " ")
                                  (mapconcat (lambda (o) (symbol-name (car o))) overrides ", ")
                                  (memq 'overrides open) on-open (mayhem-run--pairs overrides)))
     (when env
       (mayhem-run--field-or-fold 'env "Environment" (funcall line env "=")
                                  (funcall count (length env) "variable")
                                  (memq 'env open) on-open (mayhem-run--pairs env "=")))
     (when files
       (let ((files (mapcar (lambda (f) (cons (alist-get 'path f) (alist-get 'sha256 f)))
                            files)))
         (mayhem-run--field-or-fold
          'files "Files"
          (mapconcat (pcase-lambda (`(,path . ,sha))
                       (concat path " "
                               (propertize (substring (or sha "") 0 (min 8 (length (or sha ""))))
                                           'face 'mayhem-label 'help-echo sha)))
                     files "  ")
          (funcall count (length files) "file")
          (memq 'files open) on-open (mayhem-run--pairs files)))))))

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

(defun mayhem-run--render (owner project target number data tab on-tab open on-open)
  "Return the vnodes of run NUMBER of TARGET of PROJECT of OWNER, showing DATA.
TAB is the key of the tab shown; when nil or not the run's, the
log for a failed run, which says why, else the first.  ON-TAB is
called with the key of another one, to show it.  OPEN and ON-OPEN
are for the header's folds, as in `mayhem-run--started-with'."
  (let* ((run (alist-get 'run data))
         (code (not (alist-get 'api_run run)))
         (repo (mayhem--repo (alist-get 'scm_remote_origin run)))
         (parent (alist-get 'parent_revision run))
         (start (alist-get 'started_at run))
         (queued (alist-get 'created_at run))
         (cpu (alist-get 'cputime run))
         (tabs (mayhem-run--tabs run data))
         (shown (car (or (assq tab tabs)
                         (and (alist-get 'failed run) (assq 'events tabs))
                         (car tabs))))
         (now (current-time)))
    (vui-fragment
     (mayhem-field "Status" (concat (mayhem-run-status run)
                                    (when-let* ((d (alist-get 'description run)))
                                      (propertize (concat "  " d) 'face 'mayhem-label))
                                    (when (alist-get 'has_critical_errors run)
                                      (propertize "  critical errors" 'face 'error))
                                    (when (mayhem-run--live-p run)
                                      (propertize (format "  %d of %d workers"
                                                          (or (alist-get 'current_workers run) 0)
                                                          (or (alist-get 'desired_workers run) 0))
                                                  'face 'mayhem-label))
                                    (propertize (if (alist-get 'next_run_number run)
                                                    "  next "
                                                  "  latest run")
                                                'face 'mayhem-label))
                   (when-let* ((next (alist-get 'next_run_number run)))
                     (mayhem-run-link owner project target next)))
     (mayhem-field "Started" (concat (or (mayhem--format-age start now)
                                         (concat "not yet"
                                                 (when-let* ((age (mayhem--format-age queued now)))
                                                   (propertize (concat "  queued " age)
                                                               'face 'mayhem-label))))
                                     (when-let* ((by (alist-get 'started_by run)))
                                       (propertize (concat "  by " by
                                                           (and (alist-get 'is_mayhem_bot run)
                                                                " (Mayhem bot)"))
                                                   'face 'mayhem-label))
                                     (when-let* (((and start queued))
                                                 (wait (mayhem--format-duration
                                                        (mayhem--elapsed start queued)))
                                                 ((not (equal wait "0s"))))
                                       (propertize (concat "  after " wait " queued")
                                                   'face 'mayhem-label))))
     (mayhem-field "Duration" (mayhem-run--duration run)
                   (when (and cpu (> cpu 0))
                     (propertize (concat "  " (mayhem--format-duration cpu) " CPU")
                                 'face 'mayhem-label)))
     (when (alist-get 'phases run)
       (mayhem-field "Tasks" (mayhem-run--tasks run)))
     (mayhem-hardening-field run)
     (mayhem-scm-fields run)
     (when parent
       (mayhem-field "Parent" (mayhem-repo-link repo (substring parent 0 (min 7 (length parent)))
                                                'commit parent)))
     (when-let* ((build (alist-get 'build_id run)))
       (mayhem-field "Build" (format "%s" build)))
     (mayhem-image-field run)
     (mayhem-run--mayhemfile-field owner project target number run)
     (mayhem-run--started-with run open on-open)
     (when-let* ((cli (alist-get 'cli_version run)))
       (mayhem-field "CLI" (concat "mayhem " cli)))
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
  :state ((tab nil) (open nil))
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
     (mayhem-target-page-heading (format "run #%s" number) owner project target)
     (vui-newline)
     (mayhem-snapshot-view snapshot "run" (mayhem-run--skeleton)
                           (lambda (data)
                             (mayhem-run--render owner project target number data tab
                                                 (lambda (key) (vui-set-state :tab key))
                                                 open
                                                 (lambda (key unfold)
                                                   (vui-set-state :open (if unfold
                                                                            (cons key open)
                                                                          (remq key open))))))))))

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
