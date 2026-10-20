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
Each of VALUES is a string, a vnode such as a `mayhem-link', or nil."
  (apply #'vui-fragment
         (vui-text (propertize (format "%-12s" label) 'face 'mayhem-label))
         (append (mapcar (lambda (v) (if (stringp v) (vui-text v) v))
                         (delq nil values))
                 (list (vui-text "\n")))))

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
HOST is the Mayhem server's, `mayhem--host', naming the dashboard.
OWNER, PROJECT and TARGET may be nil, from the end.  Each part links
to its page, the dashboard first, so one can walk up, except the last:
that is the page itself.  MORE are parts below TARGET, strings or
vnodes such as a `mayhem-run-link'.  KIND, such as \"target\", says in
`shadow' what the page shows, as the last part is often a bare name or
number.  A name longer than `mayhem-heading-part-width' is cut in the middle,
whole on hover."
  (let* ((face 'mayhem-section-heading)
         (parts (seq-filter
                 #'car
                 (list (list (or (mayhem--host) "Mayhem") "RET: open dashboard" #'mayhem)
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
                                   (if (and (eq name (car last)) (null more))
                                       (vui-text (if cut (propertize shown 'help-echo name) shown)
                                                 :face face)
                                     (mayhem-page-link shown (if cut (concat help " " name) help)
                                                       open (list 'link face))))))
                         parts))
            (mapcan (lambda (part)
                      (list (vui-text "/" :face face)
                            (if (stringp part) (vui-text part :face face) part)))
                    more)
            (list (vui-text (concat "  " kind) :face (list 'shadow face))
                  (vui-text "\n"))))))

(defun mayhem-repo-link (repo text &optional kind ref)
  "Return TEXT linking to REPO or its KIND REF, as `mayhem--repo-url' does.
Just TEXT when REPO is nil, or its host's KIND links are not known."
  (if-let* ((url (and repo (mayhem--repo-url repo kind ref))))
      (mayhem-link text url)
    text))

(defun mayhem-repo-field (url)
  "Return the Repo field for the repository at URL, nil when URL is.
It shows the host, so it is plain where its links lead."
  (when url
    (let ((repo (mayhem--repo url)))
      (mayhem-field "Repo" (if repo
                               (mayhem-repo-link repo (concat (car repo) "/" (cdr repo)))
                             url)))))

(defun mayhem-scm-fields (scm)
  "Return the Repo, Branch, Commit and CI fields of SCM.
SCM is a run's alist with `mayhem--scm-fields'.  On GitHub, each
links to its page on its host."
  (let* ((repo (mayhem--repo (alist-get 'scm_remote_origin scm)))
         (branch (alist-get 'branch_name scm))
         (base (alist-get 'merge_base_branch_name scm))
         (revision (alist-get 'revision scm))
         (ci-url (mayhem--clean-url (alist-get 'ci_url scm)))
         (ci-type (alist-get 'ci_type scm)))
    (vui-fragment
     (mayhem-repo-field (alist-get 'scm_remote_origin scm))
     (when branch
       (mayhem-field "Branch" (mayhem-repo-link repo branch 'branch branch)
                     (when (and base (not (equal base branch)))
                       (propertize "  base " 'face 'mayhem-label))
                     (when (and base (not (equal base branch)))
                       (mayhem-repo-link repo base 'branch base))))
     (when revision
       (mayhem-field "Commit"
                     (mayhem-repo-link repo (substring revision 0 (min 7 (length revision)))
                                       'commit revision)
                     (when-let* ((subject (alist-get 'scm_commit_subject scm)))
                       (concat "  " subject))
                     (when-let* ((author (alist-get 'scm_commit_author scm)))
                       (propertize (concat "  by " author) 'face 'mayhem-label
                                   'help-echo (alist-get 'scm_commit_author_email scm)))))
     (when (or ci-url ci-type)
       (mayhem-field "CI" (if ci-url
                              (mayhem-link (mayhem--ci-label ci-type ci-url) ci-url)
                            ci-type))))))

(defun mayhem-image-field (run)
  "Return the Image field of RUN, an alist, or nil when it has no image.
It links to the image's page when it has one; its digest is the
`help-echo'."
  (when-let* ((image (alist-get 'docker_pullable run)))
    (mayhem-field "Image"
                  (let ((url (mayhem--image-url image))
                        (digest (alist-get 'fetched_docker_image_digest run)))
                    (if url
                        (mayhem-page-link image
                                          (concat "RET: open " url
                                                  (and digest (concat "\n" digest)))
                                          (lambda () (browse-url url)))
                      (propertize image 'help-echo digest))))))

(defun mayhem-hardening-field (run)
  "Return the Hardening field of RUN, an alist, or nil without one."
  (let ((factors (alist-get 'n_exploitability_factors_total run)))
    (when (and factors (> factors 0))
      (mayhem-field "Hardening"
                    (format "%s of %s exploitability factors"
                            (or (alist-get 'n_exploitability_factors_passing run) 0)
                            factors)))))

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

(defun mayhem-defect-severity-face (level)
  "Return the face for a defect of severity LEVEL, such as \"high\"."
  (pcase level
    ("high" 'error)
    ("medium" 'warning)
    (_ 'mayhem-label)))

(defun mayhem-run-status (run)
  "Return the status of RUN, an alist, coloured by how it went."
  (let ((status (mayhem--run-status run)))
    (propertize status 'face (pcase status
                               ("completed" 'success)
                               ("failed" 'error)
                               ("running" 'warning)
                               (_ 'mayhem-label)))))

(defun mayhem-testcase-status (defects)
  "Return a test case's status: \"failing\" with DEFECTS, a count, above 0."
  (if (> (or defects 0) 0)
      (propertize "failing" 'face 'error)
    (propertize "passing" 'face 'success)))

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
