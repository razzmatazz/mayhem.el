;;; mayhem-vui.el --- Shared page parts for mayhem.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Saulius Menkevičius

;; Author: Saulius Menkevičius <sauliusmenkevicius@fastmail.com>
;; Assisted-by: Claude:claude-opus-5-5

;; This file is not part of GNU Emacs.

;;; Commentary:

;; What every mayhem.el page shares: the base mode and its keys, faces,
;; RET-able rows, and how pages open in windows.  Windows follow Magit
;; and octocat.el: RET on a page opens the next one in the same window,
;; S-RET in another window, and `q' steps back out.

;;; Code:

(require 'browse-url)
(require 'seq)
(require 'subr-x)
(require 'vui)
(require 'mayhem-core)
(require 'mayhem-sync)

(defcustom mayhem-max-width 100
  "Most columns a page's lines take, or nil for the whole window.
In a narrower window the pages narrow too: a row gives up columns of
its title or name, cut with …, and wrapped text wraps sooner."
  :type '(choice (const :tag "No limit" nil) integer)
  :group 'mayhem)

(defun mayhem-page-width ()
  "Return the columns the current page's lines keep within.
That is what fits a line of the window showing the page, else of the
selected window, at most `mayhem-max-width'.  vui re-renders a page
when its window's width changes, so the page follows it.

