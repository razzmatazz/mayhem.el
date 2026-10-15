;;; mayhem-core-tests.el --- Tests for mayhem-core.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for the `mayhem list' parser.

;;; Code:

(require 'ert)
(require 'mayhem-core)

(ert-deftest mayhem-core-test-parse-list-groups-by-project ()
  (should (equal (mayhem--parse-list "proj/a\nproj/b\nother/c\n")
                 '(("proj" "a" "b") ("other" "c")))))

(ert-deftest mayhem-core-test-parse-list-drops-owner ()
  (should (equal (mayhem--parse-list "acme/proj/a\n")
                 '(("proj" "a")))))

(ert-deftest mayhem-core-test-parse-list-ignores-notices ()
  (should (null (mayhem--parse-list
                 "You have no projects / targets! Create one with mayhem run."))))

(provide 'mayhem-core-tests)
;;; mayhem-core-tests.el ends here
