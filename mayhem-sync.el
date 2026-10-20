;;; mayhem-sync.el --- Cache Mayhem data in a local SQLite store  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; The sync layer between pages and the Mayhem API, to hide latency.
;; Pages ask for resources, such as `(projects)', and read them from a
;; SQLite store, so they paint at once.  A fetch runs behind the painted
;; page, writes the store, and the page re-renders only if the data
;; changed.  A failed refresh keeps the data.
;;
;; The design follows octocat.el's plans/github-sync-mechanism.md.
;; Only its basics are here: one row per resource.  Entities shared by
;; resources, mutations and prefetch come when pages need them.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'vui)
(require 'mayhem-core)

(defcustom mayhem-sync-directory (locate-user-emacs-file "mayhem/")
  "Directory of the sync store, one SQLite file per Mayhem host."
  :type 'directory
  :group 'mayhem)

(defcustom mayhem-sync-fresh-for 30
  "Seconds after a fetch during which opening a page doesn't refetch it."
  :type 'number
  :group 'mayhem)

(defvar mayhem-sync-change-functions nil
  "Functions called with the keys of resources whose snapshot changed.")

(defvar mayhem-sync-loading-functions nil
  "Functions called with a resource's key and whether it is now loading.
Loading changes no data, so pages show it in the mode line only.")

(defconst mayhem-sync--schema 3
  "Version of the store's tables, kept in SQLite's `user_version'.
Bump it also when a resource's data changes shape: the store is then
recreated rather than read in the old shape.")


;;;; Store

(defvar mayhem-sync--db nil
  "The open store, or nil before first use.")

(defun mayhem-sync--create (db)
  "Create the tables of DB, dropping older ones, and return DB.
Signal a `user-error' when DB was made by a newer mayhem.el."
  (let ((version (caar (sqlite-select db "PRAGMA user_version"))))
    (cond
     ((> version mayhem-sync--schema)
      (user-error "Mayhem: The sync store is from a newer mayhem.el; restart Emacs"))
     ((< version mayhem-sync--schema)
      ;; A cache, so there are no migrations.
      (sqlite-execute db "DROP TABLE IF EXISTS resource")
      (sqlite-execute db "CREATE TABLE resource (
  key TEXT PRIMARY KEY, body TEXT, hash TEXT, fetched_at REAL, error TEXT)")
      (sqlite-execute db (format "PRAGMA user_version = %d" mayhem-sync--schema))))
    db))

(defun mayhem-sync--host ()
  "Return the host of the configured Mayhem server, or \"default\"."
  (or (mayhem--host) "default"))

(defun mayhem-sync--db ()
  "Return the store, opening it on first use."
  (or mayhem-sync--db
      (progn
        (unless (and (fboundp 'sqlite-available-p) (sqlite-available-p))
          (user-error "Mayhem: Needs an Emacs built with SQLite"))
        (make-directory mayhem-sync-directory t)
        (let ((db (sqlite-open (expand-file-name
                                (concat "sync-" (mayhem-sync--host) ".sqlite")
                                mayhem-sync-directory))))
          (sqlite-pragma db "journal_mode=WAL")
          (sqlite-pragma db "busy_timeout=2000")
          (setq mayhem-sync--db (mayhem-sync--create db))))))

(defun mayhem-sync--print (data)
  "Return DATA, plain Lisp data, as a string `read' gives back."
  (let ((print-length nil) (print-level nil) (print-circle nil))
    (prin1-to-string data)))

