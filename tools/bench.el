;;; bench.el --- Time mayhem-jump's search on a large made-up store  -*- lexical-binding: t; -*-
;; Assisted-by: Claude:claude-opus-5-5

;;; Commentary:

;; Run by `make bench', through `eldev exec', so mayhem and vui load.
;; It fills a store with made-up workspaces, projects and targets, then
;; times each step `mayhem-jump' takes before its prompt opens
;; (`mayhem-doctor-search-timings'), and what a fetch landing behind the
;; prompt costs.  It does so twice: with targets as they are stored now,
;; and untrimmed, with each target's whole API alist, as they were
;; stored before `mayhem--target-summary'.
;;
;; BENCH_WORKSPACES, BENCH_PROJECTS and BENCH_TARGETS set the sizes;
;; BENCH_RUNS how many times each is timed, the median shown.

;;; Code:

(require 'mayhem)

(defun mayhem-bench--env (name default)
  "Return the number in the environment variable NAME, else DEFAULT."
  (let ((value (getenv name)))
    (if (and value (not (string-empty-p value))) (string-to-number value) default)))

(defconst mayhem-bench--workspaces (mayhem-bench--env "BENCH_WORKSPACES" 20))
(defconst mayhem-bench--projects (mayhem-bench--env "BENCH_PROJECTS" 400))
(defconst mayhem-bench--targets (mayhem-bench--env "BENCH_TARGETS" 4000))
(defconst mayhem-bench--runs (mayhem-bench--env "BENCH_RUNS" 5))

(defun mayhem-bench--target (owner project slug)
  "Return target SLUG of PROJECT of OWNER, made up, as the API gives it."
  `((owner . ,owner) (project_slug . ,project) (slug . ,slug) (target_name . ,slug)
    (type . ,(if (zerop (% (length slug) 4)) "api" "code")) (is_archived)
    (description . ,(make-string 200 ?d))
    (repository_url . ,(format "https://git.example.com/%s/%s.git" owner project))
    (created_at . "2026-01-02T03:04:05.000000+00:00")
    (updated_at . "2026-02-03T04:05:06.000000+00:00")
    (latest_run (run_number . 42) (status . "completed") (n_defects . 3)
                (n_defects_active_high . 1) (n_defects_active_medium . 1)
                (n_defects_active_low . 1) (branch_name . "main") (started_by . "jdoe")
                (created_at . "2026-02-03T04:05:06.000000+00:00") (duration . 3600)
                (n_testcase_reports . 214) (n_crash_reports . 37)
                (n_lines_covered . 3120) (n_lines_total . 4410))
    (settings (engine . "default") (timeout . 30) (memory_limit . 4096)
              (cmds ((cmd . "/bin/target @@") (env) (network) (libfuzzer . :false))))))

