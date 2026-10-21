;;; mayhem-run.el --- Run page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A run's page, `*mayhem: owner/project/target/N*': its status, commit
;; and image, and its Mayhemfile, which RET shows as a file; for a code
;; run, a chart of its progress, as the web app's run page has (folded
;; in the header once the run is done), and its
;; coverage; its defects, the first 10 until asked for all; and for a
;; code run its tests (counts and failing test cases), for an API run
;; its endpoints.  Its event log is a page of its own, `.../N/log', which
;; the Log field links to, counting its errors.  What the CLI overrode,
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
(declare-function mayhem-testcases-open "mayhem-testsuite" (owner project target run))

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

(defconst mayhem-run--defects-shown 10
  "Most defects a run's page lists until asked for all of them.")

(defun mayhem-run--defects (owner project target run defects)
  "Return the Defects section of RUN, listing DEFECTS.
RUN is a run of TARGET of PROJECT of OWNER.  It lists the first
`mayhem-run--defects-shown', and a button the rest."
  (vui-fragment
   (vui-newline)
   (mayhem-heading (format "Defects (%d)" (length defects)))
   (if (null defects)
       (mayhem-notice "No defects")
     (mayhem-defect-table owner project target defects (current-time) run
                          mayhem-run--defects-shown))))

(defun mayhem-run--endpoints (endpoints)
  "Return the Endpoints section of an API run, listing ENDPOINTS."
  (vui-fragment
   (vui-newline)
   (mayhem-heading (format "Endpoints (%d)" (length endpoints)))
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
                      endpoints))))))

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
  "Return the Coverage section of RUN, a code run, or nil with none to show."
  (when (seq-some (lambda (key) (> (or (alist-get key run) 0) 0))
                  '(n_lines_total n_blocks_total n_functions_total edges_covered tests_run))
    (vui-fragment
     (vui-newline)
     (mayhem-heading "Coverage")
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
       (mayhem-field "Engines" engines)))))

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
         (optimized (mayhem-suite-size run))
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
     (mayhem-field "All" (mayhem-page-link (format "%d test case%s" all (if (= all 1) "" "s"))
                                           "RET: open every test case"
                                           (lambda ()
                                             (mayhem-testcases-open owner project target number))))
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
and counts are its `help-echo'.  Nothing before the run starts.  While
the run goes, it is a section; once done, a `mayhem-fold' of the
header, as it no longer changes."
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
           (end (mayhem--format-elapsed span))
           (found (apply #'max 0 defects))
           (processed (format "%d test case%s processed" top (if (= top 1) "" "s")))
           (found-text (format "%d defect%s found" found (if (= found 1) "" "s")))
           (legend (propertize (concat (propertize "▆" 'face 'mayhem-target) " " processed "  "
                                       (propertize "●" 'face 'error) " " found-text)
                               'face 'mayhem-label))
           (lines (append
                   (mapcar (lambda (row)
                             (concat (propertize (format (format "%%%ds " margin)
                                                         (if (eq row (car rows)) top ""))
                                                 'face 'mayhem-label)
                                     (propertize (funcall tip row) 'face 'mayhem-target)))
                           rows)
                   (list (concat pad (propertize (funcall tip dots) 'face 'error))
                         (concat pad (propertize (concat "0:00"
                                                         (make-string (max 1 (- width 4 (length end)))
                                                                      ?\s)
                                                         end)
                                                 'face 'mayhem-label))))))
      (if (mayhem-run--live-p run)
          (vui-fragment
           (vui-newline)
           (mayhem-heading "Progress")
           (vui-text (concat pad legend "\n" (mapconcat (lambda (l) (concat l "\n")) lines ""))))
        (vui-component 'mayhem-fold
                       :title "Progress"
                       :summary (concat processed "  " found-text)
                       :parts (list (propertize (concat processed "  " found-text)
                                                'face 'mayhem-label))
                       :lines (mapcar (lambda (l) (vui-text (concat l "\n"))) lines))))))

(defconst mayhem-run--test-header
  '("Test case" "Type" "Defects" nil "Time" "Seen")
  "The names of the columns of a run's failing tests.")

