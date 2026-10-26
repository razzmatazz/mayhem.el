;;; mayhem-doctor-tests.el --- Tests for mayhem-doctor.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the report, on an in-memory store.

;;; Code:

(require 'ert)
(require 'mayhem-doctor)

(ert-deftest mayhem-doctor-test-search-timings ()
  (let ((mayhem-sync--db (mayhem-sync--create (sqlite-open nil)))
        (mayhem-sync--loading (make-hash-table :test #'equal)))
    (mayhem-sync--write mayhem-sync--db "(projects)"
                        '(((owner . "acme") (slug . "p"))) 10.0)
    (mayhem-sync--write mayhem-sync--db "(workspace-targets \"acme\")"
                        '(((owner . "acme") (project_slug . "p") (slug . "t") (type . "code"))
                          ((owner . "acme") (project_slug . "p") (slug . "u") (latest . big)))
                        10.0)
    (let ((timings (mayhem-doctor-search-timings)))
      (should (equal (plist-get timings :workspaces) 1))
      (should (equal (plist-get timings :targets) 2))
      (should (equal (plist-get timings :untrimmed) 1))
      (should (equal (plist-get timings :candidates) 4))
      (should (string-match-p "Read targets" (mayhem-doctor-format-search timings))))
    (should (string-match-p "(workspace-targets \"acme\")"
                            (mayhem-doctor--store mayhem-sync--db "/nonexistent" 20.0)))))

(ert-deftest mayhem-doctor-test-hidden-targets ()
  (should (equal (mayhem-doctor--hidden-targets
                  '(((owner . "acme") (slug . "p")))
                  '(("acme" ((owner . "acme") (project_slug . "p") (slug . "a"))
                     ((owner . "acme") (project_slug . "gone") (slug . "b"))
                     ((owner . "acme") (project_slug . "old") (slug . "c"))
                     ((owner . "acme") (project_slug . "old") (slug . "d")))))
                 '(("acme/old" . 2) ("acme/gone" . 1)))))

(ert-deftest mayhem-doctor-test-stale-p ()
  (let* ((dir (make-temp-file "mayhem-doctor" t))
         (source (expand-file-name "x.el" dir))
         (compiled (expand-file-name "x.elc" dir)))
    (unwind-protect
        (progn
          (write-region "" nil compiled)
          (write-region "" nil source)
          (set-file-times compiled (time-subtract nil 60))
          (should (mayhem-doctor--stale-p compiled))
          (should-not (mayhem-doctor--stale-p source)))
      (delete-directory dir t))))

;;; mayhem-doctor-tests.el ends here