(defun mayhem-bench--data (untrimmed)
  "Return made-up (PROJECTS . TARGETS), TARGETS an alist of owner to targets.
With UNTRIMMED, each target is its whole API alist."
  (let (projects targets)
    (dotimes (p mayhem-bench--projects)
      (let ((owner (format "workspace-%02d" (% p mayhem-bench--workspaces)))
            (slug (format "project-%03d" p)))
        (push `((owner . ,owner) (slug . ,slug) (project_name . ,slug)
                (n_defects_active_high . 1) (n_defects_active_medium . 2)
                (n_defects_active_low . 0) (updated_at . "2026-02-03T04:05:06Z"))
              projects)))
    (setq projects (nreverse projects))
    (dotimes (i mayhem-bench--targets)
      (let* ((project (nth (% i mayhem-bench--projects) projects))
             (owner (alist-get 'owner project))
             (target (mayhem-bench--target owner (alist-get 'slug project)
                                           (format "target-%04d" i)))
             (cell (or (assoc owner targets) (car (push (list owner) targets)))))
        (push (if untrimmed target (mayhem--target-summary target)) (cdr cell))))
    (cons projects (mapcar (lambda (cell) (cons (car cell) (nreverse (cdr cell)))) targets))))

(defun mayhem-bench--fill (db data)
  "Store DATA, from `mayhem-bench--data', in DB."
  (let ((now (float-time)))
    (mayhem-sync--write db (mayhem-sync-spec-key '(projects)) (car data) now)
    (pcase-dolist (`(,owner . ,targets) (cdr data))
      (mayhem-sync--write db (mayhem-sync-spec-key (list 'workspace-targets owner)) targets now))))

(defun mayhem-bench--landing (db data)
  "Time a fetch of the first workspace's targets landing in DB, from DATA.
Return the timings of storing it and of search re-reading it."
  (pcase-let* ((`(,owner . ,targets) (cadr data))
               (key (mayhem-sync-spec-key (list 'workspace-targets owner)))
               ;; Data unlike what is stored, so the write isn't skipped as unchanged.
               (changed (append targets (list (car targets)))))
    (list :store (mayhem-doctor--time
                  (lambda () (mayhem-sync--write db key changed (float-time))))
          :reread (mayhem-doctor--time (lambda () (mayhem-search--targets owner))))))

(defun mayhem-bench--median (numbers)
  "Return the median of NUMBERS."
  (nth (/ (length numbers) 2) (sort (copy-sequence numbers) #'<)))

(defun mayhem-bench--scenario (untrimmed)
  "Time the search on a store of made-up data, UNTRIMMED or not.
Return an alist of each step's label to its median seconds, and the
store's size."
  (let* ((file (make-temp-file "mayhem-bench" nil ".sqlite"))
         (data (mayhem-bench--data untrimmed))
         (mayhem-sync--db (mayhem-sync--create (sqlite-open file)))
         (mayhem-sync-change-functions nil)
         (mayhem-sync-loading-functions nil)
         runs)
    (unwind-protect
        (progn
          (mayhem-bench--fill mayhem-sync--db data)
          (dotimes (_ mayhem-bench--runs)
            (garbage-collect)
            (push (append (mayhem-doctor-search-timings)
                          (mayhem-bench--landing mayhem-sync--db data))
                  runs))
          (append
           (mapcar (pcase-lambda (`(,label . ,key))
                     (cons label (mayhem-bench--median
                                  (mapcar (lambda (run) (nth 1 (plist-get run key))) runs))))
                   '(("Read projects" . :read-projects)
                     ("Read targets" . :read-targets)
                     ("Check freshness" . :fresh)
                     ("Build candidates" . :build)
                     ("Fetch lands: store" . :store)
                     ("Fetch lands: re-read" . :reread)))
           (list (cons "Store size"
                       (caar (sqlite-select mayhem-sync--db
                                            "SELECT sum(length(body)) FROM resource")))
                 (cons "Candidates" (plist-get (car runs) :candidates)))))
      (sqlite-close mayhem-sync--db)
      (delete-file file))))

(let ((trimmed (mayhem-bench--scenario nil))
      (untrimmed (mayhem-bench--scenario t)))
  (princ (format "mayhem-jump on %d workspaces, %d projects, %d targets; Emacs %s, median of %d\n\n"
                 mayhem-bench--workspaces mayhem-bench--projects mayhem-bench--targets
                 emacs-version mayhem-bench--runs))
  (princ (format "  %-22s %12s %12s\n" "" "trimmed" "untrimmed"))
  (pcase-dolist (`(,label . ,seconds) trimmed)
    (let ((other (cdr (assoc label untrimmed))))
      (princ (pcase label
               ("Store size" (format "  %-22s %12s %12s\n" label
                                     (file-size-human-readable seconds)
                                     (file-size-human-readable other)))
               ("Candidates" (format "  %-22s %12d %12d\n" label seconds other))
               (_ (format "  %-22s %10.3f s %10.3f s\n" label seconds other)))))))

;;; bench.el ends here
