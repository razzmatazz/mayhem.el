;;; screenshots.el --- Screenshots of mayhem.el's pages  -*- lexical-binding: t; -*-

;;; Commentary:

;; Renders pages from the made-up data in fixtures.el into
;; docs/screenshots/, for `make screenshots': each as a PNG of a GUI
;; frame and as text, beside README.md there, which links them.  Each shot there is a
;; marker naming the page, then what this writes, up to an end marker:
;;
;;   <!-- screenshot: (target "acme" "libpng" "fuzz-png") :name "target-trend" :press ("▶ Trend") -->
;;   <!-- /screenshot -->
;;
;; The page is (KIND ARGS...), opened by `mayhem-KIND-open', or
;; (dashboard).  :press lists buttons to press first, by their text, or
;; rows to press RET on, by a text on them.
;; :name names its files, NAME.png and NAME.txt; it defaults to KIND.  To add a shot, add a
;; marker; to show other data, edit fixtures.el.  A resource
;; fixtures.el lacks fails the run, naming it.
;;
;; Pages fetch through the sync layer as usual; only each resource's
;; fetch is replaced, by its fixture.  The clock is frozen at
;; `mayhem-screenshots-now', so ages and charts stay put.
;;
;; Run it in a GUI Emacs, as `make screenshots' does under Xvfb; in a
;; terminal or batch Emacs only the text is written.

;;; Code:

(defvar mayhem-screenshots-root
  (expand-file-name "../../" (file-name-directory (or load-file-name buffer-file-name)))
  "The mayhem.el checkout.")

;; The dependencies, as Eldev would load them: the image's, else the checkout's.
(let ((package-user-dir (expand-file-name (format ".eldev/%s.%s/packages"
                                                  emacs-major-version emacs-minor-version)
                                          (or (getenv "MAYHEM_DEPS")
                                              mayhem-screenshots-root))))
  (when (file-directory-p package-user-dir)
    (package-initialize)))
