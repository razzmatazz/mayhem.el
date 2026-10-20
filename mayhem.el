;;; mayhem.el --- Emacs client for Mayhem  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (vui "0.1"))
;; Keywords: tools
;; URL: https://github.com/razzmatazz/mayhem.el

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; An Emacs client for Mayhem (https://app.mayhem.security), driven by
;; its REST API and rendered with vui.el.  `M-x mayhem' opens a
;; dashboard of your projects and their targets.  Data is cached in a
;; local SQLite store (see mayhem-sync.el), so pages paint at once.

;;; Code:

(require 'browse-url)
(require 'cl-lib)
(require 'vui)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)
(require 'mayhem-workspace)
(require 'mayhem-project)
(require 'mayhem-target)
(require 'mayhem-defect)
(require 'mayhem-run)
(require 'mayhem-testcase)
(require 'mayhem-search)

(mayhem-sync-define-resource me ()
  :fetch #'mayhem--fetch-me)

(define-derived-mode mayhem-dashboard-mode mayhem-page-mode "Mayhem"
  "Major mode for the Mayhem dashboard.")

(defun mayhem-dashboard--workspaces (workspaces)
  "Return the vnodes listing WORKSPACES, as from `mayhem--workspaces'."
  (let ((width (apply #'max 1 (mapcar (lambda (w) (string-width (car w))) workspaces))))
    (apply #'vui-fragment
           (mapcar (pcase-lambda (`(,owner . ,count))
                     (mayhem-row (list (mayhem-fit (propertize owner 'face 'mayhem-project) width t)
                                       (propertize (format " %3d project%s" count
                                                           (if (= count 1) "" "s"))
                                                   'face 'mayhem-label))
                                 (lambda () (mayhem-workspace-open owner))
                                 "RET: open workspace"))
                   workspaces))))

(vui-defcomponent mayhem-dashboard ()
  "The dashboard: the workspaces of every project visible to the user.
Its heading is the Mayhem server's host."
  :render
  (let* ((snapshot (mayhem-sync-use-resource '(projects)))
         (workspaces (mayhem--workspaces (plist-get snapshot :data))))
    (vui-fragment
     (mayhem-page-heading nil nil nil)
     (mayhem-snapshot-view (mayhem-sync-use-resource '(me)) "user"
                           (mayhem-skeleton '(("User        " 30)))
                           (lambda (me) (mayhem-field "User" (mayhem--user-label me))))
     (vui-newline)
     (mayhem-heading (if (plist-get snapshot :fetched-at)
                         (format "Workspaces (%d)" (length workspaces))
                       "Workspaces"))
     (mayhem-snapshot-view snapshot "workspaces"
                           (mayhem-skeleton '((14 "  " 11) (22 "  " 11)
                                              (10 "  " 11) (18 "  " 11)
                                              (12 "  " 11) (16 "  " 11)))
                           (lambda (_)
                             (if workspaces
                                 (mayhem-dashboard--workspaces workspaces)
                               (mayhem-notice "No workspaces")))))))

;;;###autoload
(defun mayhem ()
  "Open the Mayhem dashboard."
  (interactive)
  (mayhem-open-page "*mayhem*" #'mayhem-dashboard-mode
                    (lambda () (vui-component 'mayhem-dashboard))
                    '(dashboard)))

;;;###autoload
(defun mayhem-jump ()
  "Open the page of a workspace, project or target, read with completion.
Candidates are \"owner\", \"owner/project\" and \"owner/project/target\"."
  (interactive)
  (mayhem-search-open (mayhem-search-read "Mayhem: Jump to: ")))

;;;; Web links

;; Links to the Mayhem web app open in mayhem.el's pages, through
;; `browse-url-handlers', wherever Emacs follows a link.  Links no page
;; shows still go to the browser, as does `mayhem-browse' (C-c C-o).

(defun mayhem-open (page)
  "Open PAGE, as (KIND ARGS...); see `mayhem--url-page'."
  (pcase page
    ('(dashboard) (mayhem))
    (`(workspace . ,args) (apply #'mayhem-workspace-open args))
    (`(project . ,args) (apply #'mayhem-project-open args))
    (`(target . ,args) (apply #'mayhem-target-open args))
    (`(run . ,args) (apply #'mayhem-run-open args))
    (`(defect . ,args) (apply #'mayhem-defect-open args))
    (`(testcase . ,args) (apply #'mayhem-testcase-open args))))

(defun mayhem--url-handled-p (url)
  "Return non-nil if URL is a link to a page of the configured web app."
  (when-let* ((host (mayhem--host)))
    (mayhem--url-page url host)))

;;;###autoload
(defun mayhem-browse-url (url &rest _)
  "Open the page showing URL, a link to the Mayhem web app.
`mayhem-open-urls' adds it to `browse-url-handlers'."
  (interactive (list (read-string "Mayhem URL: ")))
  (if-let* ((page (and (mayhem--host) (mayhem--url-page url (mayhem--host)))))
      (mayhem-open page)
    (user-error "Mayhem: No page for %s" url)))

;; So `browse-url-with-browser-kind' skips it when asked for a browser.
(function-put 'mayhem-browse-url 'browse-url-browser-kind 'internal)

(defcustom mayhem-open-urls t
  "Non-nil means `browse-url' opens links to the Mayhem web app here.
That is, in mayhem.el's page for it, wherever Emacs follows the link.
Links no page shows still go to the browser."
  :type 'boolean
  :group 'mayhem
  :set (lambda (symbol value)
         (set-default symbol value)
         (setq browse-url-handlers
               (cl-remove #'mayhem-browse-url browse-url-handlers :key #'cdr))
         (when value
           (push (cons #'mayhem--url-handled-p #'mayhem-browse-url) browse-url-handlers))))

(provide 'mayhem)
;;; mayhem.el ends here
