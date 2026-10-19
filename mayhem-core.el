;;; mayhem-core.el --- Mayhem API access for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Talks to the Mayhem REST API asynchronously, authenticating with the
;; URL and token from the Mayhem CLI's config file.  Parsing and
;; shaping are pure functions so they can be tested without a server.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'url)
(require 'url-http)
(require 'url-parse)
(require 'iso8601)

(defvar url-http-response-status)
(defvar url-http-end-of-headers)

(defgroup mayhem nil
  "Emacs client for Mayhem."
  :group 'tools
  :prefix "mayhem-")

(defcustom mayhem-config-file
  (expand-file-name "mayhem/mayhem"
                    (or (getenv "XDG_CONFIG_HOME") "~/.config"))
  "The Mayhem CLI's config file, holding the API `url' and `token'."
  :type 'file)

(defconst mayhem--page-size 100
  "Items per page when listing; the API allows at most 100.")

(defun mayhem--parse-config (text)
  "Parse TEXT, an INI config, into an alist of its [DEFAULT] keys.
Keys are symbols, values strings."
  (let ((section nil) result)
    (dolist (line (split-string text "\n" t "[ \t\r]+"))
      (cond ((string-match "\\`\\[\\(.*\\)\\]\\'" line)
             (setq section (match-string 1 line)))
            ((and (equal section "DEFAULT")
                  (string-match "\\`\\([^=:#;]+?\\)[ \t]*[=:][ \t]*\\(.*\\)\\'"
                                line))
             (push (cons (intern (match-string 1 line)) (match-string 2 line))
                   result))))
    (nreverse result)))

(defun mayhem--read-config ()
  "Return `mayhem-config-file' parsed, signalling if it lacks a token."
  (let ((config (and (file-readable-p mayhem-config-file)
                     (with-temp-buffer
                       (insert-file-contents mayhem-config-file)
                       (mayhem--parse-config (buffer-string))))))
    (unless (and (alist-get 'url config) (alist-get 'token config))
      (user-error "No Mayhem url and token in %s; run `mayhem login'"
                  mayhem-config-file))
    config))

(defun mayhem--api-url (base path &optional params)
  "Return the URL of PATH on the server at BASE, with query PARAMS.
PARAMS is a list of (NAME VALUE) as for `url-build-query-string'."
  (concat (string-trim-right base "/") path
          (and params (concat "?" (url-build-query-string params)))))

(defun mayhem--api-response (status)
  "Return (OK DATA) for the HTTP response in the current buffer.
STATUS is the plist `url-retrieve' passes its callback.  DATA is the
parsed JSON body on success, else an error message."
  (if (not (and (boundp 'url-http-end-of-headers) url-http-end-of-headers))
      (list nil (if-let* ((err (plist-get status :error)))
                    ;; url.el signals e.g. (error connection-failed "..." :host ...).
                    (mapconcat (lambda (x) (string-trim (format "%s" x)))
                               (take 2 (cdr err)) " ")
                  "No response"))
    (let* ((body (decode-coding-string
                  (buffer-substring-no-properties url-http-end-of-headers
                                                  (point-max))
                  'utf-8))
           (json (ignore-errors
                   (json-parse-string body :object-type 'alist
                                      :array-type 'list
                                      :null-object nil :false-object nil))))
      (if (<= 200 url-http-response-status 299)
          (list t json)
        (list nil (format "HTTP %d: %s" url-http-response-status
                          (or (and (consp json) (alist-get 'message json))
                              (string-trim body))))))))

(defun mayhem--api-get (path params callback)
  "GET PATH with query PARAMS from the Mayhem API in the background.
Call CALLBACK with (OK DATA): OK is non-nil on success, DATA is the
parsed JSON (objects as alists, arrays as lists) or an error message."
  (condition-case err
      (let* ((config (mayhem--read-config))
             (url-request-extra-headers
              `(("X-Mayhem-Token" . ,(concat "token " (alist-get 'token config)))
                ("Accept" . "application/json"))))
        (url-retrieve (mayhem--api-url (alist-get 'url config) path params)
                      (lambda (status)
                        (let ((result (condition-case err
                                          (mayhem--api-response status)
                                        (error (list nil (error-message-string err))))))
                          (kill-buffer (current-buffer))
                          (apply callback result)))
                      nil t t))
    (error (run-at-time 0 nil callback nil (error-message-string err)))))

(defun mayhem--api-get-all (path key callback &optional params offset items)
  "GET every page of the list under KEY at PATH, with query PARAMS.
Call CALLBACK with (OK DATA): DATA is all the items, or an error
message.  OFFSET and ITEMS carry the pages fetched so far."
  (let ((offset (or offset 0)))
    (mayhem--api-get
     path `((per_page ,mayhem--page-size) (offset ,offset) ,@params)
     (lambda (ok data)
       (if (not ok)
           (funcall callback nil data)
         (let ((page (alist-get key data)))
           ;; Not every list reports a total count, so stop on a short page.
           (if (< (length page) mayhem--page-size)
               (funcall callback t (append items page))
             (mayhem--api-get-all path key callback params
                                  (+ offset mayhem--page-size)
                                  (append items page)))))))))

(defun mayhem--pick (alist fields)
  "Return ALIST with only FIELDS, in their order."
  (mapcar (lambda (field) (cons field (alist-get field alist))) fields))

(defconst mayhem--project-fields
  '(owner slug project_name n_defects_active_high n_defects_active_medium
          n_defects_active_low updated_at)
  "Fields of a project kept in the list of every project.")

(defun mayhem--project-summary (project)
  "Return PROJECT, an alist, with only `mayhem--project-fields'."
  (mayhem--pick project mayhem--project-fields))

(defun mayhem--fetch-projects (callback)
  "Fetch every project visible to the user, across workspaces.
Call CALLBACK with (OK DATA): DATA is a list of project alists, as
`mayhem--project-summary' trims them, or an error message."
  (mayhem--api-get
   "/api/v2/user/me" nil
   (lambda (ok me)
     (if (not ok)
         (funcall callback nil me)
       (mayhem--api-get-all
        (mayhem--path "/api/v2/user/%s/project" (alist-get 'slug me))
        'projects
        (lambda (ok projects)
          (funcall callback ok (if ok (mapcar #'mayhem--project-summary projects)
                                 projects))))))))

(defun mayhem--workspaces (projects)
  "Return the workspaces of PROJECTS as (OWNER . PROJECT-COUNT), by name."
  (let (counts)
    (dolist (project projects)
      (let* ((owner (alist-get 'owner project))
             (cell (assoc owner counts)))
        (if cell
            (setcdr cell (1+ (cdr cell)))
          (push (cons owner 1) counts))))
    (sort counts (lambda (a b) (string< (car a) (car b))))))

(defun mayhem--fetch-workspace-targets (owner callback)
  "Fetch every target of the workspace OWNER.
Call CALLBACK with (OK DATA): DATA is a list of target alists, or an
error message."
  (mayhem--api-get-all (mayhem--path "/api/v2/owner/%s/target" owner)
                       'targets callback))

(defun mayhem--group-targets (projects targets)
  "Return PROJECTS with their TARGETS, as from the API.
Each element is (PROJECT-SLUG . TARGET-SLUGS); both keep the API's
order.  Targets of other projects are dropped."
  (mapcar (lambda (project)
            (let ((owner (alist-get 'owner project))
                  (slug (alist-get 'slug project)))
              (cons slug
                    (delq nil
                          (mapcar (lambda (target)
                                    (and (equal (alist-get 'owner target) owner)
                                         (equal (alist-get 'project_slug target) slug)
                                         (alist-get 'slug target)))
                                  targets)))))
          projects))

;;;; Pages' data

(defun mayhem--host ()
  "Return the host of the configured Mayhem server, or nil without a config."
  (ignore-errors
    (url-host (url-generic-parse-url (alist-get 'url (mayhem--read-config))))))

(defun mayhem--fetch-me (callback)
  "Fetch the user logged in.
Call CALLBACK with (OK DATA): DATA is the user's `slug', `username',
`first_name' and `last_name', or an error message."
  (mayhem--api-get "/api/v2/user/me" nil
                   (lambda (ok me)
                     (funcall callback ok
                              (if ok (mayhem--pick me '(slug username first_name last_name))
                                me)))))

(defun mayhem--user-label (user)
  "Return USER, as from `mayhem--fetch-me', as \"First Last (username)\".
Without a name, just the username."
  (let ((name (string-join (delq nil (list (alist-get 'first_name user)
                                           (alist-get 'last_name user)))
                           " "))
        (username (or (alist-get 'username user) (alist-get 'slug user))))
    (if (string-empty-p name)
        username
      (format "%s (%s)" name username))))

(defun mayhem--search-candidates (projects targets)
  "Return the workspaces, projects and targets of PROJECTS, to search.
TARGETS is an alist of each owner to its targets, as from the API.
Each is \"owner\", \"owner/project\" or \"owner/project/target\",
each workspace followed by its projects, each by its targets."
  (mapcan (pcase-lambda (`(,owner . ,_))
            (cons owner
                  (mapcan (pcase-lambda (`(,project . ,slugs))
                            (let ((path (concat owner "/" project)))
                              (cons path (mapcar (lambda (slug) (concat path "/" slug))
                                                 slugs))))
                          (mayhem--group-targets
                           (seq-filter (lambda (p) (equal (alist-get 'owner p) owner))
                                       projects)
                           (cdr (assoc owner targets))))))
          (mayhem--workspaces projects)))

(defun mayhem--path (format-string &rest segments)
  "Return FORMAT-STRING with SEGMENTS, each URL-encoded, in place of its %s."
  (apply #'format format-string (mapcar #'url-hexify-string segments)))

(defun mayhem--fetch-each (fetches callback)
  "Run FETCHES at once, each (KEY . FUNCTION).
FUNCTION is called with a callback for (OK DATA).  Call CALLBACK
with (OK DATA): DATA is an alist of each KEY to its data, in FETCHES' order,
or the first error message."
  (let ((left (length fetches)) (results nil) (failed nil))
    (if (zerop left)
        (funcall callback t nil)
      (pcase-dolist (`(,key . ,fn) fetches)
        (funcall fn (lambda (ok data)
                      (cond (failed)
                            ((not ok) (setq failed t) (funcall callback nil data))
                            (t (push (cons key data) results)
                               (when (zerop (setq left (1- left)))
                                 (funcall callback t
                                          (mapcar (lambda (f) (assq (car f) results))
                                                  fetches)))))))))))

(defun mayhem--fetch-project (owner project callback)
  "Fetch PROJECT of OWNER with its targets.
Call CALLBACK with (OK DATA): DATA is an alist with `project' and
`targets', or an error message."
  (mayhem--fetch-each
   `((project . ,(lambda (cb)
                   (mayhem--api-get (mayhem--path "/api/v2/owner/%s/project/%s"
                                                  owner project)
                                    nil cb)))
     (targets . ,(lambda (cb)
                   (mayhem--api-get-all (mayhem--path "/api/v2/owner/%s/project/%s/target"
                                                      owner project)
                                        'targets cb))))
   callback))

(defconst mayhem--runs-shown 20
  "How many of a target's latest runs its page shows.")

(defun mayhem--fetch-target (owner project target callback)
  "Fetch TARGET of PROJECT of OWNER, with its latest run list.
Call CALLBACK with (OK DATA): DATA is an alist with `target' and `runs',
the latter as the API lists them (`count' and `runs'), or an error
message."
  (let ((path (mayhem--path "/api/v2/owner/%s/project/%s/target/%s"
                            owner project target)))
    (mayhem--fetch-each
     `((target . ,(lambda (cb) (mayhem--api-get path nil cb)))
       (runs . ,(lambda (cb)
                  (mayhem--api-get (concat path "/run")
                                   `((per_page ,mayhem--runs-shown)) cb))))
     callback)))

(defconst mayhem--run-fields
  '(run_id run_number description pending started stopped ended failed
           started_at ended_at duration started_by branch_name revision
           scm_commit_subject n_defects tests_run edges_covered api_run)
  "Fields of a run kept for its page.")

(defun mayhem--fetch-run (owner project target number callback)
  "Fetch run NUMBER of TARGET of PROJECT of OWNER, with its defects.
An API run's endpoints come too.  Call CALLBACK with (OK DATA): DATA is
an alist with `run', `defects' and `endpoints' (nil for a code run),
each trimmed to the fields its page shows, or an error message."
  (let ((path (mayhem--path "/api/v2/owner/%s/project/%s/target/%s/run/%s"
                            owner project target (format "%s" number))))
    (mayhem--api-get
     path nil
     (lambda (ok run)
       (if (not ok)
           (funcall callback nil run)
         (let ((api (alist-get 'api_run run)))
           (mayhem--fetch-each
            `((run . ,(lambda (cb)
                        (funcall cb t (mayhem--pick
                                       (cons (cons 'api_run (and api t)) run)
                                       mayhem--run-fields))))
              ;; Defects filter on the run's id, not its number.
              (defects . ,(lambda (cb)
                            (mayhem--api-get-all
                             (mayhem--path "/api/v2/owner/%s/project/%s/defect"
                                           owner project)
                             'defects
                             (lambda (ok data)
                               (funcall cb ok (if ok (mapcar (lambda (d)
                                                               (mayhem--pick
                                                                d '(defect_number severity_level
                                                                    title state)))
                                                             data)
                                                data)))
                             `((run ,(alist-get 'run_id run))))))
              (endpoints . ,(lambda (cb)
                              (if (not api)
                                  (funcall cb t nil)
                                (mayhem--api-get-all
                                 (concat path "/endpoints") 'endpoints
                                 (lambda (ok data)
                                   (funcall cb ok (if ok (mapcar (lambda (e)
                                                                   (mayhem--pick
                                                                    e '(method path passing
                                                                        covered defects_total)))
                                                                 data)
                                                    data))))))))
            callback)))))))

(defconst mayhem--defect-fields
  '(defect_number title severity severity_level state source cwe_number
                  cwe_type cwe_link defect_class_name description first_seen
                  last_seen last_seen_run_number)
  "Fields of a defect kept for its page.")

(defconst mayhem--evidence-max 4000
  "Most characters of a request, response or backtrace kept for a page.")

(defun mayhem--decode-base64 (string)
  "Return STRING, base64 of UTF-8 text, decoded and cut to `mayhem--evidence-max'.
Return nil when STRING is nil or not base64."
  (when-let* ((raw (and string (ignore-errors (base64-decode-string string)))))
    (truncate-string-to-width (decode-coding-string raw 'utf-8) mayhem--evidence-max
                              nil nil "…")))

(defun mayhem--format-stacktrace (stacktrace)
  "Return STACKTRACE, an API issue's frames, as text, or nil without frames.
Each frame is \"path:line in function\", its source line indented below."
  (when-let* ((frames (alist-get 'frames (alist-get 'V1 stacktrace))))
    (truncate-string-to-width
     (mapconcat (lambda (frame)
                  (concat (format "%s:%s in %s"
                                  (alist-get 'path frame) (alist-get 'line frame)
                                  (alist-get 'function frame))
                          (when-let* ((snippet (alist-get 'snippet frame)))
                            (concat "\n    " snippet))))
                frames "\n")
     mayhem--evidence-max nil nil "…")))

(defun mayhem--api-evidence (issue)
  "Return the evidence of an API run's ISSUE.
That is its endpoint, the server's stack trace and the HTTP exchange."
  (append (mayhem--pick issue '(method path endpoint_name))
          (list (cons 'stacktrace (mayhem--format-stacktrace (alist-get 'stacktrace issue)))
                (cons 'request (mayhem--decode-base64 (alist-get 'request issue)))
                (cons 'response (mayhem--decode-base64 (alist-get 'response issue))))))

(defun mayhem--code-evidence (reports)
  "Return the evidence of a code defect from its test case REPORTS.
That is how many there are, and the first's crash and backtrace."
  (let ((first (car (alist-get 'testcase_reports reports))))
    (append (list (cons 'count (alist-get 'count reports)))
            (mayhem--pick first '(crash_type signal_number repro_cmdline))
            (list (cons 'backtrace
                        (when-let* ((bt (alist-get 'backtrace first)))
                          (truncate-string-to-width bt mayhem--evidence-max nil nil "…")))))))

(defun mayhem--fetch-defect (owner project target number run callback)
  "Fetch defect NUMBER of TARGET of PROJECT of OWNER, with its evidence.
Call CALLBACK with (OK DATA): DATA is an alist with `defect' and
`evidence', each trimmed to what its page shows, or an error message.
An API defect's evidence is the HTTP exchange of RUN, a run number, or
else of the last run that saw it; a code defect's, its first test
case's crash."
  (let ((path (mayhem--path "/api/v2/owner/%s/project/%s/target/%s"
                            owner project target)))
    (mayhem--api-get
     (concat path (format "/defect/%s" number)) nil
     (lambda (ok defect)
       (if (not ok)
           (funcall callback nil defect)
         (let ((done (lambda (ok evidence)
                       (funcall callback ok
                                (if ok `((defect . ,(mayhem--pick defect mayhem--defect-fields))
                                         (run . ,run)
                                         (evidence . ,evidence))
                                  evidence))))
               ;; A defect gives its last run's id, but evidence needs a number.
               (run (or run (alist-get 'last_seen_run_number defect))))
           (cond
            ((and (equal (alist-get 'source defect) "api") run)
             (mayhem--api-get (concat path (format "/run/%s/api/rest/issue/%s" run number)) nil
                              (lambda (ok issue)
                                (funcall done ok (if ok (mayhem--api-evidence issue) issue)))))
            ((equal (alist-get 'source defect) "code")
             (mayhem--api-get (concat path (format "/defect/%s/testcase_report" number))
                              '((per_page 1))
                              (lambda (ok reports)
                                (funcall done ok (if ok (mayhem--code-evidence reports) reports)))))
            (t (funcall done t nil)))))))))

(defun mayhem--format-duration (seconds)
  "Return SECONDS as \"1h 5m\", \"3m 20s\" or \"45s\"; nil gives nil."
  (when seconds
    (let* ((s (truncate seconds)) (h (/ s 3600)) (m (/ (% s 3600) 60)) (sec (% s 60)))
      (cond ((> h 0) (format "%dh %dm" h m))
            ((> m 0) (format "%dm %ds" m sec))
            (t (format "%ds" sec))))))

(defun mayhem--run-status (run)
  "Return the status of RUN, an alist as the API gives it, as a string."
  (cond ((alist-get 'failed run) "failed")
        ((alist-get 'stopped run) "stopped")
        ((alist-get 'ended run) "completed")
        ((alist-get 'started run) "running")
        ((alist-get 'pending run) "pending")
        (t "unknown")))

(defun mayhem--format-age (timestamp now)
  "Return how long before NOW, a time value, TIMESTAMP was, as \"3 days ago\".
TIMESTAMP is an ISO 8601 string, as the API gives; nil gives nil."
  (when timestamp
    (let ((secs (float-time (time-subtract now (encode-time (iso8601-parse timestamp))))))
      (pcase-let ((`(,n ,unit)
                   (cond ((< secs 60) '(0 nil))
                         ((< secs 3600) (list (/ secs 60) "minute"))
                         ((< secs 86400) (list (/ secs 3600) "hour"))
                         ((< secs (* 30 86400)) (list (/ secs 86400) "day"))
                         ((< secs (* 365 86400)) (list (/ secs (* 30 86400)) "month"))
                         (t (list (/ secs (* 365 86400)) "year")))))
        (if (null unit)
            "just now"
          (let ((n (truncate n)))
            (format "%d %s%s ago" n unit (if (= n 1) "" "s"))))))))

(provide 'mayhem-core)
;;; mayhem-core.el ends here
