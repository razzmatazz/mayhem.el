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
(require 'eldoc)
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

(defun mayhem--api-response (status &optional raw)
  "Return (OK DATA) for the HTTP response in the current buffer.
STATUS is the plist `url-retrieve' passes its callback.  DATA is the
parsed JSON body on success, else an error message.  With RAW, DATA on
success is the body's bytes, as a unibyte string."
  (if (not (and (boundp 'url-http-end-of-headers) url-http-end-of-headers))
      (list nil (if-let* ((err (plist-get status :error)))
                    ;; url.el signals e.g. (error connection-failed "..." :host ...).
                    (mapconcat (lambda (x) (string-trim (format "%s" x)))
                               (take 2 (cdr err)) " ")
                  "No response"))
    (let* ((start (if (eq (char-after url-http-end-of-headers) ?\n)
                      ;; The newline of the blank line ending the headers.
                      (1+ url-http-end-of-headers)
                    url-http-end-of-headers))
           (bytes (buffer-substring-no-properties start (point-max)))
           (bytes (if (multibyte-string-p bytes) (string-to-unibyte bytes) bytes))
           (body (decode-coding-string bytes 'utf-8))
           (json (and (not (and raw (<= 200 url-http-response-status 299)))
                      (ignore-errors
                        (json-parse-string body :object-type 'alist
                                           :array-type 'list
                                           :null-object nil :false-object nil)))))
      (if (<= 200 url-http-response-status 299)
          (list t (if raw bytes json))
        (list nil (format "HTTP %d: %s" url-http-response-status
                          (or (and (consp json) (alist-get 'message json))
                              (string-trim body))))))))

(defun mayhem--api-get (path params callback &optional raw)
  "GET PATH with query PARAMS from the Mayhem API in the background.
Call CALLBACK with (OK DATA): OK is non-nil on success, DATA is the
parsed JSON (objects as alists, arrays as lists) or an error message.
With RAW, DATA on success is the body's bytes, as a unibyte string."
  (condition-case err
      (let* ((config (mayhem--read-config))
             (url-request-extra-headers
              `(("X-Mayhem-Token" . ,(concat "token " (alist-get 'token config)))
                ("Accept" . "application/json"))))
        (url-retrieve (mayhem--api-url (alist-get 'url config) path params)
                      (lambda (status)
                        (let ((result (condition-case err
                                          (mayhem--api-response status raw)
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

(defun mayhem--target-types (targets)
  "Return a table of the type of each of TARGETS, keyed by path.
TARGETS is an alist of each owner to its targets, as from the API.  A
path is \"owner/project/target\"; a type, \"code\" or \"api\"."
  (let ((types (make-hash-table :test #'equal)))
    (dolist (owner targets types)
      (dolist (target (cdr owner))
        (puthash (concat (alist-get 'owner target) "/" (alist-get 'project_slug target)
                         "/" (alist-get 'slug target))
                 (alist-get 'type target) types)))))

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

;;;; Web links

;; A page is named by a list (KIND ARGS...): (dashboard), (workspace
;; OWNER), (project OWNER PROJECT), (target OWNER PROJECT TARGET), (run
;; OWNER PROJECT TARGET NUMBER), (defect OWNER PROJECT TARGET NUMBER
;; RUN), (testcase OWNER PROJECT TARGET RUN SHA256), (testsuite OWNER
;; PROJECT TARGET RUN) or (testcases OWNER PROJECT TARGET RUN); the web
;; app shows those last two with the run's tests.
;; Links to the web app map to pages and back.  Its routes come from
;; its JS bundle; "-" starts a segment that is not a slug.

(defun mayhem--url-number (string)
  "Return STRING as a number if it is all digits, else nil."
  (and string (string-match-p "\\`[0-9]+\\'" string) (string-to-number string)))

(defun mayhem--url-page (url host)
  "Return the page showing URL, a link to the web app on HOST, or nil.
Nil also when URL is on another host, or shows something no page does."
  (let ((parsed (url-generic-parse-url url)))
    (when (and (member (url-type parsed) '("http" "https"))
               (url-host parsed) host
               (string-equal-ignore-case (url-host parsed) host))
      (pcase-let* ((`(,path . ,query) (url-path-and-query parsed))
                   (segs (mapcar #'url-unhex-string (split-string (or path "") "/" t)))
                   (params (and query (url-parse-query-string query)))
                   (defect (mayhem--url-number (cadr (assoc "defect" params)))))
        (pcase segs
          ((guard (member "-" segs))
           (pcase segs
             (`(,o ,p ,tg "-" "defects" ,(app mayhem--url-number (and d (pred identity))))
              (list 'defect o p tg d nil))
             (`(,o ,p ,tg "-" "defects" ,(app mayhem--url-number (and d (pred identity)))
                   "runs" ,(app mayhem--url-number (and r (pred identity))))
              (list 'defect o p tg d r))))
          ('nil '(dashboard))
          (`(,o) (list 'workspace o))
          (`(,o ,p) (list 'project o p))
          (`(,o ,p ,tg) (list 'target o p tg))
          (`(,o ,p ,tg ,(app mayhem--url-number (and n (pred identity))) "tests")
           (when-let* ((sha (cadr (assoc "testcase" params))))
             (list 'testcase o p tg n sha)))
          (`(,o ,p ,tg ,(app mayhem--url-number (and n (pred identity))) . ,(or 'nil '("defects")))
           (if defect (list 'defect o p tg defect n) (list 'run o p tg n))))))))

(defun mayhem--page-url (base page)
  "Return the link to PAGE in the web app at BASE."
  (concat
   (string-trim-right base "/")
   (pcase page
     ('(dashboard) "/")
     (`(defect ,o ,p ,tg ,n ,run)
      (if run
          (format "%s?defect=%s" (mayhem--path "/%s/%s/%s/%s" o p tg (format "%s" run)) n)
        (mayhem--path "/%s/%s/%s/-/defects/%s" o p tg (format "%s" n))))
     (`(,(or 'testsuite 'testcases) ,o ,p ,tg ,run)
      (mayhem--path "/%s/%s/%s/%s/tests" o p tg (format "%s" run)))
     ;; The web app lists them on the target's page.
     (`(,(or 'target-runs 'target-defects) ,o ,p ,tg)
      (mayhem--path "/%s/%s/%s" o p tg))
     (`(testcase ,o ,p ,tg ,run ,sha)
      (format "%s?testcase=%s" (mayhem--path "/%s/%s/%s/%s/tests" o p tg (format "%s" run))
              (url-hexify-string sha)))
     (`(,_ . ,args)
      (apply #'mayhem--path (mapconcat (lambda (_) "/%s") args "")
             (mapcar (lambda (a) (format "%s" a)) args))))))

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
  "Fetch PROJECT of OWNER with its totals and targets, archived ones too.
Call CALLBACK with (OK DATA): DATA is an alist with `project', `totals'
and `targets', each trimmed to what its page shows, each target with
its `latest' run, or an error message."
  (let ((path (mayhem--path "/api/v2/owner/%s/project/%s" owner project))
        (pick (lambda (fields cb)
                (lambda (ok data) (funcall cb ok (if ok (mayhem--pick data fields) data))))))
    (mayhem--fetch-each
     `((project . ,(lambda (cb)
                     (mayhem--api-get path nil
                                      (funcall pick '(default_branch repository_url updated_at
                                                                     n_defects_active_high
                                                                     n_defects_active_medium
                                                                     n_defects_active_low
                                                                     n_defects_fixed_high
                                                                     n_defects_fixed_medium
                                                                     n_defects_fixed_low)
                                               cb))))
       (totals . ,(lambda (cb)
                    (mayhem--api-get (concat path "/project-total") nil
                                     (funcall pick '(runs targets latest_targets_passing_tests)
                                              cb))))
       (targets . ,(lambda (cb)
                     (mayhem--api-get-all
                      (concat path "/target") 'targets
                      (lambda (ok data)
                        (funcall cb ok
                                 (if (not ok)
                                     data
                                   (mapcar (lambda (target)
                                             (cons (cons 'latest
                                                         (when-let* ((run (alist-get 'latest_active_run
                                                                                     target)))
                                                           (mayhem--target-run run)))
                                                   (mayhem--pick target '(slug target_name type
                                                                               is_archived n_runs))))
                                           data))))
                      '((include_archived "true"))))))
     callback)))

(defconst mayhem--runs-shown 5
  "How many of a target's latest runs its page shows.")

(defconst mayhem--target-defects-shown 5
  "How many of a target's defects, most severe first, its page shows.")

(defconst mayhem--target-run-fields
  '(run_number pending started stopped ended failed n_defects branch_name
               created_at started_by n_testcase_reports n_crash_reports
               n_optimized_set_testcases n_exploitability_factors_passing
               n_exploitability_factors_total scm_remote_origin docker_pullable
               fetched_docker_image_digest
               ;; From its `run_attributes'.
               n_lines_covered n_lines_total n_defects_active_high
               n_defects_active_medium n_defects_active_low)
  "Fields of a run kept for its target's page.")

(defun mayhem--target-run (run)
  "Return RUN, as the API gives it, with only `mayhem--target-run-fields'."
  (mayhem--pick (append run (alist-get 'run_attributes run)) mayhem--target-run-fields))

(defconst mayhem--target-defect-fields
  '(defect_number title severity severity_level state cwe_number last_seen
                  last_seen_run_number)
  "Fields of a defect kept for its target's lists.")

(defun mayhem--target-defect (defect)
  "Return DEFECT, as the API gives it, with only `mayhem--target-defect-fields'."
  (mayhem--pick defect mayhem--target-defect-fields))

(defun mayhem--target-defects-params (target)
  "Return the query parameters listing TARGET's defects, most severe first."
  `((target_slug ,target) (sorted_by "-severity")))

(defun mayhem--fetch-target (owner project target callback)
  "Fetch TARGET of PROJECT of OWNER, with its defects and latest run list.
Call CALLBACK with (OK DATA): DATA is an alist with `target', its
`latest' run, and `runs' and `defects', each a list as the API gives it
\(`count' and the items), or an error message.  All are trimmed to what
the page shows; the defects are the most severe ones."
  (let ((path (mayhem--path "/api/v2/owner/%s/project/%s/target/%s"
                            owner project target))
        (trim (lambda (key fn)
                (lambda (cb)
                  (lambda (ok data)
                    (funcall cb ok (if ok `((count . ,(alist-get 'count data))
                                            (,key . ,(mapcar fn (alist-get key data))))
                                     data)))))))
    (mayhem--fetch-each
     `((target . ,(lambda (cb)
                    (mayhem--api-get
                     path nil
                     (lambda (ok data)
                       (funcall cb ok (if ok
                                          (cons (cons 'latest
                                                      (when-let* ((run (alist-get 'latest_active_run
                                                                                  data)))
                                                        (mayhem--target-run run)))
                                                (mayhem--pick data '(type url updated_at)))
                                        data))))))
       (runs . ,(lambda (cb)
                  (mayhem--api-get (concat path "/run")
                                   `((per_page ,mayhem--runs-shown))
                                   (funcall (funcall trim 'runs #'mayhem--target-run) cb))))
       (defects . ,(lambda (cb)
                     (mayhem--api-get
                      (mayhem--path "/api/v2/owner/%s/project/%s/defect" owner project)
                      `(,@(mayhem--target-defects-params target)
                        (per_page ,mayhem--target-defects-shown))
                      (funcall (funcall trim 'defects #'mayhem--target-defect) cb)))))
     (lambda (ok data)
       (funcall callback ok
                (if (not ok)
                    data
                  ;; The latest run rides with the target, as the API gives it.
                  (let ((target (alist-get 'target data)))
                    `((target . ,(cdr target))
                      (latest . ,(alist-get 'latest target))
                      (runs . ,(alist-get 'runs data))
                      (defects . ,(alist-get 'defects data))))))))))

(defun mayhem--fetch-target-runs (owner project target callback)
  "Fetch every run of TARGET of PROJECT of OWNER, newest first.
Call CALLBACK with (OK DATA): DATA is the runs, as `mayhem--target-run'
trims them, or an error message."
  (mayhem--api-get-all
   (mayhem--path "/api/v2/owner/%s/project/%s/target/%s/run" owner project target)
   'runs
   (lambda (ok data)
     (funcall callback ok (if ok (mapcar #'mayhem--target-run data) data)))))

(defun mayhem--fetch-target-defects (owner project target callback)
  "Fetch every defect of TARGET of PROJECT of OWNER, most severe first.
Call CALLBACK with (OK DATA): DATA is the defects, as
`mayhem--target-defect' trims them, or an error message."
  (mayhem--api-get-all
   (mayhem--path "/api/v2/owner/%s/project/%s/defect" owner project)
   'defects
   (lambda (ok data)
     (funcall callback ok (if ok (mapcar #'mayhem--target-defect data) data)))
   (mayhem--target-defects-params target)))

(defconst mayhem--trend-windows
  '((year "12 months" 31536000 604800 "%d %b")
    (quarter "3 months" 7776000 172800 "%d %b")
    (month "30 days" 2592000 86400 "%d %b")
    (week "7 days" 604800 14400 "%a %H:%M")
    (day "24 hours" 86400 3600 "%H:%M"))
  "Windows of a defect trend, as the web app offers them.
Each is (KEY LABEL SPAN STEP TIME-FORMAT): SPAN and STEP in seconds,
TIME-FORMAT for a point's time.")

(defun mayhem--fetch-defect-trend (owner project target window callback)
  "Fetch the defect trend of TARGET of PROJECT of OWNER over WINDOW.
Of the whole PROJECT when TARGET is nil.
WINDOW is a key of `mayhem--trend-windows', ending now.  Call CALLBACK
with (OK DATA): DATA is a list of points, each an alist of `timestamp'
and active defects by severity, `active_high' and the like; or
`members-only' when only members of OWNER may see it; or an error
message."
  (pcase-let* ((`(,_ ,_ ,span ,step ,_) (assq window mayhem--trend-windows))
               (end (truncate (float-time))))
    (mayhem--api-get
     (mayhem--path "/api/v2/owner/%s/defect-trend" owner)
     `((project ,project) ,@(and target `((target ,target)))
       (window_start_timestamp_seconds ,(- end span))
       (window_end_timestamp_seconds ,end)
       (window_step_seconds ,step))
     (lambda (ok data)
       (cond (ok (funcall callback t (mapcar (lambda (p)
                                               (mayhem--pick p '(timestamp active_high
                                                                           active_medium
                                                                           active_low fixed)))
                                             (alist-get 'trend data))))
             ;; Like the owner's project list, it answers only members.
             ((string-prefix-p "HTTP 404" data) (funcall callback t 'members-only))
             (t (funcall callback nil data)))))))

(defconst mayhem--scm-fields
  '(scm_remote_origin branch_name merge_base_branch_name revision
                     scm_commit_subject scm_commit_author scm_commit_author_email
                     ci_type ci_url)
  "Fields of a run naming its source and the CI build that started it.")

(defun mayhem--clean-url (url)
  "Return URL without a default port or doubled slashes in its path.
The API gives links such as https://github.com:443/owner/name//actions."
  (when url
    (replace-regexp-in-string
     "\\([^:/]\\)//+" "\\1/"
     (replace-regexp-in-string "\\`\\(https?://[^/:]+\\):\\(?:443\\|80\\)\\(/\\|\\'\\)"
                               "\\1\\2" url))))

(defun mayhem--repo (url)
  "Return the repository at URL as (HOST . PATH), or nil.
URL is a remote or web link in any form the API gives, such as
git@github.com:owner/name.git or https://github.com:443/owner/name/."
  (when (and url
             (string-match (concat "\\`\\(?:[a-z+]+://\\)?\\(?:[^@/]+@\\)?\\([^/:@]+\\)"
                                   "\\(?::[0-9]*\\)?[:/]\\([^/]+/.+?\\)"
                                   "\\(?:\\.git\\)?/*\\'")
                           url))
    (cons (match-string 1 url) (match-string 2 url))))

(defun mayhem--repo-url (repo &optional kind ref)
  "Return the web link to REPO, (HOST . PATH), or to its KIND REF.
KIND is `branch' or `commit'.  Nil for a KIND on a host whose links
are not known: GitHub's, GitLab's and Bitbucket's are."
  (pcase-let* ((`(,host . ,path) repo)
               (home (concat "https://" host "/" path))
               (forge (cond ((equal host "github.com") '("tree" . "commit"))
                            ((string-match-p "gitlab" host) '("-/tree" . "-/commit"))
                            ((equal host "bitbucket.org") '("src" . "commits")))))
    (pcase kind
      ('nil home)
      ('branch (and forge (concat home "/" (car forge) "/" ref)))
      ('commit (and forge (concat home "/" (cdr forge) "/" ref))))))

(defun mayhem--image-url (image)
  "Return the web page of the Docker IMAGE, such as \"debian:stretch\".
Its tag's page on Docker Hub, GitHub or Quay; nil for other registries,
such as a Mayhem server's own, which have no page."
  (let* ((ref (car (split-string image "@")))
         (slash (string-search "/" ref))
         (first (and slash (substring ref 0 slash)))
         (host (and first (string-match-p "[.:]\\|\\`localhost\\'" first) first))
         (path (if host (substring ref (1+ slash)) ref))
         (tag (and (string-match ":\\([^:/]+\\)\\'" path) (match-string 1 path)))
         (name (string-remove-prefix
                "library/" (if tag (substring path 0 (match-beginning 0)) path))))
    (pcase host
      ((or 'nil "docker.io" "index.docker.io" "registry-1.docker.io")
       (concat "https://hub.docker.com/"
               (if (string-search "/" name)
                   (concat "r/" name)
                 (concat "_/" name))
               (when tag (concat "/tags?name=" (url-hexify-string tag)))))
      ("ghcr.io" (concat "https://ghcr.io/" name))
      ("quay.io" (concat "https://quay.io/repository/" name "?tab=tags")))))

(defun mayhem--ci-label (type url)
  "Return how a page names the CI build of TYPE at URL."
  (if (string-match "/actions/runs/\\([0-9]+\\)" url)
      (concat "GitHub Actions run " (match-string 1 url))
    (string-join (delq nil (list type url)) "  ")))

(defconst mayhem--run-fields
  `(run_id run_number description pending started stopped ended failed
           started_at ended_at duration started_by ,@mayhem--scm-fields
           n_defects tests_run tests_per_second edges_covered
           api_run docker_pullable fetched_docker_image_digest
           n_exploitability_factors_passing n_exploitability_factors_total
           n_testcase_reports n_regression_testcase_reports
           n_regression_defect_reports n_optimized_set_testcases
           elapsed_real_time cputime created_at updated_at build_id
           cli_version parent_revision is_mayhem_bot has_critical_errors
           mayhemfile_flat overrides env_vars run_files phases next_run_number
           tests_run_mfuzz tests_run_libfuzz tests_run_honggfuzz
           tests_run_symexec current_workers desired_workers
           n_desired_cpu n_desired_memory n_crash_reports
           n_behavior_crash_reports n_regression_crash_reports
           n_valgrind_errors n_behavior_valgrind_errors
           n_regression_valgrind_errors n_starting_testcases
           ;; From its `run_attributes'.
           n_lines_covered n_lines_total n_blocks_covered n_blocks_total
           n_functions_covered n_functions_total
           n_defects_active_high n_defects_active_medium n_defects_active_low
           n_defects_fixed_high n_defects_fixed_medium n_defects_fixed_low
           n_optimized_testsuite_size n_total_testsuite_size triage_queue_size
           n_initial_coverage_collection_processed
           n_initial_coverage_collection_total)
  "Fields of a run kept for its page.")

(defconst mayhem--run-phase-fields
  '(phase_name status failed stopped started_at ended_at elapsed_real_time)
  "Fields of each of a run's `phases' kept for its page.")

(defun mayhem--run-summary (run)
  "Return RUN, as the API gives it, with only `mayhem--run-fields'.
Its `run_attributes' are merged in; `api_run' is t for an API run, and
its phases and files are trimmed too."
  (let ((summary (mayhem--pick (append (list (cons 'api_run (and (alist-get 'api_run run) t)))
                                       run (alist-get 'run_attributes run))
                               mayhem--run-fields)))
    (setf (alist-get 'phases summary)
          (mapcar (lambda (phase) (mayhem--pick phase mayhem--run-phase-fields))
                  (alist-get 'phases summary)))
    (setf (alist-get 'run_files summary)
          (mapcar (lambda (file) (mayhem--pick file '(path sha256)))
                  (alist-get 'run_files summary)))
    summary))

(defun mayhem--format-value (value)
  "Return VALUE, parsed from JSON, as one line of text.
A list is joined with commas; an object is written as JSON, but one
with a name is written as it, the rest of it after in JSON, so a
Mayhemfile's tasks read as their names."
  (cond ((stringp value) value)
        ((numberp value) (number-to-string value))
        ((eq value t) "true")
        ((null value) "")
        ((mayhem--object-p value)
         (let ((name (alist-get 'name value))
               (rest (seq-remove (lambda (pair) (eq (car pair) 'name)) value)))
           (if (stringp name)
               (concat name (and rest (concat " " (mayhem--format-value rest))))
             (condition-case nil
                 (json-serialize value :null-object nil)
               (error (format "%S" value))))))
        ((or (listp value) (vectorp value))
         (mapconcat #'mayhem--format-value value ", "))
        (t (format "%S" value))))

(defun mayhem--object-p (value)
  "Return non-nil if VALUE is a JSON object parsed as an alist."
  (and (consp value) (consp (car value)) (symbolp (caar value))))

(defun mayhem--counts (data)
  "Return the `stats' of DATA, a count over time, as (TIMESTAMP . COUNT)."
  (mapcar (lambda (p) (cons (alist-get 'timestamp p) (alist-get 'count p)))
          (alist-get 'stats data)))

(defun mayhem--testcase-summary (report)
  "Return test case REPORT, as the API lists it, trimmed for a run's page.
Its defects are counted by severity, as `high', `medium' and `low'."
  (let ((levels (mapcar (lambda (d) (alist-get 'severity_level d))
                        (alist-get 'defects report))))
    (append (mayhem--pick report '(sha256 is_regression n_defects execution_time
                                          created_at))
            (mapcar (lambda (level)
                      (cons (intern level) (seq-count (lambda (l) (equal l level)) levels)))
                    '("high" "medium" "low")))))

(defun mayhem--fetch-run (owner project target number callback)
  "Fetch run NUMBER of TARGET of PROJECT of OWNER, with its defects and events.
An API run's endpoints come too; a code run's progress.  Call CALLBACK
with (OK DATA): DATA is an alist with `run', `defects', `events',
`endpoints' and `progress' (nil when the run has none), each trimmed
to the fields its page shows, or an error message."
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
                        (funcall cb t (mayhem--run-summary run))))
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
                                                    data)))))))
              (events . ,(lambda (cb)
                           (mayhem--api-get-all
                            (concat path "/event") 'events
                            (lambda (ok data)
                              (funcall cb ok (if ok (mapcar (lambda (e)
                                                              (mayhem--pick
                                                               e '(created_at event_level
                                                                   event_phase event_desc)))
                                                            data)
                                               data))))))
              ;; How many test cases were processed and defects found by
              ;; when, to chart; each a list of (TIMESTAMP . COUNT).
              (progress . ,(lambda (cb)
                             (if api
                                 (funcall cb t nil)
                               (mayhem--fetch-each
                                (mapcar (pcase-lambda (`(,key . ,endpoint))
                                          (cons key (lambda (cb)
                                                      (mayhem--api-get
                                                       (concat path endpoint) nil
                                                       (lambda (ok data)
                                                         (funcall cb ok (if ok (mayhem--counts data)
                                                                          data)))))))
                                        '((testcases . "/testcase_over_time")
                                          (defects . "/defect_over_time")))
                                cb)))))
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

(defconst mayhem--frames-max 100
  "Most frames of a parsed backtrace kept for a page.")

(defun mayhem--backtrace-frames (parsed)
  "Return PARSED, a test case's `parsed_backtrace', as frames, innermost first.
Each frame is a list of calls (FUNCTION . SOURCE), innermost first: more
than one when calls were inlined into it.  SOURCE is nil when unknown."
  (let ((known (lambda (src) (and src (not (string-prefix-p "??" src)) src))))
    (mapcar (lambda (frame)
              ;; addr2line packs inlined calls into one name:
              ;; "f at a.c:1 (inlined by) g at b.c:2 (inlined by) h".
              (let* ((calls (split-string (or (alist-get 'fn frame) "?") " (inlined by) "))
                     (inner (mapcar (lambda (call)
                                      (if (string-match "\\`\\(.*\\) at \\([^ ]+\\)\\'" call)
                                          (cons (match-string 1 call)
                                                (funcall known (match-string 2 call)))
                                        (cons call nil)))
                                    (butlast calls))))
                (append inner (list (cons (car (last calls))
                                          (funcall known (alist-get 'src frame)))))))
            (take mayhem--frames-max parsed))))

(defun mayhem--code-evidence (reports)
  "Return the evidence of a code defect from its test case REPORTS.
That is how many there are, each listed one's run and timing, and the
first's crash and backtrace, parsed into `frames' when the API did."
  (let* ((all (alist-get 'testcase_reports reports))
         (first (car all)))
    (append (list (cons 'count (alist-get 'count reports)))
            (mayhem--pick first '(sha256 run_number crash_type signal_number repro_cmdline))
            (list (cons 'frames (mayhem--backtrace-frames (alist-get 'parsed_backtrace first)))
                  (cons 'backtrace
                        (when-let* ((bt (alist-get 'backtrace first)))
                          (truncate-string-to-width bt mayhem--evidence-max nil nil "…")))
                  (cons 'testcases
                        (mapcar (lambda (r)
                                  (mayhem--pick r '(sha256 run_number execution_time)))
                                all))))))

(defun mayhem--fetch-defect (owner project target number run callback)
  "Fetch defect NUMBER of TARGET of PROJECT of OWNER, with its evidence.
Call CALLBACK with (OK DATA): DATA is an alist with `defect', `run',
`evidence' and `scm', each trimmed to what its page shows, or an error
message.  `run' is RUN, a run number, or else the last run that saw
it, and `scm' that run's commit and CI build.  An API defect's evidence
is that run's HTTP exchange; a code defect's, its first page of test
cases and the first one's crash."
  (let ((path (mayhem--path "/api/v2/owner/%s/project/%s/target/%s"
                            owner project target)))
    (mayhem--api-get
     (concat path (format "/defect/%s" number)) nil
     (lambda (ok defect)
       (if (not ok)
           (funcall callback nil defect)
         ;; A defect gives its last run's id, but evidence needs a number.
         (let* ((run (or run (alist-get 'last_seen_run_number defect)))
                (evidence
                 (lambda (cb)
                   (cond
                    ((and (equal (alist-get 'source defect) "api") run)
                     (mayhem--api-get (concat path (format "/run/%s/api/rest/issue/%s" run number))
                                      nil
                                      (lambda (ok issue)
                                        (funcall cb ok (if ok (mayhem--api-evidence issue) issue)))))
                    ((equal (alist-get 'source defect) "code")
                     (mayhem--api-get (concat path (format "/defect/%s/testcase_report" number))
                                      `((per_page ,mayhem--page-size))
                                      (lambda (ok reports)
                                        (funcall cb ok (if ok (mayhem--code-evidence reports)
                                                         reports)))))
                    (t (funcall cb t nil)))))
                ;; The run's commit is a nicety: the page shows without it.
                (scm (lambda (cb)
                       (if (not run)
                           (funcall cb t nil)
                         (mayhem--api-get (concat path (format "/run/%s" run)) nil
                                          (lambda (ok data)
                                            (funcall cb t (and ok (mayhem--pick
                                                                   data
                                                                   mayhem--scm-fields)))))))))
           (mayhem--fetch-each
            `((evidence . ,evidence) (scm . ,scm))
            (lambda (ok data)
              (funcall callback ok
                       (if ok `((defect . ,(mayhem--pick defect mayhem--defect-fields))
                                (run . ,run)
                                ,@data)
                         data))))))))))

(defconst mayhem--testcase-fields
  '(sha256 is_regression crashed crash_type signal_number faulting_address
           n_valgrind_errors execution_time created_at repro_cmdline
           hexdump output testcase_source)
  "Fields of a test case kept for its page.")

(defun mayhem--fetch-testcase (owner project target run sha256 callback)
  "Fetch the test case SHA256 of RUN of TARGET of PROJECT of OWNER.
Call CALLBACK with (OK DATA): DATA is an alist with `testcase', its
defects, frames and backtrace, trimmed to what its page shows, and the
`run''s start, or an error message."
  (let ((path (mayhem--path "/api/v2/owner/%s/project/%s/target/%s/run/%s"
                            owner project target (format "%s" run))))
    (mayhem--fetch-each
     `((testcase . ,(lambda (cb)
                      (mayhem--api-get
                       (concat path (mayhem--path "/testcase_report/%s" sha256)) nil
                       (lambda (ok report)
                         (funcall
                          cb ok
                          (if (not ok)
                              report
                            (append
                             (mayhem--pick report mayhem--testcase-fields)
                             (list
                              (cons 'defects
                                    (mapcar (lambda (d)
                                              (mayhem--pick d '(defect_number severity_level
                                                                              title)))
                                            (alist-get 'defects report)))
                              (cons 'frames (mayhem--backtrace-frames
                                             (alist-get 'parsed_backtrace report)))
                              (cons 'backtrace
                                    (when-let* ((bt (alist-get 'backtrace report)))
                                      (truncate-string-to-width bt mayhem--evidence-max
                                                                nil nil "…")))))))))))
       (run . ,(lambda (cb)
                 (mayhem--api-get path nil
                                  (lambda (ok run)
                                    (funcall cb ok (if ok (mayhem--pick run '(started_at))
                                                     run)))))))
     callback)))

(defun mayhem--split-command (cmd &optional width)
  "Return shell command CMD with each of its commands on its own line.
Lines end in a backslash, so the text still pastes into a shell whole.
With WIDTH, a command wider than that goes on between its words, two
columns further in.  Quoting is ignored in finding separators, as
Mayhem's command lines don't quote them, but no line breaks a quote."
  ;; The character before the separator keeps 2>&1 whole.
  (let ((split (replace-regexp-in-string "\\([^<>&|;]\\(?:;\\|&&?\\|||?\\)\\)[ \t]+"
                                         "\\1 \\\\\n  " cmd)))
    (if (not width)
        split
      (mapconcat (lambda (line)
                   (let* ((indent (progn (string-match "\\` *" line) (match-string 0 line)))
                          (more (concat indent "  "))
                          (lines nil) (current nil))
                     (dolist (word (mayhem--shell-words line))
                       (if (and current
                                (> (+ (string-width current) 1 (string-width word) 2) width))
                           (setq lines (cons current lines) current (concat more word))
                         (setq current (if current (concat current " " word)
                                         (concat indent word)))))
                     (string-join (nreverse (cons current lines)) " \\\n")))
                 (split-string split " \\\\\n") " \\\n"))))

(defun mayhem--shell-words (line)
  "Return the words of shell command LINE, split at blanks outside quotes.
A backslash keeps the character after it in its word."
  (let ((words nil) (start nil) (quoting nil) (i 0) (n (length line)))
    (while (< i n)
      (let ((c (aref line i)))
        (cond (quoting (cond ((eq c quoting) (setq quoting nil))
                           ((and (eq c ?\\) (eq quoting ?\")) (setq i (1+ i)))))
              ((memq c '(?\s ?\t))
               (when start (push (substring line start i) words) (setq start nil)))
              (t (unless start (setq start i))
                 (cond ((memq c '(?\" ?')) (setq quoting c))
                       ((eq c ?\\) (setq i (1+ i)))))))
      (setq i (1+ i)))
    (when start (push (substring line start (min i n)) words))
    (nreverse words)))

(defun mayhem--format-elapsed (seconds)
  "Return SECONDS as a clock, \"5:07\" or \"1:02:03\"."
  (let* ((s (max 0 (truncate seconds))) (h (/ s 3600)) (m (/ (% s 3600) 60)))
    (if (> h 0)
        (format "%d:%02d:%02d" h m (% s 60))
      (format "%d:%02d" m (% s 60)))))

(defun mayhem--elapsed (timestamp start)
  "Return the seconds from START to TIMESTAMP, both ISO 8601 strings."
  (float-time (time-subtract (encode-time (iso8601-parse timestamp))
                             (encode-time (iso8601-parse start)))))

(defun mayhem--step-series (points span width)
  "Return the values of POINTS over SPAN seconds, sampled WIDTH times.
POINTS are (SECONDS . VALUE), by time.  Each sample is the value of the
last point by its end, 0 before the first, as in the web app's chart."
  (let ((span (max 1 span)))
    (mapcar (lambda (i)
              (let ((at (* span (/ (1+ i) (float width)))) (v 0))
                (dolist (p points v)
                  (when (<= (car p) at) (setq v (cdr p))))))
            (number-sequence 0 (1- width)))))

(defconst mayhem--bar-chars " ▁▂▃▄▅▆▇█"
  "A bar's top, by how many eighths of a row it fills.")

(defun mayhem--bar-rows (values height)
  "Return VALUES as a bar chart HEIGHT rows tall, a string per row, top first.
Bars scale to the largest value; any value above 0 shows."
  (let* ((top (max 1 (apply #'max 0 values)))
         (eighths (mapcar (lambda (v)
                            (if (> v 0) (max 1 (round (* 8 height v) top)) 0))
                          values)))
    (mapcar (lambda (row)
              (apply #'string
                     (mapcar (lambda (e)
                               (aref mayhem--bar-chars (min 8 (max 0 (- e (* 8 row))))))
                             eighths)))
            (number-sequence (1- height) 0 -1))))

(defun mayhem--stack-rows (stacks height)
  "Return STACKS as a stacked bar chart HEIGHT rows tall, top row first.
Each stack is a list of values, its bottom layer first.  Each row is a
list of (CHAR . LAYER) per column: LAYER is the index of the layer the
cell shows, nil for an empty one.  Bars scale to the tallest stack."
  (let* ((top (max 1 (apply #'max 0 (mapcar (lambda (s) (apply #'+ s)) stacks))))
         (scale (lambda (v) (if (> v 0) (max 1 (round (* 8 height v) top)) 0))))
    (mapcar
     (lambda (row)
       (mapcar
        (lambda (stack)
          (let* ((filled (funcall scale (apply #'+ stack)))
                 (eighths (min 8 (max 0 (- filled (* 8 row)))))
                 (layer nil) (sum 0))
            ;; The layer at the cell's lowest eighth colours it.
            (when (> eighths 0)
              (seq-do-indexed (lambda (v i)
                                (setq sum (+ sum v))
                                (when (and (null layer)
                                           (> (funcall scale sum) (* 8 row)))
                                  (setq layer i)))
                              stack))
            (cons (aref mayhem--bar-chars eighths) layer)))
        stacks))
     (number-sequence (1- height) 0 -1))))

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
TIMESTAMP is an ISO 8601 string, as the API gives; nil gives nil.  The
exact local time is the `help-echo' (mouse hover) and `mayhem-ts'
\(ElDoc at point, see `mayhem--ts-eldoc-setup') of the text."
  (when timestamp
    (let* ((time (encode-time (iso8601-parse timestamp)))
           (exact (format-time-string "%a %Y-%m-%d %H:%M:%S %Z" time)))
      (propertize (mayhem--age-text (float-time (time-subtract now time)))
                  'help-echo exact 'mayhem-ts exact))))

(defun mayhem--age-text (secs)
  "Return SECS seconds as an age, such as \"3 days ago\"."
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
        (format "%d %s%s ago" n unit (if (= n 1) "" "s"))))))

(defun mayhem--ts-eldoc (&rest _)
  "Return the exact time of the timestamp at point, or nil.
An `eldoc-documentation-functions' member."
  (get-text-property (point) 'mayhem-ts))

(defun mayhem--ts-eldoc-setup ()
  "Show the exact time of the timestamp at point in the echo area.
Call from a major-mode body.  ElDoc shows it after `eldoc-idle-delay'
when `global-eldoc-mode' is on (the default)."
  (add-hook 'eldoc-documentation-functions #'mayhem--ts-eldoc nil t)
  ;; vui motions, so ElDoc reacts to them like to `next-line'.
  (eldoc-add-command-completions "vui-forward" "vui-backward"))

;;;; Test suites

;; A target's test suite is the optimized set of its test cases at the
;; end of a run.  The API gives it only as a tarball of the files, each
;; named by the sha256 of its bytes, as the CLI's `mayhem download'
;; fetches it.

(defconst mayhem--preview-length 24
  "Bytes of a test case shown as its preview.")

(defun mayhem--gunzip (bytes)
  "Return BYTES, a unibyte string, decompressed if it is gzipped."
  (if (not (and (> (length bytes) 1) (= (aref bytes 0) #x1f) (= (aref bytes 1) #x8b)))
      bytes
    (unless (and (fboundp 'zlib-available-p) (zlib-available-p))
      (error "Mayhem: Needs an Emacs built with zlib to unpack the test suite"))
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert bytes)
      (unless (zlib-decompress-region (point-min) (point-max))
        (error "Mayhem: The test suite is not valid gzip"))
      (buffer-string))))

(defun mayhem--tar-files (bytes)
  "Return the regular files in BYTES, a tar archive, as (NAME . CONTENTS).
NAME is the file's path in the archive, CONTENTS a unibyte string, in
the archive's order."
  (let ((pos 0) (len (length bytes)) files)
    ;; A zero block ends the archive.
    (while (and (<= (+ pos 512) len) (/= (aref bytes pos) 0))
      (let* ((field (lambda (start size)
                      ;; Some archivers pad with spaces, not NULs.
                      (string-trim-right
                       (car (split-string (substring bytes (+ pos start) (+ pos start size))
                                          "\0")))))
             (name (funcall field 0 100))
             (prefix (if (string-prefix-p "ustar" (funcall field 257 6))
                         (funcall field 345 155)
                       ""))
             (size (string-to-number (string-trim (funcall field 124 12)) 8))
             (start (+ pos 512)))
        (when (and (memq (aref bytes (+ pos 156)) '(?0 0)) (<= (+ start size) len))
          (push (cons (if (string-empty-p prefix) name (concat prefix "/" name))
                      (substring bytes start (+ start size)))
                files))
        (setq pos (+ start (* 512 (/ (+ size 511) 512))))))
    (nreverse files)))

(defun mayhem--testsuite-files (bytes)
  "Return the test cases in BYTES, a test suite tarball, as (SHA256 . CONTENTS).
Only the files named by the sha256 of their contents: others are not
test cases, or were damaged on the way.  Signal an error when there
are files but none is, as a suite that seems empty is kept for good."
  (let* ((all (mayhem--tar-files (mayhem--gunzip bytes)))
         (files (delq nil (mapcar (pcase-lambda (`(,name . ,contents))
                                    (let ((sha (file-name-nondirectory name)))
                                      (and (equal sha (secure-hash 'sha256 contents))
                                           (cons sha contents))))
                                  all))))
    (when (and all (null files))
      (error "Mayhem: None of the %d files of the test suite is a test case" (length all)))
    files))

(defun mayhem--bytes-preview (bytes)
  "Return the first bytes of BYTES as text: printable ASCII as is, others as `.'."
  (apply #'string (mapcar (lambda (b) (if (<= 32 b 126) b ?.))
                          (substring bytes 0 (min (length bytes) mayhem--preview-length)))))

;; A test case's `hexdump' is xxd's: per line an offset, up to 16 bytes
;; in hex, then those bytes as text; a short last line may be unpadded.
(defun mayhem--hexdump-bytes (hexdump)
  "Return the bytes in HEXDUMP, as a unibyte string."
  (apply #'unibyte-string
         (mapcan
          (lambda (line)
            (when (string-match "\\`[[:xdigit:]]+: ?" line)
              (let ((rest (substring line (match-end 0))))
                ;; The text column is as long as the line has bytes.
                (catch 'bytes
                  (dolist (n (number-sequence (min 16 (length rest)) 1 -1))
                    (let ((hex (string-replace " " "" (substring rest 0 (- (length rest) n)))))
                      (when (and (= (length hex) (* 2 n))
                                 (string-match-p "\\`[[:xdigit:]]*\\'" hex))
                        (throw 'bytes
                               (mapcar (lambda (i) (string-to-number (substring hex i (+ i 2)) 16))
                                       (number-sequence 0 (- (length hex) 2) 2))))))))))
          (split-string (or hexdump "") "\n" t))))

(defun mayhem--bytes-text (bytes)
  "Return BYTES as text: printable ASCII, tabs and newlines as is, others as \\xNN."
  (mapconcat (lambda (b)
               (if (or (<= 32 b 126) (memq b '(?\t ?\n)))
                   (string b)
                 (propertize (format "\\x%02x" b) 'face 'shadow)))
             bytes ""))

(defun mayhem--fetch-testsuite (owner project target run callback)
  "Fetch the test suite of run RUN of TARGET of PROJECT of OWNER.
That is the optimized set of test cases at the end of the run.  Call
CALLBACK with (OK DATA): DATA is an alist with `live', non-nil while the
run is going, and `files', each test case as (SHA256 . CONTENTS); or an
error message."
  (let ((path (mayhem--path "/api/v2/owner/%s/project/%s/target/%s" owner project target)))
    (mayhem--fetch-each
     `((live . ,(lambda (cb)
                  (mayhem--api-get
                   (concat path (mayhem--path "/run/%s" (format "%s" run))) nil
                   (lambda (ok data)
                     (funcall cb ok (if ok
                                        (not (or (alist-get 'ended data) (alist-get 'failed data)
                                                 (alist-get 'stopped data)))
                                      data))))))
       (files . ,(lambda (cb)
                   (mayhem--api-get
                    (concat path "/testsuite.tar") `((run_number ,run) (optimized_only "true"))
                    (lambda (ok data)
                      (if (not ok)
                          (funcall cb nil data)
                        (condition-case err
                            (funcall cb t (mayhem--testsuite-files data))
                          (error (funcall cb nil (error-message-string err))))))
                    t))))
     callback)))

(defun mayhem--fetch-run-testcases (owner project target run callback)
  "Fetch how RUN of TARGET of PROJECT of OWNER saw each of its test cases.
Call CALLBACK with (OK DATA): DATA is a list of each one's
`mayhem--testcase-summary' with its `source' (such as \"libfuzzer\"),
or an error message.  The API can filter only for crashes, which miss
defects such as a memory error the target survives, so all come."
  (mayhem--api-get-all
   (mayhem--path "/api/v2/owner/%s/project/%s/target/%s/run/%s/testcase-result"
                 owner project target (format "%s" run))
   'testcase_reports
   (lambda (ok data)
     (funcall callback ok
              (if ok
                  (mapcar (lambda (tc)
                            (cons (cons 'source (alist-get 'testcase_source tc))
                                  (mayhem--testcase-summary tc)))
                          data)
                data)))))

(provide 'mayhem-core)
;;; mayhem-core.el ends here
