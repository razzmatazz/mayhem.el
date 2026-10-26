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

(defun mayhem-core-tests--response (status body &optional raw)
  "Run `mayhem--api-response' on an HTTP STATUS response with BODY.
RAW is as for `mayhem--api-response'."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert "HTTP/1.1 " (number-to-string status) "\n")
    ;; As url.el leaves it: before the blank line ending the headers.
    (setq-local url-http-end-of-headers (point))
    (setq-local url-http-response-status status)
    (insert "\n" body)
    (mayhem--api-response nil raw)))

(ert-deftest mayhem-core-test-api-response-parses-json ()
  (should (equal (mayhem-core-tests--response 200 "{\"slug\":\"me\",\"x\":[1,null]}")
                 '(t ((slug . "me") (x 1 nil))))))

(ert-deftest mayhem-core-test-api-response-raw-keeps-bytes ()
  (let ((bytes (unibyte-string 10 0 255 ?x)))
    (should (equal (mayhem-core-tests--response 200 bytes t) (list t bytes)))))

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
                 '(("p" "a" "b") ("p" "c") ("empty")))))

(ert-deftest mayhem-core-test-workspaces ()
  (should (equal (mayhem--workspaces '(((owner . "zed")) ((owner . "acme"))
                                       ((owner . "zed"))))
                 '(("acme" . 1) ("zed" . 2)))))

(ert-deftest mayhem-core-test-search-candidates ()
  (should (equal (mayhem--search-candidates
                  '(((owner . "zed") (slug . "p"))
                    ((owner . "acme") (slug . "q"))
                    ((owner . "acme") (slug . "r")))
                  '(("acme" ((owner . "acme") (project_slug . "q") (slug . "t")))
                    ("zed" ((owner . "zed") (project_slug . "other") (slug . "x")))))
                 '("acme" "acme/q" "acme/q/t" "acme/r" "zed" "zed/p"))))

(ert-deftest mayhem-core-test-target-types ()
  (let ((types (mayhem--target-types
                '(("acme" ((owner . "acme") (project_slug . "q") (slug . "t") (type . "api"))
                   ((owner . "acme") (project_slug . "q") (slug . "u") (type . "code")))))))
    (should (equal (gethash "acme/q/t" types) "api"))
    (should (equal (gethash "acme/q/u" types) "code"))
    (should-not (gethash "acme/q/v" types))))

(ert-deftest mayhem-core-test-target-summary ()
  (let ((target (mayhem--target-summary '((owner . "acme") (project_slug . "p") (slug . "t")
                                          (type . "code") (latest_run . big)))))
    (should (equal (alist-get 'slug target) "t"))
    (should (equal (alist-get 'type target) "code"))
    (should-not (assq 'latest_run target))))

(ert-deftest mayhem-core-test-user-label ()
  (should (equal (mayhem--user-label '((username . "jd") (first_name . "Jo")
                                       (last_name . "Doe")))
                 "Jo Doe (jd)"))
  (should (equal (mayhem--user-label '((slug . "jd") (username . "jd"))) "jd")))

(ert-deftest mayhem-core-test-project-summary ()
  (should (equal (alist-get 'slug (mayhem--project-summary '((slug . "p") (settings . big))))
                 "p"))
  (should-not (assq 'settings (mayhem--project-summary '((slug . "p") (settings . big))))))

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

(ert-deftest mayhem-core-test-format-age-exact-time ()
  (let* ((now (encode-time (iso8601-parse "2026-10-19T12:00:00+00:00")))
         (age (mayhem--format-age "2026-10-16T12:00:00+00:00" now))
         (exact (format-time-string "%a %Y-%m-%d %H:%M:%S %Z"
                                    (encode-time (iso8601-parse "2026-10-16T12:00:00+00:00")))))
    (should (equal (get-text-property 0 'help-echo age) exact))
    (should (equal (get-text-property 0 'mayhem-ts age) exact))))

(ert-deftest mayhem-core-test-format-elapsed ()
  (should (equal (mayhem--format-elapsed 0) "0:00"))
  (should (equal (mayhem--format-elapsed 292.9) "4:52"))
  (should (equal (mayhem--format-elapsed 3723) "1:02:03")))

(ert-deftest mayhem-core-test-step-series ()
  ;; Each of 4 steps of 10 s takes the last point by its end.
  (should (equal (mayhem--step-series '((0 . 1) (12 . 5) (31 . 9)) 40 4) '(1 5 5 9)))
  (should (equal (mayhem--step-series '((15 . 2)) 40 4) '(0 2 2 2)))
  (should (equal (mayhem--step-series nil 40 2) '(0 0))))

(ert-deftest mayhem-core-test-bar-rows ()
  (should (equal (mayhem--bar-rows '(0 1 4 8) 1) '(" ▁▄█")))
  (should (equal (mayhem--bar-rows '(0 1 8) 2) '("  █" " ▂█"))))

(ert-deftest mayhem-core-test-stack-rows ()
  ;; A cell takes the colour of the layer at its lowest eighth.
  (should (equal (mayhem--stack-rows '((1 1) (0 2) (0 0)) 1)
                 '(((?█ . 0) (?█ . 1) (?\s)))))
  (should (equal (mayhem--stack-rows '((1 1)) 2) '(((?█ . 1)) ((?█ . 0))))))

(ert-deftest mayhem-core-test-testcase-summary ()
  (should (equal (mayhem--testcase-summary
                  '((sha256 . "ab") (n_defects . 3) (is_regression) (maps . "big")
                    (defects ((severity_level . "high")) ((severity_level . "medium"))
                             ((severity_level . "high")))))
                 '((sha256 . "ab") (is_regression) (n_defects . 3) (execution_time)
                   (created_at) (high . 2) (medium . 1) (low . 0)))))

(ert-deftest mayhem-core-test-format-duration ()
  (should (equal (mayhem--format-duration 45) "45s"))
  (should (equal (mayhem--format-duration 200) "3m 20s"))
  (should (equal (mayhem--format-duration 3900) "1h 5m"))
  (should-not (mayhem--format-duration nil)))

(ert-deftest mayhem-core-test-pick ()
  (should (equal (mayhem--pick '((a . 1) (b . 2) (c . 3)) '(c a z))
                 '((c . 3) (a . 1) (z)))))

(ert-deftest mayhem-core-test-target-defect ()
  (let ((defect (mayhem--target-defect '((defect_number . 3) (title . "t") (secret . "x")))))
    (should (equal (alist-get 'defect_number defect) 3))
    (should-not (assq 'secret defect))))

(ert-deftest mayhem-core-test-run-summary ()
  (let ((run (mayhem--run-summary
              '((api_run (target . 1)) (duration . 300) (secret . "x")
                (run_attributes (n_lines_total . 10))
                (phases ((phase_name . "dynamic_analysis") (status . "completed")
                         (msg . "false")))
                (run_files ((path . "Mayhemfile") (sha256 . "ab") (extract)))))))
    (should (eq (alist-get 'api_run run) t))
    (should (equal (alist-get 'duration run) 300))
    (should (equal (alist-get 'n_lines_total run) 10))
    (should-not (assq 'secret run))
    (should (equal (alist-get 'status (car (alist-get 'phases run))) "completed"))
    (should-not (assq 'msg (car (alist-get 'phases run))))
    (should (equal (alist-get 'run_files run) '(((path . "Mayhemfile") (sha256 . "ab")))))))

(ert-deftest mayhem-core-test-format-value ()
  (should (equal (mayhem--format-value "img:1") "img:1"))
  (should (equal (mayhem--format-value 2) "2"))
  (should (equal (mayhem--format-value '("a" "b")) "a, b"))
  (should (equal (mayhem--format-value '((url . "tcp://x") (timeout . 2)))
                 "{\"url\":\"tcp://x\",\"timeout\":2}"))
  ;; A Mayhemfile's tasks read as their names.
  (should (equal (mayhem--format-value '(((name . "regression_testing"))
                                         ((name . "behavior_testing") (duration . 60))))
                 "regression_testing, behavior_testing {\"duration\":60}")))

(ert-deftest mayhem-core-test-decode-base64 ()
  (should (equal (mayhem--decode-base64 (base64-encode-string "GET / HTTP/1.1")) "GET / HTTP/1.1"))
  (should-not (mayhem--decode-base64 nil))
  (should-not (mayhem--decode-base64 "not base64!")))

(ert-deftest mayhem-core-test-code-evidence ()
  (let ((evidence (mayhem--code-evidence
                   '((count . 3)
                     (testcase_reports ((sha256 . "aa") (run_number . 3) (execution_time . 0.1)
                                        (crash_type . "abort") (backtrace . "#0 main")
                                        (registers . "big"))
                                       ((sha256 . "bb") (run_number . 1)
                                        (crash_type . "other")))))))
    (should (equal (alist-get 'count evidence) 3))
    (should (equal (alist-get 'run_number evidence) 3))
    (should (equal (alist-get 'testcases evidence)
                   '(((sha256 . "aa") (run_number . 3) (execution_time . 0.1))
                     ((sha256 . "bb") (run_number . 1) (execution_time)))))
    (should (equal (alist-get 'crash_type evidence) "abort"))
    (should (equal (alist-get 'backtrace evidence) "#0 main"))
    (should-not (alist-get 'frames evidence))
    (should-not (assq 'registers evidence))))

(ert-deftest mayhem-core-test-backtrace-frames ()
  (should (equal (mayhem--backtrace-frames
                  '(((fn . "main") (src . "/app/m.c:3:1") (ip . 1))
                    ((fn . "f at a.c:1:2 (inlined by) g at b.c:3:4 (inlined by) h")
                     (src . "c.c:5:6"))
                    ((fn . "rust::x+0x1") (src . "??:0:0"))))
                 '((("main" . "/app/m.c:3:1"))
                   (("f" . "a.c:1:2") ("g" . "b.c:3:4") ("h" . "c.c:5:6"))
                   (("rust::x+0x1")))))
  (should-not (mayhem--backtrace-frames nil)))

(ert-deftest mayhem-core-test-format-stacktrace ()
  (should (equal (mayhem--format-stacktrace
                  '((V1 (frames ((path . "a.py") (line . 3) (function . "f")
                                 (snippet . "x()"))
                                ((path . "b.py") (line . 9) (function . "g"))))))
                 "a.py:3 in f\n    x()\nb.py:9 in g"))
  (should-not (mayhem--format-stacktrace nil)))

(ert-deftest mayhem-core-test-url-page ()
  (let ((h "app.mayhem.security")
        (base "https://app.mayhem.security/o/p/t"))
    (should (equal (mayhem--url-page "https://app.mayhem.security/" h) '(dashboard)))
    (should (equal (mayhem--url-page "https://APP.mayhem.security/o" h) '(workspace "o")))
    (should (equal (mayhem--url-page "https://app.mayhem.security/o/p" h) '(project "o" "p")))
    (should (equal (mayhem--url-page base h) '(target "o" "p" "t")))
    (should (equal (mayhem--url-page (concat base "/1") h) '(run "o" "p" "t" 1)))
    (should (equal (mayhem--url-page (concat base "/1/defects") h) '(run "o" "p" "t" 1)))
    (should (equal (mayhem--url-page (concat base "/1?defect=34&exampleTestcase=ba0d") h)
                   '(defect "o" "p" "t" 34 1)))
    (should (equal (mayhem--url-page (concat base "/-/defects/34") h)
                   '(defect "o" "p" "t" 34 nil)))
    (should (equal (mayhem--url-page (concat base "/-/defects/34/runs/2") h)
                   '(defect "o" "p" "t" 34 2)))
    (should-not (mayhem--url-page "https://app.mayhem.security/-/settings/user" h))
    (should-not (mayhem--url-page "https://app.mayhem.security/o/-/projects" h))
    (should (equal (mayhem--url-page (concat base "/1/tests?testcase=ab12") h)
                   '(testcase "o" "p" "t" 1 "ab12")))
    (should-not (mayhem--url-page (concat base "/1/tests") h))
    (should-not (mayhem--url-page (concat base "/1/testcases/ab") h))
    (should-not (mayhem--url-page "https://example.com/o" h))
    (should-not (mayhem--url-page "mailto:x@app.mayhem.security" h))))

(ert-deftest mayhem-core-test-page-url-round-trips ()
  (dolist (page '((dashboard) (workspace "o") (project "o" "p") (target "o" "p" "t")
                  (run "o" "p" "t" 1) (defect "o" "p" "t" 34 1) (defect "o" "p" "t" 34 nil)
                  (testcase "o" "p" "t" 1 "ab12")))
    (should (equal (mayhem--url-page (mayhem--page-url "https://app.mayhem.security/" page)
                                     "app.mayhem.security")
                   page)))
  (should (equal (mayhem--page-url "https://h/" '(defect "o" "p" "t" 34 1))
                 "https://h/o/p/t/1?defect=34")))

(ert-deftest mayhem-core-test-page-url-target-lists ()
  (should (equal (mayhem--page-url "https://h/" '(target-runs "o" "p" "t")) "https://h/o/p/t"))
  (should (equal (mayhem--page-url "https://h/" '(target-defects "o" "p" "t")) "https://h/o/p/t")))

(ert-deftest mayhem-core-test-clean-url ()
  (should (equal (mayhem--clean-url "https://github.com:443/o/r//actions/runs/7")
                 "https://github.com/o/r/actions/runs/7"))
  (should (equal (mayhem--clean-url "http://ci.example:80") "http://ci.example"))
  (should (equal (mayhem--clean-url "https://ci.example:8443/job/1")
                 "https://ci.example:8443/job/1"))
  (should-not (mayhem--clean-url nil)))

(ert-deftest mayhem-core-test-repo ()
  (dolist (url '("git@github.com:o/r.git" "https://github.com:443/o/r/"
                 "https://github.com/o/r.git" "https://github.com/o/r"
                 "ssh://git@github.com/o/r.git"))
    (should (equal (mayhem--repo url) '("github.com" . "o/r"))))
  (should (equal (mayhem--repo "git@gitlab.com:group/sub/r.git")
                 '("gitlab.com" . "group/sub/r")))
  (should-not (mayhem--repo "https://github.com/o"))
  (should-not (mayhem--repo nil)))

(ert-deftest mayhem-core-test-image-url ()
  (should (equal (mayhem--image-url "ethan42/exim4:stretch-20171101-6")
                 "https://hub.docker.com/r/ethan42/exim4/tags?name=stretch-20171101-6"))
  (should (equal (mayhem--image-url "debian") "https://hub.docker.com/_/debian"))
  (should (equal (mayhem--image-url "docker.io/library/debian:stretch@sha256:ab")
                 "https://hub.docker.com/_/debian/tags?name=stretch"))
  (should (equal (mayhem--image-url "ghcr.io/o/r:1") "https://ghcr.io/o/r"))
  (should-not (mayhem--image-url "registry.example.com:5000/o/r:1"))
  (should-not (mayhem--image-url "localhost/o/r")))

(ert-deftest mayhem-core-test-repo-url ()
  (let ((github '("github.com" . "o/r")))
    (should (equal (mayhem--repo-url github) "https://github.com/o/r"))
    (should (equal (mayhem--repo-url github 'branch "feature/x")
                   "https://github.com/o/r/tree/feature/x"))
    (should (equal (mayhem--repo-url github 'commit "abc")
                   "https://github.com/o/r/commit/abc")))
  (should (equal (mayhem--repo-url '("gitlab.example" . "g/r") 'commit "abc")
                 "https://gitlab.example/g/r/-/commit/abc"))
  (should (equal (mayhem--repo-url '("bitbucket.org" . "o/r") 'branch "main")
                 "https://bitbucket.org/o/r/src/main"))
  (should (equal (mayhem--repo-url '("git.example" . "o/r")) "https://git.example/o/r"))
  (should-not (mayhem--repo-url '("git.example" . "o/r") 'commit "abc")))

(ert-deftest mayhem-core-test-ci-label ()
  (should (equal (mayhem--ci-label "GitHubActions" "https://github.com/o/r/actions/runs/42")
                 "GitHub Actions run 42"))
  (should (equal (mayhem--ci-label "Jenkins" "https://ci/job/1") "Jenkins  https://ci/job/1"))
  (should (equal (mayhem--ci-label nil "https://ci/job/1") "https://ci/job/1")))

(defun mayhem-core-tests--tar (files)
  "Return FILES, each (NAME . CONTENTS), as a ustar archive."
  (let ((field (lambda (s size) (concat s (make-string (- size (length s)) 0)))))
    (concat
     (mapconcat
      (pcase-lambda (`(,name . ,contents))
        (concat (funcall field name 100) (funcall field "0000644" 8)
                (funcall field "0000000" 8) (funcall field "0000000" 8)
                (funcall field (format "%011o" (length contents)) 12)
                (funcall field "00000000000" 12) (make-string 8 ?\s) "0"
                (funcall field "" 100) (funcall field "ustar" 6) "00"
                (make-string 247 0)
                contents (make-string (% (- 512 (% (length contents) 512)) 512) 0)))
      files "")
     (make-string 1024 0))))

