;;; mayhem-workspace.el --- Workspace page for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; A workspace's page, `*mayhem: owner*': the projects of one owner (a
;; user or an org) visible to the user, each with its targets.  RET on
;; a project or a target opens its page.
;;
;; The API lists a workspace's projects only to its members, so they
;; come from the list of every visible project, which the root page
;; reads too; a workspace's targets are listed to anyone who can see them.

;;; Code:

(require 'seq)
(require 'vui)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)

(declare-function mayhem-project-open "mayhem-project" (owner project))
(declare-function mayhem-target-open "mayhem-target" (owner project target))

(mayhem-sync-define-resource projects ()
  :fetch #'mayhem--fetch-projects)

(defconst mayhem-workspace--targets-max-age 300
  "Seconds a workspace's targets are reused.
Targets come and go rarely, and every `mayhem-jump' asks for each
workspace's, every page of them.")

(mayhem-sync-define-resource workspace-targets (owner)
  :fetch (lambda (done) (mayhem--fetch-workspace-targets owner done))
  :max-age mayhem-workspace--targets-max-age)

(define-derived-mode mayhem-workspace-mode mayhem-page-mode "Mayhem Workspace"
  "Major mode for a Mayhem workspace's page.")

(defun mayhem-workspace--render (owner projects targets)
  "Return the vnodes listing PROJECTS of OWNER, each with its TARGETS."
  (let ((mine (seq-filter (lambda (p) (equal (alist-get 'owner p) owner)) projects))
        (types (mayhem--target-types (list (cons owner targets)))))
    (vui-fragment
     (mayhem-heading (format "Projects (%d)" (length mine)))
     (if (null mine)
         (mayhem-notice "No projects")
       (apply #'vui-fragment
              (mapcan
               (lambda (project)
                 (let ((slug (car project)))
                   (cons (mayhem-row (concat (propertize slug 'face 'mayhem-project) "\n")
                                     (lambda () (mayhem-project-open owner slug))
                                     "RET: open project")
                         (mapcar (lambda (target)
                                   (mayhem-row (concat "  "
                                                       (propertize target 'face 'mayhem-target)
                                                       (when-let* ((type (gethash
                                                                          (concat owner "/" slug
                                                                                  "/" target)
                                                                          types)))
                                                         (propertize
                                                          (concat "  " (mayhem-target-type type))
                                                          'face 'mayhem-label))
                                                       "\n")
                                               (lambda () (mayhem-target-open owner slug target))
                                               "RET: open target"))
                                 (cdr project)))))
               (mayhem--group-targets mine targets)))))))

(defun mayhem-workspace--skeleton ()
  "Return grey bars shaped like a workspace's page, shown until its data lands."
  (vui-fragment
   (mayhem-heading "Projects")
   (mayhem-skeleton '((22) ("  " 14) ("  " 20)
                      (18) ("  " 10)
                      (26) ("  " 16) ("  " 12)))))

(vui-defcomponent mayhem-workspace-page (owner)
  "The page of the workspace OWNER."
  :render
  (let ((snapshot (mayhem-sync-combine
                   (mayhem-sync-use-resource '(projects))
                   (mayhem-sync-use-resource (list 'workspace-targets owner)))))
    (vui-fragment
     (mayhem-page-heading "workspace" owner nil nil)
     (vui-newline)
     (mayhem-snapshot-view snapshot "workspace" (mayhem-workspace--skeleton)
                           (lambda (data)
                             (mayhem-workspace--render owner (nth 0 data) (nth 1 data)))))))

(defun mayhem-workspace-open (owner)
  "Open the page of the workspace OWNER."
  (mayhem-open-page (format "*mayhem: %s*" owner)
                    #'mayhem-workspace-mode
                    (lambda () (vui-component 'mayhem-workspace-page :owner owner))
                    (list 'workspace owner)))

(provide 'mayhem-workspace)
;;; mayhem-workspace.el ends here
