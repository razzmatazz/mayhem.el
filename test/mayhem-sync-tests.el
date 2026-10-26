;;; mayhem-sync-tests.el --- Tests for mayhem-sync.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the sync store and requests, on an in-memory database.

;;; Code:

(require 'ert)
(require 'mayhem-sync)

(defmacro mayhem-sync-tests--with-db (&rest body)
  "Run BODY with a fresh in-memory store and no loading resources."
  (declare (indent 0))
  `(let ((mayhem-sync--db (mayhem-sync--create (sqlite-open nil)))
         (mayhem-sync--loading (make-hash-table :test #'equal))
         (mayhem-sync--resources (make-hash-table :test #'eq))
         (mayhem-sync-change-functions nil)
         (mayhem-sync-loading-functions nil))
     ,@body))

(ert-deftest mayhem-sync-test-write-round-trips ()
  (mayhem-sync-tests--with-db
    (should (mayhem-sync--write mayhem-sync--db "k" '(("a/p" "t")) 10.0))
    (should (equal (mayhem-sync--read mayhem-sync--db "k")
                   '((("a/p" "t")) 10.0 nil)))))

(ert-deftest mayhem-sync-test-unchanged-write-reports-nothing ()
  (mayhem-sync-tests--with-db
    (mayhem-sync--write mayhem-sync--db "k" '(1 2) 10.0)
    (should-not (mayhem-sync--write mayhem-sync--db "k" '(1 2) 20.0))
    (should (equal (nth 1 (mayhem-sync--read mayhem-sync--db "k")) 20.0))))

(ert-deftest mayhem-sync-test-error-keeps-data-until-success ()
  (mayhem-sync-tests--with-db
    (mayhem-sync--write mayhem-sync--db "k" '(1) 10.0)
    (should (mayhem-sync--write-error mayhem-sync--db "k" "HTTP 500: oops"))
    (should-not (mayhem-sync--write-error mayhem-sync--db "k" "HTTP 500: oops"))
    (should (equal (mayhem-sync--read mayhem-sync--db "k") '((1) 10.0 "HTTP 500: oops")))
    ;; Same data, but the error clears, so the snapshot changed.
    (should (mayhem-sync--write mayhem-sync--db "k" '(1) 20.0))
    (should (equal (mayhem-sync--read mayhem-sync--db "k") '((1) 20.0 nil)))))

(ert-deftest mayhem-sync-test-max-age ()
  (mayhem-sync-tests--with-db
    (mayhem-sync-define-resource thing (age)
      :fetch #'ignore
      :max-age age)
    (mayhem-sync-define-resource settled ()
      :fetch #'ignore
      :max-age (lambda (data) (if (eq (car data) 'done) 1000 10)))
    (dolist (spec '((thing nil) (thing 1000) (settled)))
      (mayhem-sync--write mayhem-sync--db (mayhem-sync-spec-key spec) '(running) 100.0))
    (let ((mayhem-sync-fresh-for 30))
      (should (mayhem-sync--fresh-p '(thing nil) 120.0))
      (should-not (mayhem-sync--fresh-p '(thing nil) 140.0))
      (should (mayhem-sync--fresh-p '(thing 1000) 500.0))
      (should-not (mayhem-sync--fresh-p '(settled) 120.0))
      (mayhem-sync--write mayhem-sync--db (mayhem-sync-spec-key '(settled)) '(done) 100.0)
      (should (mayhem-sync--fresh-p '(settled) 500.0))
      (should-not (mayhem-sync--fresh-p '(missing) 100.0)))))

(ert-deftest mayhem-sync-test-max-age-t-is-for-good ()
  (mayhem-sync-tests--with-db
    (mayhem-sync-define-resource suite ()
      :fetch #'ignore
      :max-age (lambda (data) (if (eq (car data) 'done) t 10)))
    (mayhem-sync--write mayhem-sync--db (mayhem-sync-spec-key '(suite)) '(running) 100.0)
    (should-not (mayhem-sync--fresh-p '(suite) 200.0))
    (should-not (mayhem-sync--fresh-p '(suite) 105.0 t))
    (mayhem-sync--write mayhem-sync--db (mayhem-sync-spec-key '(suite)) '(done) 100.0)
    (should (mayhem-sync--fresh-p '(suite) 1e9))
    ;; Not even `g' refetches it.
    (should (mayhem-sync--fresh-p '(suite) 1e9 t))))

(ert-deftest mayhem-sync-test-files-round-trip ()
  (mayhem-sync-tests--with-db
    (let ((bytes (unibyte-string 0 255 10 ?A 0)))
      (mayhem-sync-put-files (list (cons "s1" bytes)))
      (should (equal (mayhem-sync-file "s1") bytes))
      (should-not (multibyte-string-p (mayhem-sync-file "s1")))
      ;; Named by their bytes: one stored is kept.
      (mayhem-sync-put-files (list (cons "s1" "other")))
      (should (equal (mayhem-sync-file "s1") bytes))
      (should-not (mayhem-sync-file "s2")))))

(ert-deftest mayhem-sync-test-newer-schema-signals ()
  (let ((db (sqlite-open nil)))
    (sqlite-execute db (format "PRAGMA user_version = %d" (1+ mayhem-sync--schema)))
    (should-error (mayhem-sync--create db) :type 'user-error)))

(ert-deftest mayhem-sync-test-older-schema-compacts ()
  (let ((db (mayhem-sync--create (sqlite-open nil))))
    (dotimes (i 200)
      (mayhem-sync--write db (format "k%d" i) (make-string 2000 ?x) 10.0))
    (sqlite-execute db (format "PRAGMA user_version = %d" (1- mayhem-sync--schema)))
    (mayhem-sync--create db)
    (should (equal (caar (sqlite-select db "SELECT count(*) FROM resource")) 0))
    (should (equal (caar (sqlite-select db "PRAGMA freelist_count")) 0))))

(ert-deftest mayhem-sync-test-request-stores-and-notifies ()
  (mayhem-sync-tests--with-db
    (let ((fetches 0) changed done)
      (mayhem-sync-define-resource thing ()
        :fetch (lambda (cb) (setq fetches (1+ fetches)) (setq done cb)))
      (add-hook 'mayhem-sync-change-functions (lambda (keys) (setq changed keys)))
      (mayhem-sync-request '(thing))
      (should (plist-get (mayhem-sync-read '(thing)) :loading))
      ;; A second request while loading joins the first.
      (mayhem-sync-request '(thing))
      (should (= fetches 1))
      (funcall done t '(42))
      (should (equal changed '("(thing)")))
      (should (equal (plist-get (mayhem-sync-read '(thing)) :data) '(42)))
      (should-not (plist-get (mayhem-sync-read '(thing)) :loading))
      ;; Fetched just now: only a forced request fetches again.
      (mayhem-sync-request '(thing))
      (should (= fetches 1))
      (mayhem-sync-request '(thing) t)
      (should (= fetches 2)))))

(ert-deftest mayhem-sync-test-fetch-that-signals-records-error ()
  (mayhem-sync-tests--with-db
    (mayhem-sync-define-resource broken () :fetch (lambda (_cb) (error "Boom")))
    (mayhem-sync-request '(broken))
    (let ((snapshot (mayhem-sync-read '(broken))))
      (should (equal (plist-get snapshot :error) "Boom"))
      (should-not (plist-get snapshot :loading)))))

(ert-deftest mayhem-sync-test-header-notice ()
  (should-not (mayhem-sync-header-notice '(:error "x")))
  (should-not (mayhem-sync-header-notice '(:fetched-at 1.0 :error "x" :loading t)))
  (should (equal (mayhem-sync-header-notice '(:fetched-at 1.0 :error "HTTP 500: a\nb"))
                 "Refresh failed: HTTP 500: a; g to retry")))

(provide 'mayhem-sync-tests)
;;; mayhem-sync-tests.el ends here
