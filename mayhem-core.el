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

(require 'subr-x)
(require 'url)
(require 'url-http)

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

(defun mayhem--api-get-all (path key callback &optional offset items)
  "GET every page of the list under KEY at PATH.
Call CALLBACK with (OK DATA): DATA is all the items, or an error
message.  OFFSET and ITEMS carry the pages fetched so far."
  (let ((offset (or offset 0)))
    (mayhem--api-get
     path `((per_page ,mayhem--page-size) (offset ,offset))
     (lambda (ok data)
       (if (not ok)
           (funcall callback nil data)
         (let ((page (alist-get key data)))
           ;; Not every list reports a total count, so stop on a short page.
           (if (< (length page) mayhem--page-size)
               (funcall callback t (append items page))
             (mayhem--api-get-all path key callback
                                  (+ offset mayhem--page-size)
                                  (append items page)))))))))

(defun mayhem--group-targets (projects targets)
  "Return PROJECTS with their TARGETS, as from the API.
Each element is (LABEL . TARGET-SLUGS), LABEL being `owner/project';
both keep the API's order.  Targets of other projects are dropped."
  (mapcar (lambda (project)
            (let ((owner (alist-get 'owner project))
                  (slug (alist-get 'slug project)))
              (cons (concat owner "/" slug)
                    (delq nil
                          (mapcar (lambda (target)
                                    (and (equal (alist-get 'owner target) owner)
                                         (equal (alist-get 'project_slug target) slug)
                                         (alist-get 'slug target)))
                                  targets)))))
          projects))

(defconst mayhem--max-requests 4
  "Most requests one fetch runs at once.")

(defun mayhem--fetch-owner-targets (owners callback)
  "Fetch the targets of each of OWNERS, up to `mayhem--max-requests' at once.
Call CALLBACK with (OK DATA): DATA is all of them, in OWNERS' order, or
the first error message."
  (let ((queue owners) (running 0) (failed nil)
        (results (make-hash-table :test #'equal)))
    (letrec ((next
              (lambda ()
                (if (and (null queue) (zerop running))
                    (funcall callback t (mapcan (lambda (owner)
                                                  (copy-sequence (gethash owner results)))
                                                owners))
                  (while (and queue (< running mayhem--max-requests))
                    (let ((owner (pop queue)))
                      (setq running (1+ running))
                      (mayhem--api-get-all
                       (format "/api/v2/owner/%s/target" (url-hexify-string owner))
                       'targets
                       (lambda (ok data)
                         (setq running (1- running))
                         (cond (failed)
                               ((not ok) (setq failed t) (funcall callback nil data))
                               (t (puthash owner data results)
                                  (funcall next)))))))))))
      (funcall next))))

(defun mayhem--fetch-projects (callback)
  "Fetch every project visible to the user, with its targets.
Call CALLBACK with (OK DATA): DATA is as from `mayhem--group-targets',
or an error message."
  (mayhem--api-get
   "/api/v2/user/me" nil
   (lambda (ok me)
     (if (not ok)
         (funcall callback nil me)
       (mayhem--api-get-all
        (format "/api/v2/user/%s/project"
                (url-hexify-string (alist-get 'slug me)))
        'projects
        (lambda (ok projects)
          (if (not ok)
              (funcall callback nil projects)
            ;; One request per owner rather than per project: far fewer.
            (mayhem--fetch-owner-targets
             (delete-dups (mapcar (lambda (p) (alist-get 'owner p)) projects))
             (lambda (ok targets)
               (if ok
                   (funcall callback t (mayhem--group-targets projects targets))
                 (funcall callback nil targets)))))))))))

(provide 'mayhem-core)
;;; mayhem-core.el ends here
