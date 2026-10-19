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

(defface mayhem-section-heading
  '((t :inherit bold))
  "Face for section headings."
  :group 'mayhem)

(defface mayhem-project
  '((t :inherit font-lock-type-face))
  "Face for project names."
  :group 'mayhem)

(defface mayhem-target
  '((t :inherit font-lock-function-name-face))
  "Face for target names."
  :group 'mayhem)

(defvar-keymap mayhem-dashboard-mode-map
  :parent vui-mode-map
  "g" #'mayhem-dashboard-refresh
  "q" #'quit-window)

(define-derived-mode mayhem-dashboard-mode vui-mode "Mayhem"
  "Major mode for the Mayhem dashboard."
  (setq-local revert-buffer-function #'mayhem-sync-revert-buffer))

(defun mayhem-dashboard--projects (projects)
  "Return the vnodes listing PROJECTS, as from `mayhem--group-targets'."
  (apply #'vui-fragment
         (mapcan
          (lambda (project)
            (cons (vui-text (concat "  " (propertize (car project)
                                                     'face 'mayhem-project)
                                    "\n"))
                  (mapcar (lambda (target)
                            (vui-text (concat "    "
                                              (propertize target
                                                          'face 'mayhem-target)
                                              "\n")))
                          (cdr project))))
          projects)))

(mayhem-sync-define-resource projects ()
  :fetch #'mayhem--fetch-projects)

(vui-defcomponent mayhem-dashboard ()
  "The dashboard: every project visible to the user, with its targets."
  :render
  (let* ((snapshot (mayhem-sync-use-resource '(projects)))
         (fetched (plist-get snapshot :fetched-at))
         (projects (plist-get snapshot :data))
         (failure (plist-get snapshot :error)))
    (vui-fragment
     (vui-text (propertize "Mayhem" 'face 'mayhem-section-heading))
     (vui-newline)
     (vui-newline)
     (vui-text (propertize (if fetched
                               (format "Projects (%d)" (length projects))
                             "Projects")
                           'face 'mayhem-section-heading))
     (vui-newline)
     (cond (projects (mayhem-dashboard--projects projects))
           (fetched (vui-text (concat "  " (propertize "No projects" 'face 'shadow)
                                      "\n")))
           (failure (vui-text (concat (propertize "Fetching projects failed: "
                                                'face 'error)
                                    failure "\n")))))))

;;;###autoload
(defun mayhem ()
  "Open the Mayhem dashboard."
  (interactive)
  (let ((buf (get-buffer-create "*mayhem*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'mayhem-dashboard-mode)
        (mayhem-dashboard-mode)))
    (vui-mount (vui-component 'mayhem-dashboard) (buffer-name buf))))

(defun mayhem-dashboard-refresh ()
  "Fetch the dashboard afresh; it stays shown until the new data lands."
  (interactive)
  (mayhem-sync-refresh))

(provide 'mayhem)
;;; mayhem.el ends here