(add-to-list 'load-path mayhem-screenshots-root)

(require 'cl-lib)
(require 'mayhem)

(declare-function x-export-frames "xfns.c" (&optional frames type))
(declare-function scroll-bar-mode "scroll-bar" (&optional arg))

(load (expand-file-name "test/screenshots/fixtures" mayhem-screenshots-root) nil t)
(defvar mayhem-screenshots-fixtures)
(defvar mayhem-screenshots-now)

(defvar mayhem-screenshots-directory
  (expand-file-name "docs/screenshots/" mayhem-screenshots-root)
  "Where the shots go: README.md, whose shots are rewritten, and the PNGs.")

(defvar mayhem-screenshots-file (expand-file-name "README.md" mayhem-screenshots-directory)
  "The Markdown file whose shots are rewritten.")

(defvar mayhem-screenshots-font "JetBrains Mono 13"
  "The font of the PNGs.")

(defvar mayhem-screenshots--problems nil
  "What went wrong in the shots, newest first: resources with no fixture, say.")

(defun mayhem-screenshots--props (props spec)
  "Return resource SPEC's PROPS, fetching its fixture instead of from the API."
  (let ((fixture (assoc spec mayhem-screenshots-fixtures)))
    (unless fixture
      (cl-pushnew (format "No fixture for %S" spec) mayhem-screenshots--problems
                  :test #'equal))
    (plist-put (copy-sequence props) :fetch
               (lambda (done)
                 ;; Answer later, as the API does, so pages paint their
                 ;; skeleton first.
                 (run-at-time 0 nil
                              (lambda ()
                                (if fixture
                                    (funcall done t (cdr fixture))
                                  (funcall done nil (format "No fixture for %S" spec)))))))))

(defun mayhem-screenshots--setup ()
  "Point mayhem.el at fixtures, a fresh store and a frozen clock; style the frame."
  (let ((dir (make-temp-file "mayhem-screenshots" t)))
    (setq mayhem-config-file (expand-file-name "mayhem" dir)
          mayhem-sync-directory (expand-file-name "sync/" dir)
          mayhem-max-width 100)
    (with-temp-file mayhem-config-file
      (insert "[DEFAULT]\nurl = https://app.mayhem.security\ntoken = fixture\n")))
  (set-time-zone-rule "UTC")
  (advice-add 'mayhem-sync--props :around
              (lambda (fn spec) (mayhem-screenshots--props (funcall fn spec) spec)))
  (advice-add 'current-time :override
              (lambda () (time-convert mayhem-screenshots-now 'list)))
  (advice-add 'float-time :around
              (lambda (fn &optional time) (funcall fn (or time mayhem-screenshots-now))))
  ;; So a page is as wide whatever the window.
  (advice-add 'mayhem-page-width :override (lambda () mayhem-max-width))
  (when (display-graphic-p)
    (load-theme 'modus-operandi t)
    (set-frame-font mayhem-screenshots-font nil t)
    (menu-bar-mode -1)
    (tool-bar-mode -1)
    (scroll-bar-mode -1)
    (blink-cursor-mode -1)
    (setq-default cursor-type nil
                  cursor-in-non-selected-windows nil
                  mode-line-format nil)
    ;; The pointer rests somewhere on the frame; it must not light a row.
    (setq mouse-highlight nil
          inhibit-message t)))

(defun mayhem-screenshots--settle (buffer)
  "Wait until BUFFER has fetched everything and stopped changing.
That is, unchanged for 0.3s: a fold starts unfolding a moment after
it is pressed."
  (let ((last nil) (still 0) (tries 0))
    (while (and (< still 15) (< (cl-incf tries) 400))
      (accept-process-output nil 0.02)
      (let ((text (with-current-buffer buffer (buffer-string))))
        (if (and (equal text last) (zerop (hash-table-count mayhem-sync--loading)))
            (cl-incf still)
          (setq still 0 last text))))))

(defun mayhem-screenshots--press (buffer label)
  "Press the button whose text is LABEL in BUFFER, or RET on its row."
  (with-current-buffer buffer
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (if (search-forward label nil t)
          (let ((pos (match-beginning 0)))
            (if (button-at pos)
                (push-button pos)
              ;; A RET-able row: see docs/user-interface-conventions.md.
              (goto-char pos)
              (call-interactively (key-binding (kbd "RET")))))
        (push (format "No button %S on %s" label (buffer-name))
              mayhem-screenshots--problems)))))

(defun mayhem-screenshots--text (buffer)
  "Return BUFFER's text, without trailing blanks."
  (with-current-buffer buffer
    (replace-regexp-in-string
     "[ \t]+$" "" (string-trim-right (buffer-substring-no-properties (point-min) (point-max))))))

(defun mayhem-screenshots--png (buffer file)
  "Save BUFFER, shown whole in a frame of its own, to FILE as PNG."
  (let* ((lines (with-current-buffer buffer
                  (count-lines (point-min) (point-max))))
         (frame (make-frame `((minibuffer . nil) (width . ,(+ mayhem-max-width 2))
                              (height . ,(1+ lines)) (left-fringe . 0) (right-fringe . 0)
                              (internal-border-width . 16) (visibility . t)))))
    (unwind-protect
        (progn
          (set-window-buffer (frame-root-window frame) buffer)
          (with-selected-frame frame
            (set-window-start nil 1)
            (redisplay t))
          (make-directory (file-name-directory file) t)
          (let ((coding-system-for-write 'binary))
            (write-region (x-export-frames frame 'png) nil file nil 0)))
      (delete-frame frame t))))

(defun mayhem-screenshots--clock ()
  "Return the seconds since the epoch, of the real clock, not the frozen one.
`format-time-string' reads it in C, past the advice."
  (string-to-number (format-time-string "%s.%N")))

(defun mayhem-screenshots-shoot (page &optional press png)
  "Return the text of PAGE, (KIND ARGS...), after pressing PRESS.
KIND names the command `mayhem-KIND-open' that opens it; (dashboard)
is `mayhem'.  PRESS is a list of the labels of buttons to press, in
turn.  With PNG, a file name, save the page there too, when graphic."
  (save-window-excursion
   (let ((start (mayhem-screenshots--clock)))
    (if (equal page '(dashboard))
        (mayhem)
      (apply (intern (format "mayhem-%s-open" (car page))) (cdr page)))
    (let ((buffer (window-buffer (selected-window))))
      (mayhem-screenshots--settle buffer)
      (dolist (label press)
        (mayhem-screenshots--press buffer label)
        (mayhem-screenshots--settle buffer))
      (when (and png (display-graphic-p))
        (mayhem-screenshots--png buffer png))
      ;; So a slow page shows.
      (princ (format "%5.2fs %S\n" (- (mayhem-screenshots--clock) start) page)
             #'external-debugging-output)
      (prog1 (mayhem-screenshots--text buffer)
        (kill-buffer buffer))))))

(defconst mayhem-screenshots--marker "^<!-- screenshot: \\(.*\\) -->\n"
  "A shot's marker.")

(defun mayhem-screenshots--shot-end ()
  "Return the end of what was written for the shot whose marker point is after.
That is after its end marker, or point when there is none yet: a shot
just added."
  (save-match-data
   (save-excursion
    (let ((next (save-excursion
                  (if (re-search-forward mayhem-screenshots--marker nil t)
                      (match-beginning 0)
                    (point-max)))))
      (search-forward "<!-- /screenshot -->\n" next t)
      (point)))))

(defun mayhem-screenshots--block (marker name)
  "Return the Markdown of the shot at MARKER, whose files are named NAME."
  (let ((image (concat name ".png")))
    (concat "<!-- screenshot: " marker " -->\n"
            (if (file-exists-p (expand-file-name image mayhem-screenshots-directory))
                (format "![%s](%s)\n\n" name image)
              "")
            (format "[As text](%s.txt)\n" name)
            "<!-- /screenshot -->\n")))

(defun mayhem-screenshots-update ()
  "Rewrite every shot of `mayhem-screenshots-file'.
Signal an error after if something went wrong, as a page reading a
resource with no fixture: its shot shows the error."
  (mayhem-screenshots--setup)
  (let* ((names nil)
         (text
          (with-temp-buffer
            (insert-file-contents mayhem-screenshots-file)
            (goto-char (point-min))
            (while (re-search-forward mayhem-screenshots--marker nil t)
              (let* ((start (match-beginning 0))
                     (end (copy-marker (mayhem-screenshots--shot-end)))
                     (marker (match-string 1))
                     (spec (car (read-from-string (concat "(" marker ")"))))
                     (name (or (plist-get (cdr spec) :name) (symbol-name (caar spec))))
                     (shot (save-current-buffer
                             (mayhem-screenshots-shoot
                              (car spec) (plist-get (cdr spec) :press)
                              (expand-file-name (concat name ".png")
                                                mayhem-screenshots-directory)))))
                (when (member name names)
                  (push (format "Two shots are named %s; give one a :name" name)
                        mayhem-screenshots--problems))
                (push name names)
                (with-temp-file (expand-file-name (concat name ".txt")
                                                  mayhem-screenshots-directory)
                  (insert shot "\n"))
                (delete-region start end)
                (goto-char start)
                (insert (mayhem-screenshots--block marker name))))
            (buffer-string))))
    (with-temp-file mayhem-screenshots-file
      (insert text))
    ;; So a shot renamed or dropped leaves no file behind.
    (dolist (file (directory-files mayhem-screenshots-directory t "\\.\\(?:png\\|txt\\)\\'"))
      (unless (member (file-name-base file) names)
        (delete-file file)))
    (message "Wrote %s" mayhem-screenshots-file)
    (when mayhem-screenshots--problems
      (error "Mayhem screenshots:\n%s"
             (string-join (reverse mayhem-screenshots--problems) "\n")))))

(defun mayhem-screenshots-update-and-exit ()
  "Run `mayhem-screenshots-update' and exit Emacs, 1 if it failed."
  (kill-emacs (condition-case err
                  (progn (mayhem-screenshots-update) 0)
                (error (princ (format "%s\n" (error-message-string err))
                              #'external-debugging-output)
                       1))))

(provide 'screenshots)
;;; screenshots.el ends here
