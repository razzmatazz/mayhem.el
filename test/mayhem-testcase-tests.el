;;; mayhem-testcase-tests.el --- Tests for mayhem-testcase.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for what a test case's page shows.

;;; Code:

(require 'ert)
(require 'mayhem-testcase)

(defun mayhem-testcase-tests--page (test)
  "Return the text of the page of TEST, a test case as its fetch gives it."
  (with-temp-buffer
    (vui-render (mayhem-testcase--render "o" "p" "t" 1 `((testcase . ,test))))
    (buffer-substring-no-properties (point-min) (point-max))))

(defun mayhem-testcase-tests--lines (prefix n)
  "Return N lines, each PREFIX and its number, joined."
  (mapconcat (lambda (i) (format "%s %d" prefix i)) (number-sequence 1 n) "\n"))

(ert-deftest mayhem-testcase-test-long-blocks-unfold ()
  (let ((page (mayhem-testcase-tests--page
               `((hexdump . ,(mayhem-testcase-tests--lines "hex" 30))
                 (output . ,(concat "Standard Out:\n" (mayhem-testcase-tests--lines "out" 2)
                                    "\n\nStandard Error:\n"
                                    (mayhem-testcase-tests--lines "err" 25)))))))
    ;; The test case's bytes and its stderr each stop at their first lines.
    (should (string-search (format "hex %d\n[Show all 30 lines]" mayhem-block-lines) page))
    (should-not (string-search (format "hex %d\n" (1+ mayhem-block-lines)) page))
    (should (string-search (format "err %d\n[Show all 25 lines]" mayhem-block-lines) page))
    ;; Short stdout shows whole.
    (should (string-search "Standard output\nout 1\nout 2\n\nStandard error\n" page))))

(ert-deftest mayhem-testcase-test-output-as-is ()
  ;; Output not split into stdout and stderr shows as it came, still cut.
  (let ((page (mayhem-testcase-tests--page
               `((output . ,(mayhem-testcase-tests--lines "raw" 20))))))
    (should (string-search "Output\nraw 1\n" page))
    (should (string-search "[Show all 20 lines]" page)))
  (should (string-search "Output\nNo output\n"
                         (mayhem-testcase-tests--page
                          '((output . "Standard Out: (empty)\n\nStandard Error: (empty)\n"))))))

(provide 'mayhem-testcase-tests)
;;; mayhem-testcase-tests.el ends here
