;;; mayhem-core-tests.el --- Tests for mayhem-core.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for config parsing and shaping of API responses.

;;; Code:

(require 'ert)
(require 'mayhem-core)

(ert-deftest mayhem-core-test-parse-config-reads-default ()
  (should (equal (mayhem--parse-config
                  "[DEFAULT]\nurl = https://example.com/\ntoken=AT1.xyz\n")
                 '((url . "https://example.com/") (token . "AT1.xyz")))))

(ert-deftest mayhem-core-test-parse-config-ignores-other-sections ()
  (should (equal (mayhem--parse-config
                  "# comment\n[other]\ntoken = no\n[DEFAULT]\ntoken = yes\n")
                 '((token . "yes")))))

(ert-deftest mayhem-core-test-api-url ()
  (should (equal (mayhem--api-url "https://example.com/" "/api/v2/user/me")
                 "https://example.com/api/v2/user/me"))
  (should (equal (mayhem--api-url "https://example.com" "/api/v2/x"
                                  '((per_page 100) (offset 0)))
                 "https://example.com/api/v2/x?per_page=100&offset=0")))

(defun mayhem-core-tests--response (status body)
  "Run `mayhem--api-response' on an HTTP STATUS response with BODY."
  (with-temp-buffer
    (insert "HTTP/1.1 " (number-to-string status) "\n\n")
    (setq-local url-http-end-of-headers (point))
    (setq-local url-http-response-status status)
    (insert body)
    (mayhem--api-response nil)))

(ert-deftest mayhem-core-test-api-response-parses-json ()
  (should (equal (mayhem-core-tests--response 200 "{\"slug\":\"me\",\"x\":[1,null]}")
                 '(t ((slug . "me") (x 1 nil))))))

(ert-deftest mayhem-core-test-api-response-reports-message ()
  (should (equal (mayhem-core-tests--response 401 "{\"message\":\"Unauthorized\"}")
                 '(nil "HTTP 401: Unauthorized"))))

(ert-deftest mayhem-core-test-api-response-without-response ()
  (with-temp-buffer
    (should (equal (mayhem--api-response '(:error (error connection-failed)))
                   '(nil "connection-failed")))))

(ert-deftest mayhem-core-test-group-targets ()
  (should (equal (mayhem--group-targets
                  '(((owner . "acme") (slug . "p"))
                    ((owner . "bob") (slug . "p"))
                    ((owner . "acme") (slug . "empty")))
                  '(((owner . "acme") (project_slug . "p") (slug . "a"))
                    ((owner . "bob") (project_slug . "p") (slug . "c"))
                    ((owner . "acme") (project_slug . "hidden") (slug . "x"))
                    ((owner . "acme") (project_slug . "p") (slug . "b"))))
                 '(("acme/p" "a" "b") ("bob/p" "c") ("acme/empty")))))

(provide 'mayhem-core-tests)
;;; mayhem-core-tests.el ends here