(defun mayhem-sync--write (db key data now)
  "Store DATA, fetched at NOW, as resource KEY of DB.
Return non-nil if its snapshot changed: new data, or an error cleared."
  (let* ((body (mayhem-sync--print data))
         (hash (secure-hash 'sha1 body))
         (old  (car (sqlite-select db "SELECT hash, error FROM resource WHERE key = ?"
                                   (list key)))))
    (sqlite-execute db "INSERT INTO resource (key, body, hash, fetched_at)
                        VALUES (?, ?, ?, ?)
                        ON CONFLICT (key) DO UPDATE
                        SET body = excluded.body, hash = excluded.hash,
                            fetched_at = excluded.fetched_at, error = NULL"
                    (list key body hash now))
    (or (not (equal hash (nth 0 old))) (and (nth 1 old) t))))

(defun mayhem-sync--write-error (db key message)
  "Record in DB that the fetch of resource KEY failed with MESSAGE.
The resource keeps its data.  Return non-nil if the error is new."
  (let ((old (caar (sqlite-select db "SELECT error FROM resource WHERE key = ?"
                                  (list key)))))
    (sqlite-execute db "INSERT INTO resource (key, error) VALUES (?, ?)
                        ON CONFLICT (key) DO UPDATE SET error = excluded.error"
                    (list key message))
    (not (equal old message))))

(defun mayhem-sync--read (db key)
  "Return resource KEY of DB as (DATA FETCHED-AT ERROR), or nil."
  (when-let* ((row (car (sqlite-select
                         db "SELECT body, fetched_at, error FROM resource WHERE key = ?"
                         (list key)))))
    (list (and (nth 0 row) (car (read-from-string (nth 0 row))))
          (nth 1 row)
          (nth 2 row))))


;;;; Resources

(defvar mayhem-sync--resources (make-hash-table :test #'eq)
  "Resource name to a function of the spec's arguments returning its plist.")

(defmacro mayhem-sync-define-resource (name args &rest props)
  "Define the resource NAME, whose spec is (NAME . ARGS).
PROPS are evaluated with ARGS bound.  :fetch is a function of DONE that
fetches the resource and calls DONE with (OK DATA), as
`mayhem--api-get' calls back.  DATA must be plain Lisp data that prints
readably: it is stored printed."
  (declare (indent 2))
  `(puthash ',name (lambda ,args (list ,@props)) mayhem-sync--resources))

(defun mayhem-sync--props (spec)
  "Return the plist of resource SPEC."
  (apply (or (gethash (car spec) mayhem-sync--resources)
             (error "Mayhem: Unknown resource `%s'" (car spec)))
         (cdr spec)))

(defun mayhem-sync-spec-key (spec)
  "Return the store key of SPEC, its printed form."
  (prin1-to-string spec))

(defvar mayhem-sync--loading (make-hash-table :test #'equal)
  "Keys of the resources being fetched.  Kept in memory only.")

(defun mayhem-sync-read (spec)
  "Return a snapshot of SPEC: a plist of :data :fetched-at :error :loading.
It reads only the store, never the network.  :fetched-at is nil until
the first fetch succeeds; :error is the last fetch's failure, if any."
  (let ((key (mayhem-sync-spec-key spec)))
    (pcase-let ((`(,data ,fetched-at ,error) (mayhem-sync--read (mayhem-sync--db) key)))
      (list :data data :fetched-at fetched-at :error error
            :loading (gethash key mayhem-sync--loading)))))

(defun mayhem-sync--fresh-p (key now)
  "Return non-nil if resource KEY was fetched just before NOW.
That is, within `mayhem-sync-fresh-for' seconds."
  (when-let* ((fetched (caar (sqlite-select (mayhem-sync--db)
                                            "SELECT fetched_at FROM resource WHERE key = ?"
                                            (list key)))))
    (< (- now fetched) mayhem-sync-fresh-for)))

(defun mayhem-sync--set-loading (key loading)
  "Record whether resource KEY is LOADING, and report it."
  (if loading
      (puthash key t mayhem-sync--loading)
    (remhash key mayhem-sync--loading))
  (run-hook-with-args 'mayhem-sync-loading-functions key loading))

(defun mayhem-sync-request (spec &optional force)
  "Fetch SPEC in the background, unless running or fetched just now.
FORCE fetches even data fetched just now.  Return at once; the store
reports the result through `mayhem-sync-change-functions'."
  (let ((key (mayhem-sync-spec-key spec)))
    (unless (or (gethash key mayhem-sync--loading)
                (and (not force) (mayhem-sync--fresh-p key (float-time))))
      (mayhem-sync--set-loading key t)
      (let ((answered nil))
        (condition-case err
            (funcall (plist-get (mayhem-sync--props spec) :fetch)
                     (lambda (ok data)
                       (setq answered t)
                       (mayhem-sync--done key ok data)))
          ;; A fetch that signals as it starts must not stay loading.
          (error (if answered
                     (signal (car err) (cdr err))
                   (mayhem-sync--done key nil (error-message-string err)))))))))

(defun mayhem-sync--done (key ok data)
  "Store DATA, or the error message DATA unless OK, as resource KEY; notify."
  (mayhem-sync--set-loading key nil)
  (when (condition-case err
            (let ((db (mayhem-sync--db)))
              (if ok
                  (mayhem-sync--write db key data (float-time))
                (mayhem-sync--write-error db key data)))
          ;; Say a second Emacs held the lock past the timeout: drop the write.
          (error (message "Mayhem: Storing %s failed: %s" key (error-message-string err))
                 nil))
    (run-hook-with-args 'mayhem-sync-change-functions (list key))))


;;;; Pages

;; Each `mayhem-sync-use-resource' registers its buffer and a version
;; ref under its resource key; a change bumps the versions and
;; re-renders each buffer once.

(defvar mayhem-sync--subscriptions (make-hash-table :test #'equal)
  "Resource key to the (BUFFER . VERSION-REF) of each page reading it.")

(defun mayhem-sync--on-change (keys)
  "Re-render, once each, the pages reading a resource in KEYS."
  (let (buffers)
    (dolist (key keys)
      (pcase-dolist (`(,buf . ,version) (gethash key mayhem-sync--subscriptions))
        (setcar version (1+ (car version)))
        (unless (memq buf buffers) (push buf buffers))))
    (dolist (buf buffers)
      (when-let* ((root (and (buffer-live-p buf) (vui-get-instance buf))))
        (vui-rerender root)))))

(add-hook 'mayhem-sync-change-functions #'mayhem-sync--on-change)

(defvar-local mayhem-sync--loading-keys nil
  "Keys of the resources this buffer's page reads that are being fetched.")

(defun mayhem-sync--show-loading (buf key loading)
  "Record in BUF that resource KEY is LOADING, and show it in its mode line."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (setq mayhem-sync--loading-keys
            (if loading
                (cons key (delete key mayhem-sync--loading-keys))
              (delete key mayhem-sync--loading-keys)))
      (setq mode-line-process (and mayhem-sync--loading-keys ":loading"))
      (force-mode-line-update))))

(defun mayhem-sync--on-loading (key loading)
  "Show in the mode line of each page reading KEY whether it is LOADING."
  (pcase-dolist (`(,buf . ,_) (gethash key mayhem-sync--subscriptions))
    (mayhem-sync--show-loading buf key loading)))

(add-hook 'mayhem-sync-loading-functions #'mayhem-sync--on-loading)

(defun mayhem-sync-header-notice (snapshot)
  "Return the header line notice for SNAPSHOT, or nil.
There is one when a refresh failed over shown data: the data stays."
  (when (and (plist-get snapshot :fetched-at) (plist-get snapshot :error)
             (not (plist-get snapshot :loading)))
    (format "Refresh failed: %s; g to retry"
            (car (split-string (plist-get snapshot :error) "\n" t)))))

(defvar-local mayhem-sync--snapshots nil
  "Alist of resource key to the snapshot on this buffer's page.")

(defun mayhem-sync--show-notice (buf key snapshot)
  "Record in BUF the SNAPSHOT of KEY on its page, nil for none.
Put in its header line the notice of the first snapshot that has one."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (setq mayhem-sync--snapshots
            (if snapshot
                (cons (cons key snapshot) (assoc-delete-all key mayhem-sync--snapshots))
              (assoc-delete-all key mayhem-sync--snapshots)))
      (setq header-line-format
            (when-let* ((notice (seq-some (lambda (entry)
                                            (mayhem-sync-header-notice (cdr entry)))
                                          mayhem-sync--snapshots)))
              (propertize notice 'face 'warning))))))

(defun mayhem-sync-use-resource (spec)
  "Return the snapshot of SPEC, as `mayhem-sync-read' gives it.
Opening the page fetches SPEC unless it was fetched just now; the page
re-renders when the snapshot changes, and its mode line shows when SPEC
is being fetched.  A failed refresh shows in the header line.  A
component calling this must not be `:memo'.  Call it during render,
like any hook."
  (let* ((key     (mayhem-sync-spec-key spec))
         (buf     (current-buffer))
         (version (vui-use-ref 0))
         (v       (car version)))
    (vui-use-effect (key)
      (let ((entry (cons buf version)))
        (push entry (gethash key mayhem-sync--subscriptions))
        (mayhem-sync-request spec)
        (when (gethash key mayhem-sync--loading)
          (mayhem-sync--show-loading buf key t))
        (lambda ()
          (mayhem-sync--show-loading buf key nil)
          (let ((rest (delq entry (gethash key mayhem-sync--subscriptions))))
            (if rest
                (puthash key rest mayhem-sync--subscriptions)
              (remhash key mayhem-sync--subscriptions))))))
    (let ((snapshot (vui-use-memo (key v) (mayhem-sync-read spec))))
      (vui-use-effect (key snapshot)
        (mayhem-sync--show-notice buf key snapshot)
        (lambda () (mayhem-sync--show-notice buf key nil)))
      snapshot)))

(defun mayhem-sync-combine (&rest snapshots)
  "Return one snapshot of SNAPSHOTS, for a page part that needs them all.
Its :data is the list of theirs; it is fetched once all are, loading
while any is, and carries the first error."
  (list :data (mapcar (lambda (s) (plist-get s :data)) snapshots)
        :fetched-at (and (seq-every-p (lambda (s) (plist-get s :fetched-at)) snapshots)
                         (apply #'min (mapcar (lambda (s) (plist-get s :fetched-at))
                                              snapshots)))
        :error (seq-some (lambda (s) (plist-get s :error)) snapshots)
        :loading (seq-some (lambda (s) (plist-get s :loading)) snapshots)))

(defun mayhem-sync-refresh (&optional buffer soft)
  "Fetch again each resource on the page in BUFFER, even if fetched just now.
BUFFER defaults to the current one.  With SOFT, skip those fetched just
now, as opening a page does.  The page stays as it is until the new
data lands."
  (let ((buf (or buffer (current-buffer))))
    (maphash (lambda (key entries)
               (when (assq buf entries)
                 (mayhem-sync-request (car (read-from-string key)) (not soft))))
             mayhem-sync--subscriptions)))

(defun mayhem-sync-revert-buffer (&rest _)
  "Refetch the page's resources, as `revert-buffer-function'.
So `revert-buffer', and `gr' under Evil, refresh a page as `g' does."
  (mayhem-sync-refresh))

(provide 'mayhem-sync)
;;; mayhem-sync.el ends here