`window-max-chars-per-line' selects the window, which resets the
buffer's point to the window's point; mid-render that scrambles the
page, so point is saved around it."
  (let ((width (save-excursion
                 (window-max-chars-per-line (or (get-buffer-window nil t)
                                                (selected-window))))))
    (if mayhem-max-width (min width mayhem-max-width) width)))

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

(defface mayhem-skeleton
  '((((class color) (background dark)) :background "gray25")
    (((class color) (background light)) :background "gray88")
    (t :inverse-video t))
  "Face for the grey bars standing in for content that is still loading."
  :group 'mayhem)

(defface mayhem-label
  '((t :inherit shadow))
  "Face for field labels and secondary text."
  :group 'mayhem)


;;;; Windows

(defun mayhem-buffer-p (&optional buffer)
  "Return non-nil if BUFFER (default: the current one) is a mayhem page."
  (provided-mode-derived-p
   (buffer-local-value 'major-mode (or buffer (current-buffer)))
   'mayhem-page-mode))

(defun mayhem-display-buffer (buffer)
  "Show BUFFER and select its window, as Magit does.
From a mayhem page, in the selected window; from elsewhere, wherever
`display-buffer' puts it.  `display-buffer-alist' overrides both."
  (pop-to-buffer buffer (and (mayhem-buffer-p) '(display-buffer-same-window)))
  ;; A window with no earlier buffers was made for BUFFER, so `q' may
  ;; delete it, as `magit-maybe-set-dedicated' does.
  (unless (window-prev-buffers)
    (set-window-parameter nil 'mayhem-dedicated t)))

(defun mayhem-call-in-other-window (fn)
  "Call FN, showing the page it opens in another window, selected.
A lone window is split to the right; else another window is reused, so
repeated opens keep one pane."
  (let ((display-buffer-overriding-action
         '((display-buffer-reuse-window
            display-buffer-use-some-window
            display-buffer-in-direction)
           (direction . right)
           (inhibit-same-window . t))))
    (funcall fn)))

(defun mayhem-visit ()
  "Do what RET does at point.
Rows and buttons each bind RET their own way, so look it up."
  (interactive)
  (let ((command (or (key-binding [return] t) (key-binding (kbd "RET") t)))
        (last-command-event ?\r))
    (if (and (commandp command) (not (eq command #'mayhem-visit)))
        (call-interactively command)
      (user-error "Mayhem: Nothing to open here"))))

(defun mayhem-visit-other-window ()
  "Do what RET does at point, showing the page it opens in another window."
  (interactive)
  (mayhem-call-in-other-window #'mayhem-visit))

(defun mayhem-quit-window (&optional kill)
  "Quit the selected window and bury its buffer, or kill it with KILL.
As `quit-window', but a window made for mayhem.el is deleted once no
other mayhem page it showed is left."
  (interactive "P")
  (if (or (one-window-p)
          (not (window-parameter nil 'mayhem-dedicated))
          (seq-find (lambda (prev)
                      (let ((buffer (car prev)))
                        (and (not (eq buffer (current-buffer)))
                             (buffer-live-p buffer)
                             (mayhem-buffer-p buffer))))
                    (window-prev-buffers)))
      (quit-window kill)
    (let ((window (selected-window)))
      (quit-window kill)
      (when (window-live-p window)
        (delete-window window)))))


;;;; Pages

(defun mayhem-refresh ()
  "Fetch the page's data afresh; it stays shown until the new data lands."
  (interactive)
  (mayhem-sync-refresh))

(defvar-local mayhem-page nil
  "The page this buffer shows, as (KIND ARGS...); see `mayhem--url-page'.")

(defun mayhem-browse ()
  "Open the page shown in the web app, in a browser.
A browser even when `mayhem-open-urls' would bring the link back here."
  (interactive)
  (unless mayhem-page
    (user-error "Mayhem: No web page for this buffer"))
  (browse-url-with-browser-kind
   'external (mayhem--page-url (alist-get 'url (mayhem--read-config)) mayhem-page)))

(defvar-local mayhem-views nil
  "The names of the page's two views, as (DEFAULT OTHER); nil if it has one.
A page with two sets it in its mode, and renders the other while
`mayhem-other-view' is non-nil.")

(defvar-local mayhem-other-view nil
  "Non-nil while the page shows the second of `mayhem-views'.")

(defun mayhem-toggle-view ()
  "Switch the page between its two views, as a test case's bytes in hex or as text."
  (interactive)
  (unless mayhem-views
    (user-error "Mayhem: This page has one view"))
  (setq mayhem-other-view (not mayhem-other-view))
  (when-let* ((root (vui-get-instance (current-buffer))))
    (vui-rerender root))
  (message "Mayhem: Showing %s" (nth (if mayhem-other-view 1 0) mayhem-views)))

(declare-function mayhem "mayhem" ())
(declare-function mayhem-jump "mayhem" ())
(declare-function mayhem-workspace-open "mayhem-workspace" (owner))
(declare-function mayhem-project-open "mayhem-project" (owner project))
(declare-function mayhem-target-open "mayhem-target" (owner project target))
(declare-function mayhem-run-open "mayhem-run" (owner project target number))

(defvar-keymap mayhem-page-mode-map
  :parent vui-mode-map
  "C-c C-j" #'mayhem-jump
  "C-c C-o" #'mayhem-browse
  "C-c C-v" #'mayhem-toggle-view
  "F" #'mayhem-list-filter
  "g" #'mayhem-refresh
  "q" #'mayhem-quit-window
  "S-<return>" #'mayhem-visit-other-window)

;; Evil reads a map's `[STATE-state]' key as that state's bindings; set
;; here so we need not depend on Evil.  As in treemacs-evil and
;; octocat.el, `o' is RET and `O' S-RET; in normal state they would
;; otherwise open a line.
(dolist (state '("Normal" "Motion"))
  (let ((aux (make-sparse-keymap
              (format "Auxiliary keymap for %s state" state))))
    (keymap-set aux "o" #'mayhem-visit)
    (keymap-set aux "O" #'mayhem-visit-other-window)
    (define-key mayhem-page-mode-map
                (vector (intern (format "%s-state" (downcase state))))
                aux)))

(define-derived-mode mayhem-page-mode vui-mode "Mayhem"
  "Base mode of every mayhem.el page."
  ;; So `revert-buffer', and `gr' under Evil, refresh as `g' does.
  (setq-local revert-buffer-function #'mayhem-sync-revert-buffer)
  (mayhem--ts-eldoc-setup))

(defun mayhem-open-page (name mode component &optional page)
  "Show the page buffer NAME, in MODE, with COMPONENT's vnode.
COMPONENT is a function returning it; it is mounted only the first
time.  PAGE is what it shows, as (KIND ARGS...), for `mayhem-browse'.
A page already open is shown as it is, and refetches what is not
fresh, as opening a page does."
  (let ((buf (get-buffer name)))
    (if (and buf (vui-get-instance buf))
        (mayhem-sync-refresh buf t)
      (setq buf (get-buffer-create name))
      (with-current-buffer buf
        (unless (eq major-mode mode)
          (funcall mode)))
      ;; `vui-mount' ends with `switch-to-buffer'; the window is ours.
      (save-window-excursion
        (vui-mount (funcall component) name)))
    (with-current-buffer buf
      (setq mayhem-page page))
    (mayhem-display-buffer buf)))

(defconst mayhem-fit-min-width 10
  "Fewest columns a `mayhem-fit' part is cut to, so it stays readable.")

(defun mayhem-cut-middle (string width)
  "Return STRING cut to WIDTH columns by a … in its middle, or STRING if it fits.
Names differ at either end (`fuzz-foo-1', `fuzz-foo-2'), so both stay."
  (if (<= (string-width string) width)
      string
    (let* ((room (max 0 (1- width)))
           (head (truncate-string-to-width string (- room (/ room 2))))
           (start (length string)))
      (while (and (> start 0)
                  (<= (string-width (substring string (1- start))) (/ room 2)))
        (setq start (1- start)))
      (concat head (apply #'propertize "…" (text-properties-at 0 string))
              (substring string start)))))

(defun mayhem-fit (string width &optional middle)
  "Return STRING as the part of a `mayhem-line' that fits it to the page.
It is padded to WIDTH columns, or, on a page too narrow for the line,
cut with … to the columns the line's other parts leave, but no fewer
than `mayhem-fit-min-width'.  With MIDDLE, it is cut in the middle, as
names are; else at the end, as titles are."
  (list :fit string width middle))

(defun mayhem-line (parts &optional decorate)
  "Return a vnode of the line of PARTS, and its newline.
PARTS are strings, and at most one `mayhem-fit' part, which keeps the
line within `mayhem-page-width'.  DECORATE, when non-nil, is called on
each string shown, and returns it to show."
  (let ((decorate (or decorate #'identity)))
    (vui-fragment
     (apply #'vui-flex :width (mayhem-page-width) :spacing 0
            (mapcar (lambda (part)
                      (pcase part
                        (`(:fit ,string ,width ,middle)
                         (vui-flex-item
                          (lambda (room)
                            (let ((fit (min width (max room mayhem-fit-min-width))))
                              (vui-text (funcall decorate
                                                 (truncate-string-to-width
                                                  (if middle (mayhem-cut-middle string fit) string)
                                                  fit nil ?\s "…")))))))
                        (_ (vui-text (funcall decorate part)))))
                    (remq nil parts)))
     (vui-text (funcall decorate "\n")))))

(defun mayhem-row (line on-visit help-echo)
  "Return a RET-able row showing LINE.
LINE is a propertized string ending in newline, or the parts of a
`mayhem-line'.  ON-VISIT is a function of no arguments that RET calls.
HELP-ECHO reads \"RET: <imperative>\", such as \"RET: open project\"."
  (let ((map (make-sparse-keymap))
        (decorate (lambda (s)
                    (let ((s (propertize s 'mouse-face 'highlight)) (pos 0))
                      ;; Off the newline, else Emacs sees the rows as one
                      ;; stretch of `highlight' and lights them all on hover.
                      (while (string-match "\n" s pos)
                        (remove-text-properties (match-beginning 0) (match-end 0)
                                                '(mouse-face nil) s)
                        (setq pos (match-end 0)))
                      (mayhem--default-help-echo s help-echo)))))
    (define-key map (kbd "RET") (lambda () (interactive) (funcall on-visit)))
    (define-key map [mouse-1] (lambda () (interactive) (funcall on-visit)))
    (vui-region :keymap map
      (if (stringp line)
          (vui-text (funcall decorate line))
        (mayhem-line line decorate)))))

(defun mayhem--default-help-echo (string help-echo)
  "Return a copy of STRING with HELP-ECHO on the parts lacking a `help-echo'.
So a timestamp in a row keeps its exact time on hover."
  (let ((s (copy-sequence string)) (pos 0))
    (while (< pos (length s))
      (let ((next (next-single-property-change pos 'help-echo s (length s))))
        (unless (get-text-property pos 'help-echo s)
          (put-text-property pos next 'help-echo help-echo s))
        (setq pos next)))
    s))

(defun mayhem-field (label &rest values)
  "Return a vnode for a LABEL: VALUES line of a page's header.
Each of VALUES is a string, a vnode such as a `mayhem-link', or nil.
With none but nil and empty strings, it shows a grey -, so the line
reads as known to be empty."
  (let ((values (seq-remove (lambda (v) (or (null v) (equal v ""))) values)))
    (apply #'vui-fragment
           (vui-text (propertize (format "%-12s" label) 'face 'mayhem-label))
           (append (or (mapcar (lambda (v) (if (stringp v) (vui-text v) v)) values)
                       (list (vui-text (propertize "-" 'face 'mayhem-label))))
                   (list (vui-text "\n"))))))

(defun mayhem-page-link (text help-echo on-visit &optional face)
  "Return a vnode showing TEXT, in FACE or `link', that RET follows.
Following it calls ON-VISIT, of no arguments.  HELP-ECHO reads
\"RET: <imperative>\", such as \"RET: open run\"."
  (vui-button text :no-decoration t :face (or face 'link)
              :help-echo help-echo :on-click on-visit))

(defun mayhem-link (text url)
  "Return a vnode showing TEXT that RET opens URL with, through `browse-url'."
  (mayhem-page-link text (concat "RET: open " url) (lambda () (browse-url url))))

(defun mayhem-run-link (owner project target number &optional text face)
  "Return TEXT, or \"run #NUMBER\", linking to run NUMBER.
NUMBER is a run of TARGET of PROJECT of OWNER.  FACE is as for
`mayhem-page-link'."
  (mayhem-page-link (or text (format "run #%s" number)) "RET: open run"
                    (lambda () (mayhem-run-open owner project target number))
                    face))

(defconst mayhem-heading-part-width 24
  "Most columns a name takes in a page's heading; longer ones are cut.")

(defun mayhem-page-heading (kind owner project target &rest more)
  "Return a page's heading: HOST/OWNER/PROJECT/TARGET/MORE KIND.
See `mayhem--page-heading'."
  (mayhem--page-heading kind nil owner project target more))

(defun mayhem-target-page-heading (name owner project target)
  "Return the heading of a page below TARGET, which NAME names.
NAME is such as \"run #7\", \"defect !12\" or \"runs\", or a list as
`mayhem--page-heading' takes.  The breadcrumb
ends at TARGET's page, linked, and goes on with what of it the page
shows, NAME after TARGET's kind: host/o/p/t  code target, run #7.
TARGET is of PROJECT of OWNER; its type is read from the store, if
there."
  (let ((type (alist-get 'type (alist-get 'target (plist-get (mayhem-sync-read
                                                              (list 'target owner project target))
                                                             :data)))))
    (mayhem--page-heading (concat (mayhem-target-kind type) ",") t
                          owner project target nil name)))

(defun mayhem--page-heading (kind link-last owner project target more &optional name)
  "Return a page's heading: HOST/OWNER/PROJECT/TARGET/MORE KIND.
HOST is the Mayhem server's, `mayhem--host', naming the dashboard; it
is plain text, as one rarely walks up that far.  OWNER, PROJECT and
TARGET may be nil, from the end.  Each links to its page, so one can
walk up, except the last: that is the page itself, unless LINK-LAST.
MORE are parts below TARGET, strings or vnodes such as a
`mayhem-run-link'.  KIND, such as \"target\", says in `shadow' what the
page shows, as the last part is often a bare name or number; it is nil
when the last part says it, such as \"tests\".  NAME, if given, follows
KIND, naming the page: a string, or a list of strings and vnodes, such
as a `mayhem-run-link'.  A name longer than `mayhem-heading-part-width'
is cut in the middle, whole on hover."
  (let* ((face 'mayhem-section-heading)
         (parts (seq-filter
                 #'car
                 (list (list (or (mayhem--host) "Mayhem") nil nil)
                       (list owner "RET: open workspace"
                             (lambda () (mayhem-workspace-open owner)))
                       (list project "RET: open project"
                             (lambda () (mayhem-project-open owner project)))
                       (list target "RET: open target"
                             (lambda () (mayhem-target-open owner project target))))))
         (last (car (last parts))))
    (apply #'vui-fragment
           (append
            (cdr (mapcan (pcase-lambda (`(,name ,help ,open))
                           (let* ((shown (mayhem-cut-middle name mayhem-heading-part-width))
                                  (cut (not (eq shown name))))
                             (list (vui-text "/" :face face)
                                   (if (or (null open)
                                           (and (eq name (car last)) (null more) (not link-last)))
                                       (vui-text (if cut (propertize shown 'help-echo name) shown)
                                                 :face face)
                                     (mayhem-page-link shown (if cut (concat help " " name) help)
                                                       open (list 'link face))))))
                         parts))
            (mapcan (lambda (part)
                      (list (vui-text "/" :face face)
                            (if (stringp part) (vui-text part :face face) part)))
                    more)
            (and kind (list (vui-text (concat "  " kind) :face (list 'shadow face))))
            (cond ((stringp name) (list (vui-text (concat " " name) :face face)))
                  (name (cons (vui-text " " :face face)
                              (mapcar (lambda (part)
                                        (if (stringp part) (vui-text part :face face) part))
                                      name))))
            (list (vui-text "\n"))))))

(defun mayhem-repo-link (repo text &optional kind ref)
  "Return TEXT linking to REPO or its KIND REF, as `mayhem--repo-url' does.
Just TEXT when REPO is nil, or its host's KIND links are not known."
  (if-let* ((url (and repo (mayhem--repo-url repo kind ref))))
      (mayhem-link text url)
    text))

(defun mayhem-repo-field (url &optional indent)
  "Return the Repo field for the repository at URL, nil when URL is.
It shows the host, so it is plain where its links lead.  INDENT, a
string, goes before its label."
  (when url
    (let ((repo (mayhem--repo url)))
      (mayhem-field (concat indent "Repo") (if repo
                               (mayhem-repo-link repo (concat (car repo) "/" (cdr repo)))
                             url)))))

(defun mayhem-scm-fields (scm &optional indent)
  "Return a list of the Repo, Branch, Commit and CI fields of SCM, nil for none.
SCM is a run's alist with `mayhem--scm-fields'.  On GitHub, each
links to its page on its host.  INDENT, a string, goes before each
label."
  (let* ((repo (mayhem--repo (alist-get 'scm_remote_origin scm)))
         (branch (alist-get 'branch_name scm))
         (base (alist-get 'merge_base_branch_name scm))
         (revision (alist-get 'revision scm))
         (ci-url (mayhem--clean-url (alist-get 'ci_url scm)))
         (ci-type (alist-get 'ci_type scm)))
    (list
     (mayhem-repo-field (alist-get 'scm_remote_origin scm) indent)
     (when branch
       (mayhem-field (concat indent "Branch") (mayhem-repo-link repo branch 'branch branch)
                     (when (and base (not (equal base branch)))
                       (propertize "  base " 'face 'mayhem-label))
                     (when (and base (not (equal base branch)))
                       (mayhem-repo-link repo base 'branch base))))
     (when revision
       (mayhem-field (concat indent "Commit")
                     (mayhem-repo-link repo (substring revision 0 (min 7 (length revision)))
                                       'commit revision)
                     (when-let* ((subject (alist-get 'scm_commit_subject scm)))
                       (concat "  " subject))
                     (when-let* ((author (alist-get 'scm_commit_author scm)))
                       (propertize (concat "  by " author) 'face 'mayhem-label
                                   'help-echo (alist-get 'scm_commit_author_email scm)))))
     (when (or ci-url ci-type)
       (mayhem-field (concat indent "CI") (if ci-url
                              (mayhem-link (mayhem--ci-label ci-type ci-url) ci-url)
                            ci-type))))))

(defmacro mayhem-use-timer (deps interval active &rest body)
  "Run BODY every INTERVAL seconds while ACTIVE, tied to the component.
The timer starts when the component renders with ACTIVE true, and
restarts when DEPS, a list of variables as `vui-use-effect' takes,
change; ACTIVE should depend only on them.  It is cancelled when DEPS
change, when the component unmounts, when BODY returns nil (done), and
when BODY signals, so a broken frame is reported once, not every tick.
BODY runs in the component's context, so it may call `vui-set-state'.
From octocat.el's `octocat-vui-use-timer'."
  (declare (indent 3))
  (let ((timer (make-symbol "timer")))
    `(vui-use-effect ,deps
       (when ,active
         (let ((,timer nil))
           (setq ,timer
                 (run-with-timer
                  ,interval ,interval
                  (vui-with-async-context
                    (condition-case err
                        (unless (progn ,@body)
                          (cancel-timer ,timer))
                      (error (cancel-timer ,timer)
                             (signal (car err) (cdr err)))))))
           (lambda () (cancel-timer ,timer)))))))

(defconst mayhem-unfold-growth 0.5
  "How much of the distance still to go each frame of an unfolding moves.
It eases out onto its end; each frame moves at least one line.")

(defconst mayhem-unfold-peak 0.2
  "Most of an unfolding's whole distance one frame may move.
It caps the speed at the start, so an unfolding begins at full speed
rather than jumping most of the way in its first frame.")

(defconst mayhem-unfold-interval 0.025
  "Seconds between the frames of an unfolding.")

(defun mayhem-unfold-step (now from to)
  "Return the position after NOW of an unfolding going FROM to TO.
It starts fast and eases out, see `mayhem-unfold-growth'."
  (let* ((span (abs (- to from)))
         (step (max 1 (min (ceiling (* mayhem-unfold-peak span))
                           (ceiling (* mayhem-unfold-growth (abs (- to now))))))))
    (if (< from to) (min to (+ now step)) (max to (- now step)))))

(defun mayhem-use-unfold (shown to from)
  "Step the calling component's :shown state, SHOWN, from FROM to TO.
Return how many lines to show now.  Call it during render, as any
hook; the component's :shown starts at the end it is at rest on."
  (let* ((now (max (min shown (max to from)) (min to from)))
         (moving (/= now to)))
    (mayhem-use-timer (moving to) mayhem-unfold-interval moving
      (setq now (mayhem-unfold-step now from to))
      (vui-set-state :shown now)
      ;; Setting an unchanged value doesn't re-render, so stop at TO.
      (/= now to))
    now))

(vui-defcomponent mayhem-fold (title summary parts lines)
  "A header line TITLE that unfolds LINES under it, animated.
LINES are vnodes of a line each, nil ones left out.  Unfolded, the
line goes on with SUMMARY, plain; folded, with PARTS, so TAB reaches
their links.  Each of PARTS is a string or (TEXT . VNODE); those that
don't fit go.  Unfolding and folding start fast and ease out, a line
a frame at the end, as octocat.el's folds do.  It keeps whether it is
open itself."
  :state ((open nil) (shown 0))
  :render
  (let* ((lines (delq nil lines))
         (now (mayhem-use-unfold shown (if open (length lines) 0)
                                 (if open 0 (length lines))))
         (room (- (mayhem-page-width) 12)))
    (vui-fragment
     ;; The arrow and its space stand in for two of a field label's columns.
     (vui-button (concat (if open "▼ " "▶ ") title)
                 :no-decoration t :face 'mayhem-label :key 'fold-toggle
                 :help-echo (if open "RET: fold" "RET: unfold")
                 :on-click (lambda () (vui-set-state :open (not open))))
     (vui-text (make-string (max 1 (- 10 (string-width title))) ?\s))
     (if open
         (vui-text (propertize (truncate-string-to-width summary (max 10 room) nil nil "…")
                               'face 'mayhem-label))
       (let ((used 0) shown)
         (catch 'full
           (dolist (part parts)
             (let* ((sep (if shown 2 0))
                    (text (if (consp part) (car part) part)))
               (when (> (+ used sep (string-width text)) room)
                 (throw 'full nil))
               (setq used (+ used sep (string-width text)))
               (when shown (push (vui-text "  ") shown))
               (push (if (consp part) (cdr part) (vui-text part)) shown))))
         (apply #'vui-fragment (nreverse shown))))
     (vui-newline)
     (apply #'vui-fragment (seq-take lines now)))))

(vui-defcomponent mayhem-unfold-list (rows limit what)
  "The first LIMIT of ROWS, and a button unfolding the rest, animated.
ROWS are vnodes of a line each.  The button reads \"Show all 12 WHAT\",
then \"Show fewer\"; the rows unfold and fold back as a `mayhem-fold'
does.  Nil ROWS show nothing."
  :state ((all nil) (shown nil))
  :render
  (let* ((count (length rows))
         (limit (min limit count))
         (now (mayhem-use-unfold (or shown limit) (if all count limit)
                                 (if all limit count))))
    (vui-fragment
     (apply #'vui-fragment (seq-take rows now))
     (when (> count limit)
       (vui-fragment
        (vui-button (if all "Show fewer" (format "Show all %d %s" count what))
                    :help-echo (if all
                                   (format "RET: list the first %d" limit)
                                 "RET: list every one")
                    :on-click (lambda () (vui-set-state :all (not all))))
        (vui-newline))))))

(defun mayhem-source-fold (scm)
  "Return SCM's repo, branch, commit and parent, a `mayhem-fold'.
SCM is a run's alist with `mayhem--scm-fields', or a defect's.  The
line names its branch, commit and subject; folded, the branch and
commit link to their pages.  Nil when SCM names none of them."
  (let* ((repo (mayhem--repo (alist-get 'scm_remote_origin scm)))
         (parent (alist-get 'parent_revision scm))
         (revision (alist-get 'revision scm))
         (branch (alist-get 'branch_name scm))
         (short (and revision (substring revision 0 (min 7 (length revision)))))
         (subject (alist-get 'scm_commit_subject scm)))
    (when (or (alist-get 'scm_remote_origin scm) revision branch parent)
      (vui-component
       'mayhem-fold
       :title "Source"
       :summary (string-join (delq nil (list branch short subject)) "  ")
       :parts (delq nil (list (and branch (cons branch (mayhem-repo-link repo branch 'branch branch)))
                              (and short (cons short (mayhem-repo-link repo short 'commit revision)))
                              (and subject
                                   (truncate-string-to-width
                                    subject (max 10 (- (mayhem-page-width) 16
                                                       (length branch) (length short)))
                                    nil nil "…"))))
       :lines (append (mayhem-scm-fields scm "  ")
                      (list (when parent
                              (mayhem-field "  Parent"
                                            (mayhem-repo-link repo (substring parent 0 (min 7 (length parent)))
                                                              'commit parent)))))))))

(defun mayhem-image-link (image &optional digest)
  "Return IMAGE linking to its page when it has one, else plain.
DIGEST, if known, goes in its `help-echo'."
  (if-let* ((url (mayhem--image-url image)))
      (mayhem-page-link image (concat "RET: open " url (and digest (concat "\n" digest)))
                        (lambda () (browse-url url)))
    (propertize image 'help-echo digest)))

(defun mayhem-image-field (run)
  "Return the Image field of RUN, an alist, or nil when it has no image.
It links as `mayhem-image-link' does, with its digest."
  (when-let* ((image (alist-get 'docker_pullable run)))
    (mayhem-field "Image" (mayhem-image-link image (alist-get 'fetched_docker_image_digest run)))))

(defun mayhem-hardening-field (run &optional indent)
  "Return the Hardening field of RUN, an alist, or nil without one.
INDENT, a string, goes before its label."
  (let ((factors (alist-get 'n_exploitability_factors_total run)))
    (when (and factors (> factors 0))
      (mayhem-field (concat indent "Hardening")
                    (format "%s of %s exploitability factors"
                            (or (alist-get 'n_exploitability_factors_passing run) 0)
                            factors)))))

(defun mayhem-suite-size (run)
  "Return how many test cases are in RUN's test suite, or nil if unknown.
RUN is an alist.  A run can count 0 in its optimized set when the set
was never counted, yet its suite then holds every one of its test cases."
  (let ((optimized (alist-get 'n_optimized_set_testcases run)))
    (if (and optimized (> optimized 0))
        optimized
      (alist-get 'n_testcase_reports run))))

(defun mayhem-heading (text)
  "Return a vnode for the section heading TEXT and its newline."
  (vui-text (concat (propertize text 'face 'mayhem-section-heading) "\n")))

(defun mayhem-notice (text &optional face)
  "Return a vnode for TEXT where data would be, in FACE or `shadow'."
  (vui-text (concat (propertize text 'face (or face 'shadow)) "\n")))

(defun mayhem-skeleton-bar (width)
  "Return a grey bar WIDTH columns wide, as a string."
  (propertize (make-string (max 1 width) ?\s) 'face 'mayhem-skeleton))

(defun mayhem-skeleton (rows)
  "Return a vnode of grey bars standing in for content still loading.
ROWS are lines, each a list of bar widths and literal strings, such as
an indent or a field label."
  (vui-text (mapconcat (lambda (row)
                         (concat (mapconcat (lambda (x)
                                              (if (numberp x) (mayhem-skeleton-bar x) x))
                                            row "")
                                 "\n"))
                       rows "")))

(defconst mayhem-command-width 72
  "Most columns a shell command shown for copying takes before it wraps.")

(defun mayhem-command (cmd)
  "Return shell command CMD wrapped for a page, as `mayhem--split-command'.
It keeps within `mayhem-command-width' and the page's width."
  (mayhem--split-command cmd (max 20 (min mayhem-command-width (mayhem-page-width)))))

(defun mayhem-block (title text)
  "Return a section TITLE with TEXT below it from column 0, for copying.
Nothing when TEXT is empty."
  (when (and text (not (string-empty-p (string-trim text))))
    (vui-fragment
     (vui-newline)
     (mayhem-heading title)
     (vui-text (concat (string-trim-right text) "\n")))))

(defun mayhem-backtrace (frames)
  "Return FRAMES, as `mayhem--backtrace-frames' gives them, as text.
Each frame's number and function, its source below; inlined calls follow."
  (let ((n -1))
    (mapconcat
     (lambda (frame)
       (setq n (1+ n))
       (let ((first t))
         (mapconcat
          (pcase-lambda (`(,fn . ,src))
            (concat (if (not first)
                        (propertize "    inlined by " 'face 'mayhem-label)
                      (setq first nil)
                      (propertize (format "#%-3d" n) 'face 'mayhem-label))
                    ;; Dim a Rust symbol's +0x offset.
                    (if (string-match "\\+0x[[:xdigit:]]+\\'" fn)
                        (concat (propertize (substring fn 0 (match-beginning 0))
                                            'face 'mayhem-target)
                                (propertize (match-string 0 fn) 'face 'mayhem-label))
                      (propertize fn 'face 'mayhem-target))
                    (when src
                      (concat "\n      " (propertize src 'face 'mayhem-label)))))
          frame "\n")))
     frames "\n")))

(defun mayhem-tab-row (tabs &optional width)
  "Return a row of TABS underlined across WIDTH columns, as a tab bar.
WIDTH is `mayhem-page-width' when nil.
Each tab is (LABEL HELP ON-CLICK); the current one has no ON-CLICK and
is drawn as a heading, the others as buttons."
  (let* ((nodes (mapcar (pcase-lambda (`(,label ,help ,on-click))
                          (if on-click
                              (vui-button label :face '(mayhem-label underline)
                                          :help-echo help :on-click on-click)
                            (vui-text label :face '(mayhem-section-heading underline))))
                        tabs))
         ;; Buttons are drawn in brackets.
         (used (+ (apply #'+ (mapcar (pcase-lambda (`(,label ,_ ,on-click))
                                       (+ (string-width label) (if on-click 2 0)))
                                     tabs))
                  (* 2 (1- (length tabs)))))
         (width (or width (mayhem-page-width))))
    ;; One node, so the gaps between the tabs are underlined too.
    (vui-fragment
     (apply #'vui-hstack :spacing 0
            (append (cdr (mapcan (lambda (n) (list (vui-text "  " :face 'underline) n))
                                 nodes))
                    (list (vui-text (make-string (max 0 (- width used)) ?\s)
                                    :face 'underline))))
     (vui-newline))))

(defun mayhem-target-type (type)
  "Return how a target of TYPE, \"code\" or \"api\", is named: as it is."
  (if (stringp type) type ""))

(defun mayhem-target-kind (type)
  "Return what a target of TYPE is, such as \"code target\", for a heading."
  (string-trim (concat (mayhem-target-type type) " target")))

(defun mayhem-defect-severity-face (level)
  "Return the face for a defect of severity LEVEL, such as \"high\"."
  (pcase level
    ("high" 'error)
    ("medium" 'warning)
    (_ 'mayhem-label)))

(defun mayhem-table (lines items open help-echo)
  "Return LINES, from `mayhem-columns' with a header, as a table of ITEMS.
The header is plain; each line after it is a RET-able row calling OPEN
with its item.  HELP-ECHO is the rows'."
  (apply #'vui-fragment
         (vui-text (concat (car lines) "\n"))
         (seq-mapn (lambda (item line)
                     (mayhem-row (concat line "\n") (lambda () (funcall open item)) help-echo))
                   items (cdr lines))))

(defun mayhem-columns (rows &optional right header)
  "Return ROWS, each a list of strings, as lines in aligned columns.
Each column is as wide as its widest cell and two spaces from the
next; one empty in every row is left out.  The columns whose indexes
are in RIGHT are aligned right.  HEADER, a list of a name per column,
makes the first line theirs, in capitals and `mayhem-label'.  A name
of nil continues the one before, which then spans both columns, as
\"Defects\" over a count and its split by severity."
  (let* ((n (apply #'max 0 (mapcar #'length rows)))
         (widths (mapcar (lambda (i)
                           (apply #'max 0 (mapcar (lambda (row) (string-width (or (nth i row) "")))
                                                  rows)))
                         (number-sequence 0 (1- n))))
         (spans (when header
                  (let ((i 0) spans)
                    (while (< i n)
                      (let ((j (1+ i)))
                        (while (and (< j n) (null (nth j header)))
                          (setq j (1+ j)))
                        (push (number-sequence i (1- j)) spans)
                        (setq i j)))
                    (nreverse spans))))
         (shown (lambda (span) (seq-filter (lambda (k) (> (nth k widths) 0)) span)))
         (room (lambda (cols)
                 (+ (apply #'+ (mapcar (lambda (k) (nth k widths)) cols))
                    (* 2 (max 0 (1- (length cols))))))))
    ;; A name wider than its columns widens the first of them.
    (dolist (span spans)
      (let ((cols (funcall shown span))
            (name (or (nth (car span) header) "")))
        (when (and cols (> (string-width name) (funcall room cols)))
          (setf (nth (car cols) widths)
                (+ (nth (car cols) widths) (- (string-width name) (funcall room cols)))))))
    (let ((lines (mapcar (lambda (row)
                           (let (cells)
                             (dotimes (i n)
                               (when (> (nth i widths) 0)
                                 (let* ((cell (or (nth i row) ""))
                                        (pad (make-string (- (nth i widths) (string-width cell))
                                                          ?\s)))
                                   (push (if (memq i right) (concat pad cell) (concat cell pad))
                                         cells))))
                             (string-trim-right (string-join (nreverse cells) "  "))))
                         rows)))
      (if (not header)
          lines
        (cons (propertize
               (string-trim-right
                (mapconcat (lambda (cols)
                             (let ((name (upcase (or (nth (car cols) header) ""))))
                               (string-pad name (funcall room cols) nil
                                           (and (null (cdr cols)) (memq (car cols) right)))))
                           (delq nil (mapcar shown spans))
                           "  "))
               'face 'mayhem-label)
              lines)))))

(defun mayhem-defect-ids (defects)
  "Return the numbers of DEFECTS, alists, as \"!N\" padded to one width.
Each leads its defect's row, so the rows after it line up."
  (let* ((ids (mapcar (lambda (defect) (format "!%s" (alist-get 'defect_number defect)))
                      defects))
         (width (apply #'max 0 (mapcar #'string-width ids))))
    (mapcar (lambda (id) (string-pad id width)) ids)))

(defun mayhem-run-status-face (status)
  "Return the face of a run of STATUS, such as \"failed\", by how it went."
  (pcase status
    ("completed" 'success)
    ("failed" 'error)
    ("running" 'warning)
    (_ 'mayhem-label)))

(defun mayhem-run-status (run)
  "Return the status of RUN, an alist, coloured by how it went."
  (let ((status (mayhem--run-status run)))
    (propertize status 'face (mayhem-run-status-face status))))

(defun mayhem-testcase-status (defects)
  "Return a test case's status: \"failing\" with DEFECTS, a count, above 0."
  (if (> (or defects 0) 0)
      (propertize "failing" 'face 'error)
    (propertize "passing" 'face 'success)))

(defun mayhem-testcase-severities (test)
  "Return TEST's defects by severity, as \"1 high, 2 low\", or \"\".
TEST is as `mayhem--testcase-summary' has it."
  (mapconcat (lambda (level)
               (propertize (format "%d %s" (alist-get (intern level) test) level)
                           'face (mayhem-defect-severity-face level)))
             (seq-filter (lambda (level) (> (or (alist-get (intern level) test) 0) 0))
                         '("high" "medium" "low"))
             ", "))

(defun mayhem-testcase-type (regression)
  "Return a test case's type: \"regression\" if REGRESSION, else \"new\"."
  (if regression "regression" "new"))

(defun mayhem-snapshot-view (snapshot what skeleton render)
  "Return the vnode of a page part showing SNAPSHOT, a sync snapshot.
RENDER is called with the data once there is some.  Before that, it
shows SKELETON, a vnode shaped like the data to come, unless the fetch
failed: then it says fetching WHAT failed."
  (cond ((plist-get snapshot :fetched-at) (funcall render (plist-get snapshot :data)))
        ((and (plist-get snapshot :error) (not (plist-get snapshot :loading)))
         (vui-text (concat (propertize (format "Fetching %s failed: " what) 'face 'error)
                           (plist-get snapshot :error) "\n")))
        (t skeleton)))

;;;; List filters

;; A page listing every defect or run of a target fetches them all, so
;; it filters them here.  Its mode sets `mayhem-list-facets'; the filter
;; is buffer-local, kept across refreshes, and `F' or a facet's button
;; changes it.  The items are the page's resource, `mayhem-page'.

(defvar-local mayhem-list-facets nil
  "What the page's list filters by, as (LABEL . FN), in button order.
FN returns an item's value for the facet, a string or nil.  Nil when the
page has no filters.")

(defvar-local mayhem-list-filter nil
  "The page's filter, as (LABEL . VALUE) for each facet set.")

(defun mayhem-list-filtered (items)
  "Return ITEMS that match `mayhem-list-filter'."
  (seq-filter (lambda (item)
                (seq-every-p (pcase-lambda (`(,label . ,value))
                               (equal (funcall (alist-get label mayhem-list-facets
                                                          nil nil #'equal)
                                               item)
                                      value))
                             mayhem-list-filter))
              items))

(defun mayhem-list--check-filterable ()
  "Signal a `user-error' unless the page's list has filters."
  (unless mayhem-list-facets
    (user-error "Mayhem: This page has no filters")))

(defun mayhem-list--apply (filter)
  "Make FILTER the page's filter and show what passes it."
  (setq mayhem-list-filter filter)
  (when-let* ((root (vui-get-instance (current-buffer))))
    (vui-rerender root)))

(defun mayhem-list-filter-by (label)
  "Choose the value of the list's facet LABEL; the one set clears it."
  (mayhem-list--check-filterable)
  (let* ((fn (alist-get label mayhem-list-facets nil nil #'equal))
         (items (plist-get (mayhem-sync-read mayhem-page) :data))
         (values (seq-uniq (delq nil (mapcar fn items))))
         (current (alist-get label mayhem-list-filter nil nil #'equal))
         (marked (mapcar (lambda (v) (if (equal v current) (concat v " ✓") v))
                         (if current (cons current (delete current values)) values)))
         (table (lambda (string pred action)
                  (if (eq action 'metadata)
                      '(metadata (display-sort-function . identity))
                    (complete-with-action action marked string pred))))
         (value (string-remove-suffix
                 " ✓" (completing-read (format "%s (✓ = set): " label) table nil t))))
    (mayhem-list--apply
     (append (seq-remove (lambda (f) (equal (car f) label)) mayhem-list-filter)
             (unless (or (string-empty-p value) (equal value current))
               (list (cons label value)))))))

(defun mayhem-list-clear-filter ()
  "Show the whole list."
  (interactive)
  (mayhem-list--check-filterable)
  (mayhem-list--apply nil))

(defun mayhem-list-filter ()
  "Choose a facet of the list to filter by, or clear the filter."
  (interactive)
  (mayhem-list--check-filterable)
  (let ((choice (completing-read "Filter by: "
                                 (append (mapcar #'car mayhem-list-facets)
                                         (and mayhem-list-filter '("Clear")))
                                 nil t)))
    (if (equal choice "Clear")
        (mayhem-list-clear-filter)
      (mayhem-list-filter-by choice))))

(defun mayhem-list-filter-bar (items shown)
  "Return the line of the list's facet buttons, a set one with its value.
While a filter is set, a `[clear]' button follows, and how many of
ITEMS are SHOWN."
  (vui-fragment
   (apply #'vui-hstack :spacing 2
          (vui-text "Filter" :face 'mayhem-label)
          (append
           (mapcar (pcase-lambda (`(,label . ,_))
                     (let ((value (alist-get label mayhem-list-filter nil nil #'equal)))
                       (vui-button (if value (format "%s: %s" label value) label)
                                   :key label
                                   :face (unless value 'mayhem-label)
                                   :help-echo (format "RET: filter by %s" (downcase label))
                                   :on-click (lambda () (mayhem-list-filter-by label)))))
                   mayhem-list-facets)
           (and mayhem-list-filter
                (list (vui-button "clear" :key 'clear :face 'mayhem-label
                                  :help-echo "RET: show the whole list"
                                  :on-click #'mayhem-list-clear-filter)
                      (vui-text (format "%d of %d" (length shown) (length items))
                                :face 'mayhem-label)))))
   (vui-newline)))

(defun mayhem-tally (items fn &optional order face)
  "Return a line counting ITEMS by FN's value, as \"4 high, 2 medium\".
Values in ORDER come first, in it, the rest by count; FACE, a function
of a value, gives its face.  Nil when no item has a value."
  (let (counts)
    (dolist (item items)
      (when-let* ((v (funcall fn item)))
        (setf (alist-get v counts 0 nil #'equal) (1+ (alist-get v counts 0 nil #'equal)))))
    (when counts
      (setq counts (sort counts (lambda (a b)
                                  (let ((i (seq-position order (car a)))
                                        (j (seq-position order (car b))))
                                    (cond ((and i j) (< i j))
                                          (i t)
                                          (j nil)
                                          (t (> (cdr a) (cdr b))))))))
      (vui-text (concat (mapconcat (pcase-lambda (`(,v . ,n))
                                     (propertize (format "%d %s" n v)
                                                 'face (if face (funcall face v) 'mayhem-label)))
                                   counts
                                   (propertize ", " 'face 'mayhem-label))
                        "\n")))))

;;;; Defect trend

(mayhem-sync-define-resource defect-trend (owner project target window)
  :fetch (lambda (done)
           (mayhem--fetch-defect-trend owner project target window done)))

(defconst mayhem-trend--width 60
  "Columns of a defect trend chart, at most.")

(defconst mayhem-trend--margin 5
  "Columns left of a defect trend chart, for its scale.")

(defun mayhem-trend--chart-width ()
  "Return the columns of a defect trend chart on the current page."
  (max 10 (min mayhem-trend--width (- (mayhem-page-width) mayhem-trend--margin))))

(defconst mayhem-trend--height 4
  "Rows of a defect trend chart.")

(defconst mayhem-severities '("high" "medium" "low")
  "Severity levels, most severe first: the bottom layer of a trend chart.")

(defun mayhem-severity-counts (counts &optional kind)
  "Return active defects by severity, as \"3 high, 6 medium\", from COUNTS.
COUNTS is an alist with `n_defects_active_high' and the like, as a run
or project has.  KIND \"fixed\" counts fixed defects instead.  Levels
with none are left out; nil when there are none."
  (let ((parts (delq nil
                     (mapcar (lambda (level)
                               (let ((n (or (alist-get (intern (format "n_defects_%s_%s" (or kind "active") level))
                                                       counts)
                                            0)))
                                 (when (> n 0)
                                   (propertize (format "%d %s" n level)
                                               'face (mayhem-defect-severity-face level)))))
                             mayhem-severities))))
    (and parts (string-join parts ", "))))

(defun mayhem-trend--chart (points window width)
  "Return the vnodes charting POINTS of a defect trend over WINDOW.
POINTS are as `mayhem--fetch-defect-trend' gives them; WINDOW is a key
of `mayhem--trend-windows'.  The chart is at most WIDTH columns, its
scale aside.  Active defects are stacked by severity; each column's
time and counts are its `help-echo'."
  (cond
   ((eq points 'members-only)
    (mayhem-notice "Only members of the workspace see its defect trend"))
   ((null points)
    (mayhem-notice "No data"))
   (t
    (let* ((time-format (nth 4 (assq window mayhem--trend-windows)))
           (colw (max 1 (/ width (length points))))
           (count (lambda (p level) (or (alist-get (intern (concat "active_" level)) p) 0)))
           (stacks (mapcar (lambda (p) (mapcar (lambda (l) (funcall count p l))
                                               mayhem-severities))
                           points))
           (time (lambda (p) (format-time-string
                              time-format (encode-time (iso8601-parse (alist-get 'timestamp p))))))
           (tips (seq-mapn (lambda (p stack)
                             (format "%s  %d active%s" (funcall time p) (apply #'+ stack)
                                     (if (> (apply #'+ stack) 0)
                                         (concat ": " (string-join
                                                       (seq-mapn (lambda (n l) (format "%d %s" n l))
                                                                 stack mayhem-severities)
                                                       ", "))
                                       "")))
                           points stacks))
           (top (apply #'max 0 (mapcar (lambda (s) (apply #'+ s)) stacks)))
           (margin (max (1- mayhem-trend--margin) (length (number-to-string top))))
           (pad (make-string (1+ margin) ?\s))
           (rows (mayhem--stack-rows stacks mayhem-trend--height))
           (width (* colw (length points)))
           (first (funcall time (car points)))
           (last (funcall time (car (last points)))))
      (vui-text
       (concat
        (mapconcat
         (lambda (row)
           (concat (propertize (format (format "%%%ds " margin) (if (eq row (car rows)) top ""))
                               'face 'mayhem-label)
                   (apply #'concat
                          (seq-mapn (pcase-lambda (`(,char . ,layer) tip)
                                      (propertize (make-string colw char)
                                                  'face (if layer
                                                            (mayhem-defect-severity-face
                                                             (nth layer mayhem-severities))
                                                          'mayhem-label)
                                                  'help-echo tip 'mayhem-ts tip))
                                    row tips))
                   "\n"))
         rows "")
        pad (propertize (concat first (make-string (max 1 (- width (length first) (length last)))
                                                   ?\s)
                                last)
                        'face 'mayhem-label)
        "\n"
        pad (mapconcat (lambda (level)
                         (concat (propertize "█" 'face (mayhem-defect-severity-face level))
                                 (propertize (concat " " level) 'face 'mayhem-label)))
                       mayhem-severities "  ")
        "\n"))))))

(defun mayhem-trend-skeleton ()
  "Return grey bars shaped like a defect trend, and the blank line after."
  (vui-fragment
   (mayhem-heading "Defect trend")
   (mayhem-skeleton (make-list mayhem-trend--height
                               (list (make-string mayhem-trend--margin ?\s)
                                     (mayhem-trend--chart-width))))
   (vui-newline)))

(vui-defcomponent mayhem-trend (owner project target)
  "The defect trend of TARGET of PROJECT of OWNER, with its window selector.
Of the whole PROJECT when TARGET is nil.  Then a blank line.  Pages
show it through `mayhem-trend-view'."
  :state ((window 'month))
  :render
  (let ((snapshot (mayhem-sync-use-resource (list 'defect-trend owner project target window)))
        (width (mayhem-trend--chart-width)))
    (vui-fragment
     (mayhem-heading "Defect trend")
     (mayhem-tab-row (mapcar (pcase-lambda (`(,key ,label . ,_))
                               (list label (format "RET: show the last %s" label)
                                     (unless (eq key window)
                                       (lambda () (vui-set-state :window key)))))
                             mayhem--trend-windows)
                     (+ mayhem-trend--margin width))
     (mayhem-snapshot-view snapshot "defect trend"
                           (mayhem-skeleton (make-list mayhem-trend--height
                                                       (list (make-string mayhem-trend--margin ?\s)
                                                             width)))
                           (lambda (points) (mayhem-trend--chart points window width)))
     (vui-newline))))

(defun mayhem-trend-view (owner project target)
  "Return the `mayhem-trend' of TARGET of PROJECT of OWNER, for a page.
Nil for one who may not see it, so not a member of the workspace: the
page leaves it out.  The page decides, not the component, as vui wipes
the buffer when a component that rendered nothing re-renders alone."
  (unless (eq (plist-get (mayhem-sync-use-resource
                          (list 'defect-trend owner project target 'month))
                         :data)
              'members-only)
    (vui-component 'mayhem-trend :owner owner :project project :target target)))

(provide 'mayhem-vui)
;;; mayhem-vui.el ends here
