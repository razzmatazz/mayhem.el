;;; mayhem-core-tests.el --- Tests for mayhem-core.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for config parsing, requests and shaping of API responses.

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

(ert-deftest mayhem-core-test-path-encodes-segments ()
  (should (equal (mayhem--path "/a/%s/b/%s" "x y" "z/w") "/a/x%20y/b/z%2Fw")))

(ert-deftest mayhem-core-test-fetch-each-collects-in-order ()
  (let (result later)
    (mayhem--fetch-each
     `((a . ,(lambda (cb) (setq later cb)))
       (b . ,(lambda (cb) (funcall cb t 2))))
     (lambda (ok data) (setq result (list ok data))))
    (should-not result)
    (funcall later t 1)
    (should (equal result '(t ((a . 1) (b . 2)))))))

(ert-deftest mayhem-core-test-fetch-each-fails-once ()
  (let (results)
    (mayhem--fetch-each
     `((a . ,(lambda (cb) (funcall cb nil "HTTP 404: no")))
       (b . ,(lambda (cb) (funcall cb nil "HTTP 500: also"))))
     (lambda (ok data) (push (list ok data) results)))
    (should (equal results '((nil "HTTP 404: no"))))))

(ert-deftest mayhem-core-test-run-status ()
  (should (equal (mayhem--run-status '((ended . t) (started . t))) "completed"))
  (should (equal (mayhem--run-status '((failed . t) (ended . t))) "failed"))
  (should (equal (mayhem--run-status '((started . t))) "running"))
  (should (equal (mayhem--run-status nil) "unknown")))

(ert-deftest mayhem-core-test-format-age ()
  (let ((now (encode-time (iso8601-parse "2026-10-19T12:00:00+00:00"))))
    (should (equal (mayhem--format-age "2026-10-19T11:59:30.5+00:00" now) "just now"))
    (should (equal (mayhem--format-age "2026-10-19T11:00:00+00:00" now) "1 hour ago"))
    (should (equal (mayhem--format-age "2026-10-16T12:00:00+00:00" now) "3 days ago"))
    (should (equal (mayhem--format-age "2024-10-01T12:00:00+00:00" now) "2 years ago"))
    (should-not (mayhem--format-age nil now))))

(provide 'mayhem-core-tests)
;;; mayhem-core-tests.el ends here
