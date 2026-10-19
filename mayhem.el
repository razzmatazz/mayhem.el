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

(require 'vui)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)
(require 'mayhem-workspace)
(require 'mayhem-project)
(require 'mayhem-target)
(require 'mayhem-defect)
(require 'mayhem-run)
(require 'mayhem-search)

(mayhem-sync-define-resource me ()
  :fetch #'mayhem--fetch-me)

(define-derived-mode mayhem-dashboard-mode mayhem-page-mode "Mayhem"
  "Major mode for the Mayhem dashboard.")

(defun mayhem-dashboard--workspaces (workspaces)
  "Return the vnodes listing WORKSPACES, as from `mayhem--workspaces'."
  (apply #'vui-fragment
         (mapcar (pcase-lambda (`(,owner . ,count))
                   (mayhem-row (concat "  "
                                       (propertize (format "%-30s" owner) 'face 'mayhem-project)
                                       (propertize (format " %3d project%s" count
                                                           (if (= count 1) "" "s"))
                                                   'face 'mayhem-label)
                                       "\n")
                               (lambda () (mayhem-workspace-open owner))
                               "RET: open workspace"))
                 workspaces)))

(vui-defcomponent mayhem-dashboard (host)
  "The dashboard: the workspaces of every project visible to the user.
HOST is the Mayhem server's, shown with the user logged in."
  :render
  (let* ((snapshot (mayhem-sync-use-resource '(projects)))
         (workspaces (mayhem--workspaces (plist-get snapshot :data))))
    (vui-fragment
     (mayhem-heading "Mayhem")
     (mayhem-snapshot-view (mayhem-sync-use-resource '(me)) "user"
                           (mayhem-skeleton '(("User        " 30)))
                           (lambda (me) (mayhem-field "User" (mayhem--user-label me))))
     (mayhem-field "Host" host)
     (vui-newline)
     (mayhem-heading (if (plist-get snapshot :fetched-at)
                         (format "Workspaces (%d)" (length workspaces))
                       "Workspaces"))
     (mayhem-snapshot-view snapshot "workspaces"
                           (mayhem-skeleton '(("  " 14 "  " 11) ("  " 22 "  " 11)
                                              ("  " 10 "  " 11) ("  " 18 "  " 11)
                                              ("  " 12 "  " 11) ("  " 16 "  " 11)))
                           (lambda (_)
                             (if workspaces
                                 (mayhem-dashboard--workspaces workspaces)
                               (mayhem-notice "No workspaces")))))))

;;;###autoload
(defun mayhem ()
  "Open the Mayhem dashboard."
  (interactive)
  (mayhem-open-page "*mayhem*" #'mayhem-dashboard-mode
                    (lambda () (vui-component 'mayhem-dashboard :host (mayhem--host)))))

;;;###autoload
(defun mayhem-jump ()
  "Open the page of a workspace, project or target, read with completion.
Candidates are \"owner\", \"owner/project\" and \"owner/project/target\"."
  (interactive)
  (mayhem-search-open (mayhem-search-read "Mayhem: Jump to: ")))

(provide 'mayhem)
;;; mayhem.el ends here
