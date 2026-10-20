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

(declare-function mayhem-jump "mayhem" ())

(defvar-keymap mayhem-page-mode-map
  :parent vui-mode-map
  "C-c C-j" #'mayhem-jump
  "C-c C-o" #'mayhem-browse
  "g" #'mayhem-refresh
  "q" #'mayhem-quit-window
  "S-<return>" #'mayhem-visit-other-window)

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

(defun mayhem-row (line on-visit help-echo)
  "Return a RET-able row showing LINE, a propertized string ending in newline.
ON-VISIT is a function of no arguments that RET calls.  HELP-ECHO reads
\"RET: <imperative>\", such as \"RET: open project\"."
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") (lambda () (interactive) (funcall on-visit)))
    (define-key map [mouse-1] (lambda () (interactive) (funcall on-visit)))
    (vui-region :keymap map
      (vui-text (mayhem--default-help-echo (propertize line 'mouse-face 'highlight)
                                           help-echo)))))

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

(defun mayhem-field (label value)
  "Return a vnode for a LABEL: VALUE line of a page's header."
  (vui-text (concat (propertize (format "%-12s" label) 'face 'mayhem-label)
                    (or value "") "\n")))

(defun mayhem-heading (text)
  "Return a vnode for the section heading TEXT and its newline."
  (vui-text (concat (propertize text 'face 'mayhem-section-heading) "\n")))

(defun mayhem-notice (text &optional face)
  "Return a vnode for TEXT where data would be, in FACE or `shadow'."
  (vui-text (concat "  " (propertize text 'face (or face 'shadow)) "\n")))

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

(defun mayhem-tab-row (tabs width)
  "Return a row of TABS underlined across WIDTH columns, as a tab bar.
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
                  (* 2 (1- (length tabs))))))
    ;; One node, so the gaps between the tabs are underlined too.
    (vui-fragment
     (apply #'vui-hstack :spacing 0
            (append (cdr (mapcan (lambda (n) (list (vui-text "  " :face 'underline) n))
                                 nodes))
                    (list (vui-text (make-string (max 0 (- width used)) ?\s)
                                    :face 'underline))))
     (vui-newline))))

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

(provide 'mayhem-vui)
;;; mayhem-vui.el ends here
