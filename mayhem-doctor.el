;;; mayhem-doctor.el --- Report on mayhem.el's code and store  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; `mayhem-doctor' writes a plain-text report to paste into a bug
;; report: which files are loaded, and whether a compiled one is older
;; than its source; the sync store's size and its largest resources;
;; and how long `mayhem-jump' takes to read and build what it searches.
;; It names the host, workspaces, projects and targets, never the token.
;;
;; `mayhem-doctor-search-timings' measures the search on its own, for
;; the report and for `make bench' (test/bench.el).

;;; Code:

(require 'seq)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)
(require 'mayhem-search)

(declare-function sqlite-select "ext:sqlite.c" (db query &optional values return-type))

(defconst mayhem-doctor--features
  '(mayhem-core mayhem-sync mayhem-vui mayhem-mayhemfile mayhem-workspace
                mayhem-project mayhem-target mayhem-defect mayhem-run mayhem-testcase
                mayhem-testsuite mayhem-search mayhem-doctor mayhem)
  "Features of mayhem.el, in the order they load.")

(defun mayhem-doctor--loaded-file (feature)
  "Return the file FEATURE was loaded from, or nil."
  (car (seq-find (lambda (entry) (member (cons 'provide feature) (cdr entry)))
                 load-history)))

(defun mayhem-doctor--stale-p (file)
  "Return non-nil if FILE, a compiled file, is older than its source."
  (let ((source (concat (file-name-sans-extension file) ".el")))
    (and (not (equal file source))
         (file-exists-p source)
         (file-newer-than-file-p source file))))

(defun mayhem-doctor--time (function)
  "Call FUNCTION and return (VALUE SECONDS GCS GC-SECONDS)."
  (let ((start (float-time))
        (gcs gcs-done)
        (gc-time gc-elapsed))
    (let ((value (funcall function)))
      (list value (- (float-time) start) (- gcs-done gcs) (- gc-elapsed gc-time)))))

(defun mayhem-doctor--untrimmed-p (target)
  "Return non-nil if TARGET has fields `mayhem--target-summary' drops."
  (seq-some (lambda (field) (not (memq (car-safe field) mayhem--target-fields))) target))

(defun mayhem-doctor-search-timings ()
  "Time each step `mayhem-jump' takes before its prompt opens, on the store.
Return a plist: :workspaces :projects :targets :untrimmed :candidates
are counts; :read-projects :read-targets :fresh :build are each
\(VALUE SECONDS GCS GC-SECONDS), as from `mayhem-doctor--time'."
  (let* ((read-projects (mayhem-doctor--time
                         (lambda () (plist-get (mayhem-sync-read '(projects)) :data))))
         (projects (car read-projects))
         (owners (mapcar #'car (mayhem--workspaces projects)))
         (read-targets (mayhem-doctor--time
                        (lambda ()
                          (mapcar (lambda (owner) (cons owner (mayhem-search--targets owner)))
                                  owners))))
         (targets (car read-targets))
         (all (mapcan (lambda (cell) (copy-sequence (cdr cell))) targets))
         (fresh (mayhem-doctor--time
                 (lambda ()
                   (let ((now (float-time)))
                     (mapcar (lambda (owner)
                               (mayhem-sync--fresh-p (list 'workspace-targets owner) now))
                             owners)))))
         (build (mayhem-doctor--time
                 (lambda () (mayhem-search--candidates projects targets)))))
    (list :workspaces (length owners) :projects (length projects) :targets (length all)
          :untrimmed (seq-count #'mayhem-doctor--untrimmed-p all)
          :candidates (length (car (car build)))
          :read-projects read-projects :read-targets read-targets :fresh fresh :build build)))

(defun mayhem-doctor-format-timing (label timing)
  "Return a line of LABEL and TIMING, as from `mayhem-doctor--time'."
  (format "  %-18s %8.3f s  %3d GCs, %.3f s\n"
          label (nth 1 timing) (nth 2 timing) (nth 3 timing)))

(defun mayhem-doctor-format-search (timings)
  "Return TIMINGS, from `mayhem-doctor-search-timings', as lines of text."
  (concat
   (format "  %d workspaces, %d projects, %d targets (%d untrimmed), %d candidates\n"
           (plist-get timings :workspaces) (plist-get timings :projects)
           (plist-get timings :targets) (plist-get timings :untrimmed)
           (plist-get timings :candidates))
   (mayhem-doctor-format-timing "Read projects" (plist-get timings :read-projects))
   (mayhem-doctor-format-timing "Read targets" (plist-get timings :read-targets))
   (mayhem-doctor-format-timing "Check freshness" (plist-get timings :fresh))
   (mayhem-doctor-format-timing "Build candidates" (plist-get timings :build))))

