;;; mayhem-search.el --- Find workspaces, projects and targets  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Reading a workspace, project or target with completion, for
;; `mayhem-jump' (C-c C-j on every page).  The API has no search, so
;; it completes on the sync store: the list of every visible project
;; and each workspace's targets, the resources the dashboard and the
;; workspace pages read.  The prompt opens at once on what is stored,
;; however old, and refetches behind it; what lands shows on the next
;; keystroke.

;;; Code:

(require 'seq)
(require 'mayhem-core)
(require 'mayhem-sync)
(require 'mayhem-vui)
(require 'mayhem-workspace)

(declare-function mayhem-project-open "mayhem-project" (owner project))
(declare-function mayhem-target-open "mayhem-target" (owner project target))

(defun mayhem-search--targets (owner)
  "Return the stored targets of the workspace OWNER."
  (plist-get (mayhem-sync-read (list 'workspace-targets owner)) :data))

(defun mayhem-search--candidates (projects targets)
  "Return PROJECTS and TARGETS as paths to search, with the targets' types.
That is (PATHS . TYPES).  TARGETS is an alist of each owner to its
targets; TYPES is `mayhem--target-types' of them."
  (cons (mayhem--search-candidates projects targets)
        (mayhem--target-types targets)))

(defun mayhem-search--request (projects)
  "Refetch in the background what is searched, unless fetched just now.
That is, every project and the targets of the workspaces of PROJECTS."
  (mayhem-sync-request '(projects))
  (dolist (workspace (mayhem--workspaces projects))
    (mayhem-sync-request (list 'workspace-targets (car workspace)))))

(defun mayhem-search--annotate (candidate types)
  "Return what kind of page CANDIDATE opens; a target's, with its type.
TYPES is `mayhem--target-types' of the targets."
  (propertize (pcase (seq-count (lambda (c) (eq c ?/)) candidate)
                (0 "  workspace")
                (1 "  project")
                (_ (concat "  " (mayhem-target-kind (gethash candidate types)))))
              'face 'mayhem-label))

(defun mayhem-search--table (candidates)
  "Return a completion table of CANDIDATES, a box of (PATHS . TYPES).
It reads the box's car on each call, so it completes on what is put
there."
  (lambda (string pred action)
    (if (eq action 'metadata)
        `(metadata (category . mayhem)
                   (annotation-function
                    . ,(lambda (c) (mayhem-search--annotate c (cdar candidates))))
                   ;; Keep each workspace above its projects, each above its targets.
                   (display-sort-function . identity)
                   (cycle-sort-function . identity))
      (complete-with-action action (caar candidates) string pred))))

(defun mayhem-search-read (prompt)
  "Read with PROMPT a workspace, project or target, as its path.
That is \"owner\", \"owner/project\" or \"owner/project/target\".
It offers at once what the store has, and what fetches bring after."
  ;; Kept here, so a fetch landing re-reads from the store only what it changed.
  (let* ((projects (plist-get (mayhem-sync-read '(projects)) :data))
         (targets (mapcar (pcase-lambda (`(,owner . ,_))
                            (cons owner (mayhem-search--targets owner)))
                          (mayhem--workspaces projects)))
         (candidates (list (mayhem-search--candidates projects targets)))
         (on-change
          (lambda (keys)
            (let (changed)
              (when (member (mayhem-sync-spec-key '(projects)) keys)
                (setq projects (plist-get (mayhem-sync-read '(projects)) :data)
                      targets (mapcar (pcase-lambda (`(,owner . ,_))
                                        (or (assoc owner targets)
                                            (cons owner (mayhem-search--targets owner))))
                                      (mayhem--workspaces projects))
                      changed t)
                ;; New projects may bring workspaces, whose targets to fetch.
                (mayhem-search--request projects))
              (dolist (cell targets)
                (when (member (mayhem-sync-spec-key (list 'workspace-targets (car cell))) keys)
                  (setcdr cell (mayhem-search--targets (car cell)))
                  (setq changed t)))
              (when changed
                (setcar candidates (mayhem-search--candidates projects targets)))))))
    (unwind-protect
        (progn
          (add-hook 'mayhem-sync-change-functions on-change)
          (mayhem-search--request projects)
          (completing-read prompt (mayhem-search--table candidates) nil t))
      (remove-hook 'mayhem-sync-change-functions on-change))))

(defun mayhem-search-open (path)
  "Open the page of PATH, a path from `mayhem-search-read'."
  (pcase (split-string path "/")
    (`(,owner) (mayhem-workspace-open owner))
    (`(,owner ,project) (mayhem-project-open owner project))
    (`(,owner ,project ,target) (mayhem-target-open owner project target))
    (_ (user-error "Mayhem: Not a workspace, project or target: %s" path))))

(provide 'mayhem-search)
;;; mayhem-search.el ends here
