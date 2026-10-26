;;; fixtures.el --- Made-up Mayhem data for screenshots.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; Every resource the pages of docs/screenshots/README.md read, keyed by its spec,
;; each in the shape its fetch in mayhem-core.el gives.  All of it is
;; invented: the acme workspace, its projects, people and hashes.
;; Times are seconds before `mayhem-screenshots-now', so pages read the
;; same whenever they are shot.
;;
;; To show a page with other data, change its resource here; to add a
;; page, add the resources `make screenshots' says it lacks.

;;; Code:

(require 'seq)
(require 'iso8601)
(require 'mayhem-core)

(defvar mayhem-screenshots-now (encode-time (iso8601-parse "2026-10-23T12:00:00Z"))
  "The time the screenshots are taken at.")

(defconst mayhem-screenshots--h 3600)
(defconst mayhem-screenshots--d 86400)

(defun mayhem-screenshots--ago (seconds)
  "Return the timestamp SECONDS before `mayhem-screenshots-now'.
In the API's format."
  (format-time-string "%Y-%m-%dT%H:%M:%S.000000+00:00"
                      (time-subtract mayhem-screenshots-now seconds) t))

(defun mayhem-screenshots--sha (seed)
  "Return a made-up sha256, the same for the same SEED."
  (secure-hash 'sha256 seed))

(defun mayhem-screenshots--merge (alist overrides)
  "Return ALIST with the fields of OVERRIDES, a plist, put in."
  (let ((result (copy-alist alist)))
    (while overrides
      (setf (alist-get (intern (substring (symbol-name (pop overrides)) 1)) result)
            (pop overrides)))
    result))

;;;; The acme workspace

(defconst mayhem-screenshots--repo "https://github.com/acme/libpng")
(defconst mayhem-screenshots--image "ghcr.io/acme/libpng-fuzz:main")

(defun mayhem-screenshots--project (owner slug name high medium low updated)
  "Return project SLUG of OWNER, as `mayhem--project-summary' gives it."
  `((owner . ,owner) (slug . ,slug) (project_name . ,name)
    (n_defects_active_high . ,high) (n_defects_active_medium . ,medium)
    (n_defects_active_low . ,low) (updated_at . ,(mayhem-screenshots--ago updated))))

(defun mayhem-screenshots--workspace-target (owner project slug type &optional archived)
  "Return target SLUG of PROJECT of OWNER, as a workspace's list gives it."
  `((owner . ,owner) (project_slug . ,project) (slug . ,slug) (target_name . ,slug)
    (type . ,type) (is_archived . ,archived)))

(defun mayhem-screenshots--target-run (number ago &rest fields)
  "Return run NUMBER of fuzz-png, made AGO seconds ago.
In the shape `mayhem--target-run' gives.  FIELDS, a plist, override
its defaults: a finished run with defects."
  (mayhem-screenshots--merge
   `((run_number . ,number) (pending) (started . t) (stopped) (ended . t) (failed)
     (n_defects . 4) (branch_name . "main") (created_at . ,(mayhem-screenshots--ago ago))
     (started_by . "srivera") (n_testcase_reports . 214) (n_crash_reports . 37)
     (n_optimized_set_testcases . 96) (n_exploitability_factors_passing . 3)
     (n_exploitability_factors_total . 4) (scm_remote_origin . ,mayhem-screenshots--repo)
     (docker_pullable . ,mayhem-screenshots--image)
     (fetched_docker_image_digest
      . ,(concat "ghcr.io/acme/libpng-fuzz@sha256:" (mayhem-screenshots--sha "image")))
     (edges_covered . 14822) (tests_per_second . 5203.9)
     (n_lines_covered . 6412) (n_lines_total . 9875) (n_defects_active_high . 2)
     (n_defects_active_medium . 2) (n_defects_active_low . 0))
   fields))

(defconst mayhem-screenshots--target-runs
  (let ((h mayhem-screenshots--h) (d mayhem-screenshots--d))
    (list (mayhem-screenshots--target-run 42 (* 2 h))
          (mayhem-screenshots--target-run 41 (* 1 d) :branch_name "png-text-chunks"
                                          :started_by "mchen" :n_lines_covered 6398
                                          :edges_covered 14790 :tests_per_second 4870.2)
          (mayhem-screenshots--target-run 40 (* 2 d) :n_defects 5 :n_defects_active_high 3
                                          :n_lines_covered 6211 :edges_covered 14315)
          (mayhem-screenshots--target-run 39 (* 3 d) :ended nil :failed t :n_defects 0
                                          :n_testcase_reports 0 :n_crash_reports 0
                                          :n_defects_active_high 0
                                          :n_defects_active_medium 0
                                          :n_lines_covered nil :n_lines_total nil
                                          :edges_covered nil :tests_per_second nil)
          (mayhem-screenshots--target-run 38 (* 5 d) :branch_name "apng-frames"
                                          :started_by "mchen" :n_defects 3
                                          :n_defects_active_high 1 :n_lines_covered 6020
                                          :edges_covered 13902 :tests_per_second 812.4)
          (mayhem-screenshots--target-run 37 (* 8 d) :n_defects 3 :n_defects_active_high 1
                                          :n_lines_covered 5874 :edges_covered 13540)
          (mayhem-screenshots--target-run 36 (* 12 d) :ended nil :stopped t :n_defects 1
                                          :n_defects_active_high 0 :n_defects_active_medium 1
                                          :n_lines_covered 4410 :edges_covered 9876
                                          :tests_per_second 12640.5)
          (mayhem-screenshots--target-run 35 (* 15 d) :n_defects 2 :n_defects_active_high 0
                                          :n_lines_covered 5702 :edges_covered 12988)))
  "The runs of fuzz-png, newest first.")

(defun mayhem-screenshots--defect (number title severity level cwe ago run &optional state)
  "Return defect NUMBER of fuzz-png, as `mayhem--target-defect' gives it."
  `((defect_number . ,number) (title . ,title) (severity . ,severity)
    (severity_level . ,level) (state . ,(or state "open")) (cwe_number . ,cwe)
    (last_seen . ,(mayhem-screenshots--ago ago)) (last_seen_run_number . ,run)))

(defconst mayhem-screenshots--defects
  (let ((h mayhem-screenshots--h) (d mayhem-screenshots--d))
    (list (mayhem-screenshots--defect 12 "Out-of-bounds Read" 8.2 "high" 125 (* 2 h) 42)
          (mayhem-screenshots--defect 13 "Integer Overflow or Wraparound" 7.5 "high" 190
                                      (* 2 h) 42)
          (mayhem-screenshots--defect 10 "Uncontrolled Resource Consumption" 6.5 "medium" 400
                                      (* 2 h) 42)
          (mayhem-screenshots--defect 9 "NULL Pointer Dereference" 5.9 "medium" 476
                                      (* 2 h) 42)
          (mayhem-screenshots--defect 8 "Divide By Zero" 5.5 "medium" 369 (* 8 d) 37 "fixed")
          (mayhem-screenshots--defect 5 "Use of Uninitialized Variable" 3.3 "low" 457
                                      (* 15 d) 35 "fixed")))
  "The defects of fuzz-png, most severe first.")

(defun mayhem-screenshots--trend (start end)
  "Return 31 daily points of a defect trend, going from START to END.
Each is a list (HIGH MEDIUM LOW) of active defects."
  (mapcar (lambda (i)
            (let ((f (/ i 30.0)))
              `((timestamp . ,(mayhem-screenshots--ago (* (- 30 i) mayhem-screenshots--d)))
                ,@(seq-mapn (lambda (key a b)
                              ;; A step a third of the way, another two thirds.
                              (cons key (cond ((< f 0.33) a)
                                              ((< f 0.66) (round (/ (+ a a b) 3.0)))
                                              (t b))))
                            '(active_high active_medium active_low) start end)
                (fixed . ,(round (* 10 f))))))
          (number-sequence 0 30)))

;;;; Run 42 of fuzz-png

(defconst mayhem-screenshots--run-start (* 2 mayhem-screenshots--h)
  "Seconds before now that run 42 started.")

(defun mayhem-screenshots--run-at (seconds)
  "Return the timestamp SECONDS into run 42."
  (mayhem-screenshots--ago (- mayhem-screenshots--run-start seconds)))

(defconst mayhem-screenshots--mayhemfile
  "project: acme/libpng
target: fuzz-png
image: ghcr.io/acme/libpng-fuzz:main
duration: 3600
cmds:
  - cmd: /out/png_read_fuzzer @@
    libfuzzer: true
    sanitizer: true
")

(defconst mayhem-screenshots--run
  `((run_id . 90042) (run_number . 42) (description . "Run Completed") (pending)
    (started . t) (stopped) (ended . t) (failed)
    (started_at . ,(mayhem-screenshots--run-at 0))
    (ended_at . ,(mayhem-screenshots--run-at 3712)) (duration . 3600)
    (started_by . "srivera") (scm_remote_origin . ,mayhem-screenshots--repo)
    (branch_name . "main") (merge_base_branch_name)
    (revision . ,(substring (mayhem-screenshots--sha "commit 42") 0 40))
    (scm_commit_subject . "Check chunk length before reading IDAT")
    (scm_commit_author . "Sam Rivera") (scm_commit_author_email . "sam@acme.example")
    (ci_type . "github")
    (ci_url . "https://github.com/acme/libpng/actions/runs/7700042")
    (n_defects . 4) (tests_run . 18734211) (tests_per_second . 5203.9)
    (edges_covered . 14822) (api_run) (docker_pullable . ,mayhem-screenshots--image)
    (fetched_docker_image_digest
     . ,(concat "ghcr.io/acme/libpng-fuzz@sha256:" (mayhem-screenshots--sha "image")))
    (n_exploitability_factors_passing . 3) (n_exploitability_factors_total . 4)
    (n_testcase_reports . 214) (n_regression_testcase_reports . 88)
    (n_regression_defect_reports . 2) (n_optimized_set_testcases . 96)
    (elapsed_real_time . 3712) (cputime . 29410)
    (created_at . ,(mayhem-screenshots--run-at -6))
    (updated_at . ,(mayhem-screenshots--run-at 3712)) (build_id . "7700042")
    (cli_version . "2.14.1")
    (parent_revision . ,(substring (mayhem-screenshots--sha "commit 41") 0 40))
    (is_mayhem_bot) (has_critical_errors)
    (mayhemfile_flat . ,mayhem-screenshots--mayhemfile)
    (overrides (duration . 3600))
    (env_vars (ASAN_OPTIONS . "detect_leaks=0"))
    (run_files ((path . "Mayhemfile") (sha256 . ,(mayhem-screenshots--sha "Mayhemfile"))))
    (phases
     ((phase_name . "regression_testing") (status . "completed") (failed) (stopped)
      (started_at . ,(mayhem-screenshots--run-at 4)) (ended_at . ,(mayhem-screenshots--run-at 61))
      (elapsed_real_time . 57))
     ((phase_name . "dynamic_analysis") (status . "completed") (failed) (stopped)
      (started_at . ,(mayhem-screenshots--run-at 62))
      (ended_at . ,(mayhem-screenshots--run-at 3662)) (elapsed_real_time . 3600))
     ((phase_name . "static_analysis") (status . "completed") (failed) (stopped)
      (started_at . ,(mayhem-screenshots--run-at 3663))
      (ended_at . ,(mayhem-screenshots--run-at 3690)) (elapsed_real_time . 27))
     ((phase_name . "coverage_analysis") (status . "completed") (failed) (stopped)
      (started_at . ,(mayhem-screenshots--run-at 3691))
      (ended_at . ,(mayhem-screenshots--run-at 3712)) (elapsed_real_time . 21)))
    (next_run_number) (tests_run_mfuzz . 6120455) (tests_run_libfuzz . 11890231)
    (tests_run_honggfuzz) (tests_run_symexec . 723525) (current_workers . 0)
    (desired_workers . 0) (n_desired_cpu . 8) (n_desired_memory . 16384)
    (n_crash_reports . 37) (n_behavior_crash_reports . 35) (n_regression_crash_reports . 2)
    (n_valgrind_errors . 3) (n_behavior_valgrind_errors . 3) (n_regression_valgrind_errors . 0)
    (n_starting_testcases . 88) (n_lines_covered . 6412) (n_lines_total . 9875)
    (n_blocks_covered . 11208) (n_blocks_total . 17630) (n_functions_covered . 512)
    (n_functions_total . 688) (n_defects_active_high . 2) (n_defects_active_medium . 2)
    (n_defects_active_low . 0) (n_defects_fixed_high . 1) (n_defects_fixed_medium . 1)
    (n_defects_fixed_low . 0) (n_optimized_testsuite_size . 96) (n_total_testsuite_size . 214)
    (triage_queue_size . 0) (n_initial_coverage_collection_processed . 88)
    (n_initial_coverage_collection_total . 88))
  "Run 42 of fuzz-png, as `mayhem--run-summary' gives it.")

(defconst mayhem-screenshots--events
  (mapcar (pcase-lambda (`(,at ,level ,phase ,desc))
            `((created_at . ,(mayhem-screenshots--run-at at)) (event_level . ,level)
              (event_phase . ,phase) (event_desc . ,desc)))
          ;; Newest first, as the API lists them.
          '((3712 1 nil "Run completed.")
            (3705 0 "coverage_analysis" "Coverage collected: 6412 of 9875 lines.")
            (3691 1 "coverage_analysis" "Coverage analysis started.")
            (3688 1 "static_analysis" "Exploitability: 3 of 4 factors passing.")
            (3663 1 "static_analysis" "Exploitability analysis started.")
            (3662 1 "dynamic_analysis" "Behavior testing finished: 18734211 tests.")
            (2950 2 "dynamic_analysis"
                  "Test case took longer than 5s to run; it was skipped.")
            (1807 1 "dynamic_analysis" "New defect: Integer Overflow or Wraparound (CWE-190).")
            (912 1 "dynamic_analysis" "New defect: Out-of-bounds Read (CWE-125).")
            (240 0 "dynamic_analysis" "Mayhem-fuzz process launched.")
            (63 0 "dynamic_analysis" "libFuzzer process launched.")
            (62 1 "dynamic_analysis" "Behavior testing started.")
            (61 1 "regression_testing" "Regression testing finished: 88 test cases, 2 defects.")
            (4 1 "regression_testing" "Regression testing started.")
            (0 0 nil "Image pulled: ghcr.io/acme/libpng-fuzz:main.")))
  "The events of run 42.")

(defconst mayhem-screenshots--progress
  (let ((points (number-sequence 0 3600 300)))
    `((testcases . ,(mapcar (lambda (s)
                              (cons (mayhem-screenshots--run-at (+ 62 s))
                                    (round (* 214 (sqrt (/ s 3600.0))))))
                            points))
      (defects . ,(mapcar (lambda (s)
                            (cons (mayhem-screenshots--run-at (+ 62 s))
                                  (cond ((< s 900) 2) ((< s 1800) 3) (t 4))))
                          points))))
  "The test cases processed and defects found by run 42 over time.")

(defconst mayhem-screenshots--testcase-sha
  "5f2c9e0a8b1d4c7e3f6a9b2c5d8e1f4a7b0c3d6e9f2a5b8c1d4e7f0a3b6c9d2e"
  "The test case of run 42 shown on its page.")

(defconst mayhem-screenshots--run-testcases
  (let ((n 0))
    (mapcar (pcase-lambda (`(,source ,regression ,high ,medium ,time ,at))
              (setq n (1+ n))
              `((source . ,source)
                (sha256 . ,(if (= n 1) mayhem-screenshots--testcase-sha
                             (mayhem-screenshots--sha (format "testcase %d" n))))
                (is_regression . ,regression) (n_defects . ,(+ high medium))
                (execution_time . ,time) (created_at . ,(mayhem-screenshots--run-at at))
                (high . ,high) (medium . ,medium) (low . 0)))
            '(("libfuzzer" nil 1 0 0.041 912)
              ("mayhem" nil 1 0 0.118 1807)
              ("libfuzzer" nil 0 1 2.304 2950)
              ("libfuzzer" nil 0 0 0.012 2741)
              ("mayhem" nil 0 0 0.087 2210)
              ("symexec" nil 0 0 0.233 1654)
              ("libfuzzer" nil 0 0 0.009 1290)
              ("mayhem" nil 0 1 0.064 640)
              ("libfuzzer" nil 0 0 0.015 301)
              ("regression" t 1 0 0.038 30)
              ("regression" t 0 1 0.052 22)
              ("regression" t 0 0 0.007 15)
              ("regression" t 0 0 0.011 9))))
  "The test cases of run 42, newest first.")

(defconst mayhem-screenshots--testsuite
  `((live)
    (files . ,(mapcar (pcase-lambda (`(,seed ,size ,preview))
                        (list (mayhem-screenshots--sha seed) size preview))
                      '(("suite 1" 8192 ".PNG........IHDR.......@...")
                        ("suite 2" 1311 ".PNG........IHDR...........")
                        ("suite 3" 642 ".PNG........IHDR.....tEXtCo")
                        ("suite 4" 377 ".PNG........IHDR.......IDAT")
                        ("suite 5" 96 ".PNG........IHDR....acTL...")
                        ("suite 6" 45 ".PNG........IHDR...."))))))

(defconst mayhem-screenshots--frames
  '((("png_read_IDAT_data" . "pngrutil.c:4182:17"))
    (("png_read_row" . "pngread.c:528:4"))
    (("png_read_image" . "pngread.c:742:10"))
    (("LLVMFuzzerTestOneInput" . "contrib/oss-fuzz/libpng_read_fuzzer.cc:182:3"))
    (("fuzzer::Fuzzer::ExecuteCallback" . nil)))
  "The frames of the out-of-bounds read, innermost first.")

(defconst mayhem-screenshots--backtrace
  "==17==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x6020000000f1
READ of size 1 at 0x6020000000f1 thread T0
    #0 0x55d1c3a2 in png_read_IDAT_data pngrutil.c:4182:17
    #1 0x55d1b0f4 in png_read_row pngread.c:528:4
    #2 0x55d1a8e1 in png_read_image pngread.c:742:10
    #3 0x55d0f5c3 in LLVMFuzzerTestOneInput libpng_read_fuzzer.cc:182:3")

(defconst mayhem-screenshots--repro
  "MAYHEM_TRIAGING=1 /out/png_read_fuzzer /testsuite/5f2c9e0a")

;;;; The billing-api API target

(defun mayhem-screenshots--api-run ()
  "Return run 7 of billing-api's api target, as `mayhem--run-summary' gives it."
  (mayhem-screenshots--merge
   mayhem-screenshots--run
   `(:run_id 90007 :run_number 7 :api_run t :duration 1800 :elapsed_real_time 1841
             :cputime 3620 :tests_run 48210 :tests_per_second 26.2 :edges_covered nil
             :n_defects 3 :n_testcase_reports nil :n_regression_testcase_reports nil
             :n_crash_reports nil :n_optimized_set_testcases nil
             :n_lines_covered nil :n_lines_total nil :n_blocks_covered nil
             :n_blocks_total nil :n_functions_covered nil :n_functions_total nil
             :n_valgrind_errors nil :tests_run_mfuzz nil :tests_run_libfuzz nil
             :tests_run_symexec nil
             :scm_remote_origin "https://github.com/acme/billing-api"
             :revision ,(substring (mayhem-screenshots--sha "api commit") 0 40)
             :parent_revision nil
             :scm_commit_subject "Validate invoice amounts on update"
             :scm_commit_author "Mei Chen" :scm_commit_author_email "mei@acme.example"
             :ci_url "https://github.com/acme/billing-api/actions/runs/7700007"
             :build_id "7700007"
             :docker_pullable "ghcr.io/acme/billing-api:main"
             :fetched_docker_image_digest
             ,(concat "ghcr.io/acme/billing-api@sha256:" (mayhem-screenshots--sha "api image"))
             :mayhemfile_flat "project: acme/billing-api
target: api
http:
  url: http://localhost:8080
  openapi: /openapi.json
duration: 1800
"
             :overrides nil :env_vars nil :started_by "mchen"
             :n_exploitability_factors_passing nil :n_exploitability_factors_total nil
             :n_defects_active_high 1
             :n_defects_active_medium 2 :phases nil)))

(defconst mayhem-screenshots--api-request
  "PUT /invoices/1042 HTTP/1.1
Host: localhost:8080
Content-Type: application/json

{\"amount\": \"1e309\", \"currency\": \"USD\"}")

(defconst mayhem-screenshots--api-response
  "HTTP/1.1 500 Internal Server Error
Content-Type: application/json

{\"error\": \"internal\", \"detail\": \"OverflowError: cannot convert float infinity to integer\"}")

;;;; Fixtures

(defvar mayhem-screenshots-fixtures
  (let* ((h mayhem-screenshots--h) (d mayhem-screenshots--d)
         (latest (car mayhem-screenshots--target-runs))
         (oob (car mayhem-screenshots--defects)))
    `(((me)
       . ((slug . "jdoe") (username . "jdoe") (first_name . "Jane") (last_name . "Doe")))

      ((projects)
       . (,(mayhem-screenshots--project "acme" "libpng" "libpng" 2 2 0 (* 2 h))
          ,(mayhem-screenshots--project "acme" "billing-api" "Billing API" 1 2 0 (* 3 d))
          ,(mayhem-screenshots--project "acme" "zlib" "zlib" 0 0 0 (* 40 d))
          ,(mayhem-screenshots--project "jdoe" "sandbox" "Sandbox" 0 1 0 (* 9 d))))

      ((workspace-targets "acme")
       . (,(mayhem-screenshots--workspace-target "acme" "libpng" "fuzz-png" "code")
          ,(mayhem-screenshots--workspace-target "acme" "libpng" "fuzz-apng" "code")
          ,(mayhem-screenshots--workspace-target "acme" "libpng" "legacy-reader" "code" t)
          ,(mayhem-screenshots--workspace-target "acme" "billing-api" "api" "api")
          ,(mayhem-screenshots--workspace-target "acme" "zlib" "inflate" "code")))

      ((project "acme" "libpng")
       . ((project (default_branch . "main") (repository_url . ,mayhem-screenshots--repo)
                   (updated_at . ,(mayhem-screenshots--ago (* 2 h)))
                   (n_defects_active_high . 2) (n_defects_active_medium . 2)
                   (n_defects_active_low . 0) (n_defects_fixed_high . 3)
                   (n_defects_fixed_medium . 5) (n_defects_fixed_low . 2))
          (totals (runs . 97) (targets . 3) (latest_targets_passing_tests . 1))
          (targets
           ((latest . ,latest) (slug . "fuzz-png") (target_name . "fuzz-png")
            (type . "code") (is_archived) (n_runs . 42))
           ((latest . ,(mayhem-screenshots--target-run
                        51 (* 6 h) :n_defects 0 :n_defects_active_high 0
                        :n_testcase_reports 120 :n_crash_reports 0
                        :n_defects_active_medium 0 :n_lines_covered 3120
                        :n_lines_total 4410))
            (slug . "fuzz-apng") (target_name . "fuzz-apng") (type . "code")
            (is_archived) (n_runs . 51))
           ((latest . ,(mayhem-screenshots--target-run
                        4 (* 200 d) :n_defects 1 :n_defects_active_high 0
                        :n_defects_active_medium 0 :n_defects_active_low 1))
            (slug . "legacy-reader") (target_name . "legacy-reader") (type . "code")
            (is_archived . t) (n_runs . 4)))))

      ((defect-trend "acme" "libpng" nil month)
       . ,(mayhem-screenshots--trend '(4 3 1) '(2 2 0)))

      ((defect-trend "acme" "libpng" "fuzz-png" month)
       . ,(mayhem-screenshots--trend '(3 3 1) '(2 2 0)))

      ((target "acme" "libpng" "fuzz-png")
       . ((target (type . "code") (url) (updated_at . ,(mayhem-screenshots--ago (* 2 h))))
          (latest . ,latest)
          (runs (count . 42) (runs . ,(seq-take mayhem-screenshots--target-runs 5)))
          (defects (count . ,(length mayhem-screenshots--defects))
                   (defects . ,(seq-take mayhem-screenshots--defects 5)))))

      ((target-runs "acme" "libpng" "fuzz-png") . ,mayhem-screenshots--target-runs)

      ((target-defects "acme" "libpng" "fuzz-png") . ,mayhem-screenshots--defects)

      ((run "acme" "libpng" "fuzz-png" 42)
       . ((run . ,mayhem-screenshots--run)
          (defects . ,(seq-take mayhem-screenshots--defects 4))
          (endpoints)
          (events . ,mayhem-screenshots--events)
          (progress . ,mayhem-screenshots--progress)))

      ((run-testcases "acme" "libpng" "fuzz-png" 42) . ,mayhem-screenshots--run-testcases)

      ((testsuite "acme" "libpng" "fuzz-png" 42) . ,mayhem-screenshots--testsuite)

      ((defect "acme" "libpng" "fuzz-png" 12 42)
       . ((defect (defect_number . 12) (title . "Out-of-bounds Read") (severity . 8.2)
                  (severity_level . "high") (state . "open") (source . "code")
                  (cwe_number . 125) (cwe_type . "Out-of-bounds Read")
                  (cwe_link . "https://cwe.mitre.org/data/definitions/125.html")
                  (defect_class_name . "improper-memory-access")
                  (description . "The product reads data past the end, or before the beginning, of the intended buffer.")
                  (first_seen . ,(mayhem-screenshots--ago (* 5 d)))
                  (last_seen . ,(alist-get 'last_seen oob)) (last_seen_run_number . 42))
          (run . 42)
          (evidence (count . 3) (sha256 . ,mayhem-screenshots--testcase-sha) (run_number . 42)
                    (crash_type . "heap-buffer-overflow") (signal_number . 6)
                    (repro_cmdline . ,mayhem-screenshots--repro)
                    (frames . ,mayhem-screenshots--frames)
                    (backtrace . ,mayhem-screenshots--backtrace)
                    (testcases ((sha256 . ,mayhem-screenshots--testcase-sha) (run_number . 42)
                                (execution_time . 0.041))
                               ((sha256 . ,(mayhem-screenshots--sha "oob 2")) (run_number . 40)
                                (execution_time . 0.037))
                               ((sha256 . ,(mayhem-screenshots--sha "oob 3")) (run_number . 38)
                                (execution_time . 0.052))))
          (scm . ,(seq-filter (lambda (field) (memq (car field) mayhem--scm-fields))
                              mayhem-screenshots--run))))

      ((testcase "acme" "libpng" "fuzz-png" 42 ,mayhem-screenshots--testcase-sha)
       . ((testcase (sha256 . ,mayhem-screenshots--testcase-sha) (is_regression)
                    (crashed . t) (crash_type . "heap-buffer-overflow") (signal_number . 6)
                    (faulting_address . "0x6020000000f1") (n_valgrind_errors . 0)
                    (execution_time . 0.041) (created_at . ,(mayhem-screenshots--run-at 912))
                    (repro_cmdline . ,mayhem-screenshots--repro)
                    (hexdump . "00000000: 8950 4e47 0d0a 1a0a 0000 000d 4948 4452  .PNG........IHDR
00000010: 0000 0010 0000 0010 0806 0000 001f f3ff  ................
00000020: 6100 0000 ff49 4441 5478 9c63 6000 0200  a....IDATx.c`...
00000030: 0005 0001                                ....")
                    (output . "Standard Out: (empty)

Standard Error:
==17==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x6020000000f1")
                    (testcase_source . "libfuzzer")
                    (defects ,oob)
                    (frames . ,mayhem-screenshots--frames)
                    (backtrace . ,mayhem-screenshots--backtrace))
          (run (started_at . ,(mayhem-screenshots--run-at 0)))))

      ((run "acme" "billing-api" "api" 7)
       . ((run . ,(mayhem-screenshots--api-run))
          (defects ,(mayhem-screenshots--defect 3 "Internal Server Error" 7.5 "high" 755 (* 3 d) 7)
                   ,(mayhem-screenshots--defect 4 "Authentication Bypass" 6.5 "medium" 287
                                                (* 3 d) 7)
                   ,(mayhem-screenshots--defect 2 "Verbose Error Messages" 5.3 "medium" 209
                                                (* 3 d) 7))
          (endpoints
           ((method . "GET") (path . "/invoices") (passing . t) (covered . t) (defects_total . 0))
           ((method . "POST") (path . "/invoices") (passing . t) (covered . t) (defects_total . 0))
           ((method . "GET") (path . "/invoices/{id}") (passing) (covered . t) (defects_total . 1))
           ((method . "PUT") (path . "/invoices/{id}") (passing) (covered . t) (defects_total . 2))
           ((method . "DELETE") (path . "/invoices/{id}") (passing . t) (covered . t)
            (defects_total . 0))
           ((method . "GET") (path . "/health") (passing . t) (covered) (defects_total . 0)))
          (events . ,(seq-take mayhem-screenshots--events 3))
          (progress)))

      ((defect "acme" "billing-api" "api" 3 7)
       . ((defect (defect_number . 3) (title . "Internal Server Error") (severity . 7.5)
                  (severity_level . "high") (state . "open") (source . "api")
                  (cwe_number . 755)
                  (cwe_type . "Improper Handling of Exceptional Conditions")
                  (cwe_link . "https://cwe.mitre.org/data/definitions/755.html")
                  (defect_class_name . "internal-server-error")
                  (description . "The server answered 500 to a request it should have refused.")
                  (first_seen . ,(mayhem-screenshots--ago (* 3 d)))
                  (last_seen . ,(mayhem-screenshots--ago (* 3 d))) (last_seen_run_number . 7))
          (run . 7)
          (evidence (method . "PUT") (path . "/invoices/{id}")
                    (endpoint_name . "update_invoice")
                    (stacktrace . "app/invoices.py:88 in update_invoice
    amount = int(float(body[\"amount\"]) * 100)
app/server.py:41 in dispatch
    return handler(request)")
                    (request . ,mayhem-screenshots--api-request)
                    (response . ,mayhem-screenshots--api-response))
          (scm . ,(seq-filter (lambda (field) (memq (car field) mayhem--scm-fields))
                              (mayhem-screenshots--api-run)))))))
  "Each resource's spec and its data.")

(provide 'fixtures)
;;; fixtures.el ends here