(ert-deftest mayhem-core-test-tar-files ()
  (let ((tar (mayhem-core-tests--tar '(("testsuite/a" . "hello") ("b" . "")))))
    (should (= (% (length tar) 512) 0))
    (should (equal (mayhem--tar-files tar) '(("testsuite/a" . "hello") ("b" . ""))))
    (should (equal (mayhem--tar-files "") nil))
    ;; Names padded with spaces, as the Mayhem server writes them.
    (should (equal (mayhem--tar-files (concat "x" (make-string 99 ?\s) (substring tar 100)))
                   '(("x" . "hello") ("b" . ""))))))

(ert-deftest mayhem-core-test-testsuite-files-keeps-test-cases ()
  ;; Only files named by the sha256 of their contents are test cases.
  (let* ((bytes (unibyte-string 0 1 255 ?A))
         (sha (secure-hash 'sha256 bytes))
         (tar (mayhem-core-tests--tar (list (cons (concat "testsuite/" sha) bytes)
                                            (cons "testsuite/meta.json" "{}")
                                            (cons (concat "testsuite/" (make-string 64 ?0))
                                                  "damaged")))))
    (should (equal (mayhem--testsuite-files tar) (list (cons sha bytes)))))
  (should-error (mayhem--testsuite-files (mayhem-core-tests--tar '(("testsuite/x" . "y")))))
  (should-not (mayhem--testsuite-files (make-string 1024 0))))

(ert-deftest mayhem-core-test-hexdump-bytes ()
  (should (equal (mayhem--hexdump-bytes
                  (concat "0000000: 4548 4c4f 2041 4141 4141 4141 4141 0a00 EHLO AAAAAAAAA..\n"
                          "0000010: 4141 41 AAA"))
                 "EHLO AAAAAAAAA\n\0AAA"))
  ;; Padded as xxd pads, with a text column that looks like hex.
  (should (equal (mayhem--hexdump-bytes "0000000: 4142                                     AB")
                 "AB"))
  (should (equal (mayhem--bytes-text (unibyte-string ?A 10 0 255)) "A\n\\x00\\xff")))

(ert-deftest mayhem-core-test-bytes-preview ()
  (should (equal (mayhem--bytes-preview (unibyte-string ?G ?E ?T 0 10 255 ?/)) "GET.../"))
  (should (equal (length (mayhem--bytes-preview (make-string 100 ?x)))
                 mayhem--preview-length)))

(ert-deftest mayhem-core-test-testsuite-page-url ()
  (should (equal (mayhem--page-url "https://h/" '(testsuite "o" "p" "t" 7)) "https://h/o/p/t/7/tests"))
  (should (equal (mayhem--page-url "https://h/" '(testcases "o" "p" "t" 7)) "https://h/o/p/t/7/tests"))
  (should (equal (mayhem--page-url "https://h/" '(run-log "o" "p" "t" 7)) "https://h/o/p/t/7")))

(provide 'mayhem-core-tests)
;; A long command wraps between words, never inside a quote.
(ert-deftest mayhem-core-test-split-command-wraps ()
  (should (equal (mayhem--split-command "A=1 /bin/x 0123456789" 16)
                 "A=1 /bin/x \\\n  0123456789"))
  (should (equal (mayhem--split-command "a && /bin/x 'q r' s" 12)
                 "a && \\\n  /bin/x \\\n    'q r' \\\n    s"))
  (should (equal (mayhem--split-command "a && b") "a && \\\n  b")))

;;; mayhem-core-tests.el ends here
