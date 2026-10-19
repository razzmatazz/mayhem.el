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
(require 'mayhem-project)
(require 'mayhem-target)

(define-derived-mode mayhem-dashboard-mode mayhem-page-mode "Mayhem"
  "Major mode for the Mayhem dashboard.")

(defun mayhem-dashboard--projects (projects)
  "Return the vnodes listing PROJECTS, as from `mayhem--group-targets'."
  (apply #'vui-fragment
         (mapcan
          (lambda (project)
            (pcase-let ((`(,owner ,slug) (split-string (car project) "/")))
              (cons (mayhem-row (concat "  " (propertize (car project) 'face 'mayhem-project)
                                        "\n")
                                (lambda () (mayhem-project-open owner slug))
                                "RET: open project")
                    (mapcar (lambda (target)
                              (mayhem-row (concat "    "
                                                  (propertize target 'face 'mayhem-target)
                                                  "\n")
                                          (lambda () (mayhem-target-open owner slug target))
                                          "RET: open target"))
                            (cdr project)))))
          projects)))

(mayhem-sync-define-resource projects ()
  :fetch #'mayhem--fetch-projects)

(vui-defcomponent mayhem-dashboard ()
  "The dashboard: every project visible to the user, with its targets."
  :render
  (let* ((snapshot (mayhem-sync-use-resource '(projects)))
         (fetched (plist-get snapshot :fetched-at))
         (projects (plist-get snapshot :data)))
    (vui-fragment
     (mayhem-heading "Mayhem")
     (vui-newline)
     (mayhem-heading (if fetched
                         (format "Projects (%d)" (length projects))
                       "Projects"))
     (mayhem-snapshot-view snapshot "projects"
                           (mayhem-skeleton '(("  " 26) ("    " 14) ("    " 20)
                                              ("  " 22) ("    " 10)
                                              ("  " 30) ("    " 16) ("    " 12) ("    " 18)
                                              ("  " 18) ("    " 14)))
                           (lambda (projects)
                             (if projects
                                 (mayhem-dashboard--projects projects)
                               (mayhem-notice "No projects")))))))

;;;###autoload
(defun mayhem ()
  "Open the Mayhem dashboard."
  (interactive)
  (mayhem-open-page "*mayhem*" #'mayhem-dashboard-mode
                    (lambda () (vui-component 'mayhem-dashboard))))

(provide 'mayhem)
;;; mayhem.el ends here
