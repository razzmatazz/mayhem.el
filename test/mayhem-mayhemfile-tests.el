;;; mayhem-mayhemfile-tests.el --- Tests for mayhem-mayhemfile.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for reading the errors `mayhem validate' reports, from its
;; output as captured from the CLI (mayhem_core 2.14).

;;; Code:

(require 'ert)
(require 'mayhem-mayhemfile)

(ert-deftest mayhem-mayhemfile-test-parse-type-error ()
  (should (equal (mayhem-mayhemfile--parse-validate "\
WARNING Warning: Skipping docker tests. Incorrect targets may pass validation.
ERROR Error: Mayhemfile contains errors
ERROR  --> /tmp/x/Mayhemfile
ERROR 3 | duration: abc
ERROR   |           ^^^ 'abc' is not of type 'integer', 'null'
ERROR 
ERROR Source Mayhemfile /tmp/x/Mayhemfile is not immediately parseable
ERROR Invalid configuration.
Suggestion: Review error messages above.
")
                 '((3 10 13 "'abc' is not of type 'integer', 'null'")))))

(ert-deftest mayhem-mayhemfile-test-parse-takes-the-caret-line-with-a-message ()
  (should (equal (mayhem-mayhemfile--parse-validate "\
ERROR Error: Mayhemfile contains errors
ERROR 4 |   - cmd: /bin/cat @@
ERROR   |     ^^^^^^^^^^^^^^^^ 
ERROR 5 |     java: 1
ERROR   | ^^^^^^^^^^ Additional properties are not allowed ('java' was unexpected)
")
                 '((5 0 10 "Additional properties are not allowed ('java' was unexpected)")))))

(ert-deftest mayhem-mayhemfile-test-parse-drops-repeats-and-headers ()
  (should (equal (mayhem-mayhemfile--parse-validate "\
ERROR Error: version not recognized
ERROR  --> /tmp/x/Mayhemfile
ERROR 3 | version: '0.1'
ERROR   |          ^^^^^ '0.1' is not a recognized version.
ERROR 
ERROR Error: version not recognized
ERROR  --> 
ERROR 3 | version: '0.1'
ERROR   |          ^^^^^ '0.1' is not a recognized version.
ERROR Error materializing default values for Mayhemfile.
")
                 '((3 9 14 "'0.1' is not a recognized version.")))))

(ert-deftest mayhem-mayhemfile-test-parse-unplaced-error ()
  (should (equal (mayhem-mayhemfile--parse-validate "\
ERROR Error: Mayhemfile contains errors
ERROR Additional properties are not allowed ('bogus' was unexpected)
ERROR 
ERROR Source Mayhemfile /tmp/x/Mayhemfile is not immediately parseable
ERROR Invalid configuration.
")
                 '((nil nil nil "Additional properties are not allowed ('bogus' was unexpected)")))))

(ert-deftest mayhem-mayhemfile-test-parse-splits-unexpected-keys ()
  (should (equal (mayhem-mayhemfile--parse-validate "\
ERROR Error: Mayhemfile contains errors
ERROR Additional properties are not allowed ('image', 'tasks' were unexpected)
")
                 '((nil nil nil "Additional properties are not allowed ('image' was unexpected)")
                   (nil nil nil "Additional properties are not allowed ('tasks' was unexpected)")))))

(ert-deftest mayhem-mayhemfile-test-parse-yaml-error ()
  (should (equal (mayhem-mayhemfile--parse-validate "\
ERROR Error: YAML parsing error: while parsing a block collection
  in \"<unicode string>\", line 4, column 3:
      - cmd: /bin/cat @@
      ^ (line: 4)
expected <block end>, but found '<block mapping start>'
  in \"<unicode string>\", line 5, column 4:
       cwd: [x
       ^ (line: 5)
ERROR 
")
                 '((4 2 nil "while parsing a block collection")
                   (5 3 nil "expected <block end>, but found '<block mapping start>'")))))

(ert-deftest mayhem-mayhemfile-test-region ()
  (with-temp-buffer
    (insert "project: a/b\nbogus: 1\ncmds:\n  - cmd: x\n")
    (should (equal (mayhem-mayhemfile--region 2 0 5 "m") '(14 . 19)))
    (should (equal (mayhem-mayhemfile--region 4 4 nil "m") '(33 . 37)))
    (should (equal (mayhem-mayhemfile--region 4 0 9 "m") '(31 . 38)))
    (should (equal (mayhem-mayhemfile--region
                    nil nil nil "Additional properties are not allowed ('bogus' was unexpected)")
                   '(14 . 19)))
    (should (equal (mayhem-mayhemfile--region nil nil nil "other") '(1 . 13)))))

;;; mayhem-mayhemfile-tests.el ends here