(defun mayhem-doctor--file-size (file)
  "Return the size of FILE, readable, or \"none\" if there is no FILE."
  (if-let* ((attributes (file-attributes file)))
      (file-size-human-readable (file-attribute-size attributes))
    "none"))

(defun mayhem-doctor--code ()
  "Return the report's lines on Emacs and the files loaded."
  (concat
   "Code\n"
   (format "  Emacs %s, %s, native-comp %s, SQLite %s\n"
           emacs-version system-configuration
           (if (and (fboundp 'native-comp-available-p) (native-comp-available-p)) "yes" "no")
           (if (and (fboundp 'sqlite-available-p) (sqlite-available-p)) "yes" "no"))
   ;; A large heap makes each collection slow, so reading big data can be.
   (format "  GC          threshold %s, percentage %s; %d so far, %.1f s in all\n"
           (file-size-human-readable gc-cons-threshold) gc-cons-percentage
           gcs-done gc-elapsed)
   (mapconcat (lambda (feature)
                (let ((file (mayhem-doctor--loaded-file feature)))
                  (format "  %-18s %s%s\n" feature (or file "not loaded")
                          (if (and file (mayhem-doctor--stale-p file))
                              "  STALE: older than its .el"
                            ""))))
              mayhem-doctor--features "")))

(defun mayhem-doctor--store (db file now)
  "Return the report's lines on DB, the store in FILE, at NOW."
  (pcase-let ((`(,count ,chars ,errors)
               (car (sqlite-select db "SELECT count(*), coalesce(sum(length(body)), 0),
                                              count(error)
                                       FROM resource")))
              (`(,files ,bytes)
               (car (sqlite-select db "SELECT count(*), coalesce(sum(length(bytes)), 0)
                                       FROM file"))))
    (concat
     "Store\n"
     (format "  File        %s  %s, WAL %s\n" file (mayhem-doctor--file-size file)
             (mayhem-doctor--file-size (concat file "-wal")))
     (format "  Schema      %s (this code's: %d)\n"
             (caar (sqlite-select db "PRAGMA user_version")) mayhem-sync--schema)
     (format "  Resources   %d, %s of data, %d failed\n"
             count (file-size-human-readable chars) errors)
     (format "  Files       %d, %s\n" files (file-size-human-readable bytes))
     (format "  Loading     %d\n" (hash-table-count mayhem-sync--loading))
     (format "  Fresh for   %s s\n" mayhem-sync-fresh-for)
     "\nLargest resources\n"
     (mapconcat (pcase-lambda (`(,key ,size ,fetched ,error))
                  (format "  %9s  %12s  %s%s\n" (file-size-human-readable size)
                          (if fetched (format "%d s ago" (round (- now fetched))) "never fetched")
                          key (if error (concat "  failed: " error) "")))
                (sqlite-select db "SELECT key, coalesce(length(body), 0), fetched_at, error
                                   FROM resource ORDER BY 2 DESC LIMIT 10")
                ""))))

(defun mayhem-doctor-report ()
  "Return, as a string, the report of `mayhem-doctor'."
  (let ((db (mayhem-sync--db)))
    (concat (format "mayhem-doctor at %s, host %s\n\n"
                    (format-time-string "%F %T") (or (mayhem--host) "none"))
            (mayhem-doctor--code)
            "\n"
            (mayhem-doctor--store db (mayhem-sync--file) (float-time))
            "\nSearch (mayhem-jump), before its prompt opens\n"
            (mayhem-doctor-format-search (mayhem-doctor-search-timings)))))

(defun mayhem-doctor-show ()
  "Show the report of `mayhem-doctor-report', which `g' redoes."
  (let ((buffer (get-buffer-create "*mayhem: doctor*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (mayhem-doctor-report)))
      (unless (derived-mode-p 'special-mode)
        (special-mode))
      (setq-local revert-buffer-function (lambda (&rest _) (mayhem-doctor-show)))
      (goto-char (point-min)))
    (mayhem-display-buffer buffer)))

(provide 'mayhem-doctor)
;;; mayhem-doctor.el ends here