(defconst mayhem-run--tests-shown 10
  "Most failing tests a run's page lists until asked for all of them.")

(defun mayhem-run--tests (owner project target number run failing)
  "Return the vnodes listing FAILING, the failing test cases of RUN.
RUN is run NUMBER of TARGET of PROJECT of OWNER.  It lists the first
`mayhem-run--tests-shown', and a button the rest."
  (let ((start (alist-get 'started_at run)))
    (vui-fragment
     (mayhem-heading (format "Failing tests (%d)" (length failing)))
     (if (null failing)
         (mayhem-notice "No failing tests")
       (let ((lines (mayhem-columns
                     (mapcar (lambda (test)
                               (let ((sha (alist-get 'sha256 test)))
                                 (list (substring sha 0 (min 8 (length sha)))
                                       (propertize (mayhem-testcase-type (alist-get 'is_regression test))
                                                   'face 'mayhem-label)
                                       (format "%d" (or (alist-get 'n_defects test) 0))
                                       (mayhem-testcase-severities test)
                                       (propertize
                                        (format "%dms" (round (* 1000 (or (alist-get 'execution_time test)
                                                                           0))))
                                        'face 'mayhem-label)
                                       (mayhem-run--elapsed-text (alist-get 'created_at test) start))))
                             failing)
                     '(2 4 5) mayhem-run--test-header)))
         (mayhem-table lines failing
                       (lambda (test)
                         (mayhem-testcase-open owner project target number (alist-get 'sha256 test)))
                       "RET: open test case" mayhem-run--tests-shown "failing tests"))))))

(vui-defcomponent mayhem-run-tests (owner project target number run)
  "The Tests section of RUN, run NUMBER of TARGET of PROJECT of OWNER.
A test case fails when it shows a defect, crash or not."
  :render
  (let ((snapshot (mayhem-sync-use-resource
                   (list 'run-testcases owner project target number))))
    (vui-fragment
     (vui-newline)
     (mayhem-heading (format "Tests (%d)" (or (alist-get 'n_testcase_reports run) 0)))
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

(defun mayhem-run--mayhemfile-link (owner project target number run text)
  "Return TEXT linking to RUN's Mayhemfile, or nil without one.
RUN is run NUMBER of TARGET of PROJECT of OWNER."
  (when-let* ((mayhemfile (alist-get 'mayhemfile_flat run)))
    (mayhem-page-link text "RET: view Mayhemfile"
                      (lambda ()
                        (mayhem-run-show-mayhemfile owner project target number mayhemfile)))))

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

(defun mayhem-run--lines (label lines)
  "Return fields showing LINES, the first labelled LABEL.
Each of LINES is a string or a list of the values of a field."
  (seq-map-indexed (lambda (line i)
                     (apply #'mayhem-field (if (= i 0) label "") (ensure-list line)))
                   lines))

(defun mayhem-run--setup (owner project target number run)
  "Return what RUN was set up with, a `mayhem-fold'.
Its build, hardening, Mayhemfile, what the CLI overrode in
it, the environment it added, the files it sent, and the CLI's
version.  Folded, the line links to the Mayhemfile and counts what
the CLI added.  RUN is run NUMBER of TARGET of PROJECT of OWNER."
  (let* ((build (alist-get 'build_id run))
         (factors (alist-get 'n_exploitability_factors_total run))
         (hardening (and factors (> factors 0)
                         (format "hardening %s/%s"
                                 (or (alist-get 'n_exploitability_factors_passing run) 0)
                                 factors)))
         (mayhemfile (alist-get 'mayhemfile_flat run))
         (overrides (alist-get 'overrides run))
         (env (alist-get 'env_vars run))
         (files (alist-get 'run_files run))
         (cli (and (alist-get 'cli_version run)
                   (concat "mayhem " (alist-get 'cli_version run))))
         (link (lambda (text) (mayhem-run--mayhemfile-link owner project target number
                                                           run text)))
         (count (lambda (items what)
                  (when items
                    (let ((n (length items)))
                      (format "%d %s%s" n what (if (= n 1) "" "s"))))))
         (grey (lambda (text) (and text (propertize text 'face 'mayhem-label))))
         (counts (delq nil (list (funcall count overrides "override")
                                 (funcall count env "variable")
                                 (funcall count files "file")
                                 hardening))))
    (when (or build hardening mayhemfile overrides env files cli)
      (vui-component
       'mayhem-fold
       :title "Setup"
       :summary (string-join (delq nil (cons (and mayhemfile "Mayhemfile") counts)) "  ")
       :parts (append (and mayhemfile (list (cons "Mayhemfile" (funcall link "Mayhemfile"))))
                      (mapcar grey counts))
       :lines
       (append
        (list (when build
                (mayhem-field "  Build" (format "%s" build)))
              (mayhem-hardening-field run "  ")
              (when mayhemfile
                (let ((lines (length (split-string (string-trim-right mayhemfile) "\n"))))
                  ;; "Mayhemfile", indented, leaves no room after the label.
                  (mayhem-field "  Config" (funcall link "Mayhemfile")
                                (funcall grey (format "  %d line%s" lines
                                                      (if (= lines 1) "" "s")))))))
        (when overrides
          (let ((width (apply #'max (mapcar (lambda (o) (length (symbol-name (car o))))
                                            overrides))))
            ;; A list, such as the tasks or test suites, goes an item a line.
            (mayhem-run--lines "  Overrides"
                               (mapcan (pcase-lambda (`(,key . ,value))
                                         (let ((items (cond ((null value) (list (funcall grey "null")))
                                                            ((and (listp value)
                                                                  (not (mayhem--object-p value)))
                                                             (mapcar #'mayhem--format-value value))
                                                            (t (list (mayhem--format-value value))))))
                                           (cons (list (string-pad (symbol-name key) (+ width 2))
                                                       (if (and (eq key 'image) (stringp value))
                                                           (mayhem-image-link value)
                                                         (car items)))
                                                 (mapcar (lambda (item)
                                                           (concat (make-string (+ width 2) ?\s) item))
                                                         (cdr items)))))
                                       overrides))))
        (when env
          (mayhem-run--lines "  Env"
                             (mapcar (pcase-lambda (`(,key . ,value))
                                       (format "%s=%s" key (mayhem--format-value value)))
                                     env)))
        (when files
          (mayhem-run--lines "  Files"
                             (mapcar (lambda (f)
                                       (let ((sha (or (alist-get 'sha256 f) "")))
                                         (concat (alist-get 'path f) "  "
                                                 (propertize (substring sha 0 (min 8 (length sha)))
                                                             'face 'mayhem-label 'help-echo sha))))
                                     files)))
        (list (when cli
                (mayhem-field "  CLI" cli))))))))

(defun mayhem-run--render (owner project target number data)
  "Return the vnodes of run NUMBER of TARGET of PROJECT of OWNER, showing DATA."
  (let* ((run (alist-get 'run data))
         (code (not (alist-get 'api_run run)))
         (start (alist-get 'started_at run))
         (queued (alist-get 'created_at run))
         (cpu (alist-get 'cputime run))
         (live (mayhem-run--live-p run))
         (now (current-time))
         (chart (when code (mayhem-run--chart run (alist-get 'progress data) now))))
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
     (mayhem-source-fold run)
     (mayhem-image-field run)
     (mayhem-run--setup owner project target number run)
     ;; A done run's chart is a fold of the header, a going run's a section.
     (unless live chart)
     (mayhem-run--log-field owner project target number (alist-get 'events data))
     (when live chart)
     (when code
       (mayhem-run--coverage run))
     (mayhem-run--defects owner project target number (alist-get 'defects data))
     (if code
         (vui-component 'mayhem-run-tests :owner owner :project project
                        :target target :number number :run run)
       (mayhem-run--endpoints (alist-get 'endpoints data))))))

(defun mayhem-run--log-field (owner project target number events)
  "Return the Log field of run NUMBER of TARGET of PROJECT of OWNER.
It links to the run's log of EVENTS, counting its errors and warnings,
which say why a run failed."
  (let* ((n (length events))
         (count (lambda (test)
                  (seq-count (lambda (e) (funcall test (or (alist-get 'event_level e) 1)))
                             events)))
         (errors (funcall count (lambda (level) (>= level 3))))
         (warnings (funcall count (lambda (level) (= level 2)))))
    (mayhem-field "Log"
                  (mayhem-page-link (format "%d event%s" n (if (= n 1) "" "s"))
                                    "RET: open the run's log"
                                    (lambda () (mayhem-run-log-open owner project target number)))
                  (when (> errors 0)
                    (propertize (format "  %d error%s" errors (if (= errors 1) "" "s"))
                                'face 'error))
                  (when (> warnings 0)
                    (propertize (format "  %d warning%s" warnings (if (= warnings 1) "" "s"))
                                'face 'warning)))))

(defun mayhem-run--skeleton ()
  "Return grey bars shaped like a run's page, shown until its data lands."
  (vui-fragment
   (mayhem-field "Status" (mayhem-skeleton-bar 22))
   (mayhem-field "Started" (mayhem-skeleton-bar 20))
   (mayhem-field "Duration" (mayhem-skeleton-bar 6))
   (mayhem-field "Source" (mayhem-skeleton-bar 30))
   (mayhem-field "Setup" (mayhem-skeleton-bar 30))
   (vui-newline)
   (mayhem-heading "Defects")
   (mayhem-skeleton '((6 " " 28) (6 " " 36) (6 " " 22) (6 " " 30)))))

(defun mayhem-run--use-run (owner project target number)
  "Return the snapshot of run NUMBER of TARGET of PROJECT of OWNER.
While the run is going, it is refetched every
`mayhem-run-refresh-interval' seconds.  Call it during render, as any
hook."
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
    snapshot))

(vui-defcomponent mayhem-run-page (owner project target number)
  "The page of run NUMBER of TARGET of PROJECT of OWNER."
  :render
  (let ((snapshot (mayhem-run--use-run owner project target number)))
    (vui-fragment
     (mayhem-target-page-heading (format "run #%s" number) owner project target)
     (vui-newline)
     (mayhem-snapshot-view snapshot "run" (mayhem-run--skeleton)
                           (lambda (data)
                             (mayhem-run--render owner project target number data))))))

(defun mayhem-run-open (owner project target number)
  "Open the page of run NUMBER of TARGET of PROJECT of OWNER."
  (mayhem-open-page (format "*mayhem: %s/%s/%s/%s*" owner project target number)
                    #'mayhem-run-mode
                    (lambda () (vui-component 'mayhem-run-page
                                              :owner owner :project project
                                              :target target :number number))
                    (list 'run owner project target number)))

(define-derived-mode mayhem-run-log-mode mayhem-page-mode "Mayhem Run Log"
  "Major mode for a Mayhem run's event log.")

(vui-defcomponent mayhem-run-log-page (owner project target number)
  "The page of the event log of run NUMBER of TARGET of PROJECT of OWNER."
  :render
  (let ((snapshot (mayhem-run--use-run owner project target number)))
    (vui-fragment
     (mayhem-target-page-heading
      (list (mayhem-run-link owner project target number nil '(link mayhem-section-heading))
            ", log")
      owner project target)
     (vui-newline)
     (mayhem-snapshot-view snapshot "run"
                           (mayhem-skeleton (make-list 8 '(8 "  " 14 "  " 40)))
                           (lambda (data) (mayhem-run--events (alist-get 'events data)))))))

(defun mayhem-run-log-open (owner project target number)
  "Open the event log of run NUMBER of TARGET of PROJECT of OWNER."
  (mayhem-open-page (format "*mayhem: %s/%s/%s/%s/log*" owner project target number)
                    #'mayhem-run-log-mode
                    (lambda () (vui-component 'mayhem-run-log-page
                                              :owner owner :project project
                                              :target target :number number))
                    (list 'run-log owner project target number)))

(provide 'mayhem-run)
;;; mayhem-run.el ends here
