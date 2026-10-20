;;; mayhem-vui-tests.el --- Tests for mayhem-vui.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for what a page part shows for a sync snapshot.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'mayhem-vui)

(ert-deftest mayhem-vui-test-snapshot-view-skeleton-until-data ()
  (should (eq (mayhem-snapshot-view '(:loading t) "x" 'skeleton #'ignore) 'skeleton))
  (should (eq (mayhem-snapshot-view nil "x" 'skeleton #'ignore) 'skeleton))
  ;; A retry of a failed first fetch shows the skeleton again.
  (should (eq (mayhem-snapshot-view '(:error "e" :loading t) "x" 'skeleton #'ignore)
              'skeleton)))

(ert-deftest mayhem-vui-test-snapshot-view-error-without-data ()
  (should-not (memq (mayhem-snapshot-view '(:error "HTTP 500: e") "x" 'skeleton #'ignore)
                    '(skeleton nil))))

(ert-deftest mayhem-vui-test-snapshot-view-renders-data ()
  (should (equal (mayhem-snapshot-view '(:fetched-at 1.0 :data (1) :error "e")
                                       "x" 'skeleton #'identity)
                 '(1))))

(ert-deftest mayhem-vui-test-skeleton-bar ()
  (let ((bar (mayhem-skeleton-bar 3)))
    (should (equal bar "   "))
    (should (eq (get-text-property 0 'face bar) 'mayhem-skeleton))))

(defun mayhem-vui-tests--parts (vnode)
  "Return VNODE's text as a list: a link's as (LINK TEXT), else a string."
  (cond ((vui-vnode-fragment-p vnode)
         (mapcan #'mayhem-vui-tests--parts (vui-vnode-fragment-children vnode)))
        ((vui-vnode-button-p vnode) (list (list 'link (vui-vnode-button-label vnode))))
        ((vui-vnode-text-p vnode) (list (vui-vnode-text-content vnode)))))

(ert-deftest mayhem-vui-test-page-heading-links-enclosing-pages ()
  (cl-letf (((symbol-function 'mayhem--host) (lambda () "h.example")))
    (should (equal (mayhem-vui-tests--parts (mayhem-page-heading "dashboard" nil nil nil))
                   '("h.example" " dashboard" "\n")))
    (should (equal (mayhem-vui-tests--parts (mayhem-page-heading "target" "o" "p" "t"))
                   '((link "h.example") "/" (link "o") "/" (link "p") "/" "t" " target"
                     "\n")))
    (should (equal (mayhem-vui-tests--parts (mayhem-page-heading "run" "o" "p" "t" "#3"))
                   '((link "h.example") "/" (link "o") "/" (link "p") "/" (link "t") "/" "#3"
                     " run" "\n")))
    (should (equal (mayhem-vui-tests--parts
                    (mayhem-page-heading "target" "o" "p" "stretch-20171101-6-75k-unknown-adv-3"))
                   '((link "h.example") "/" (link "o") "/" (link "p") "/"
                     "stretch-2017…known-adv-3" " target" "\n")))))

(defun mayhem-vui-tests--line (max-width parts)
  "Return the text of the `mayhem-line' of PARTS, on a page MAX-WIDTH wide."
  (let ((mayhem-max-width max-width))
    (with-temp-buffer
      (vui-render (mayhem-line parts))
      (buffer-substring-no-properties (point-min) (point-max)))))

(ert-deftest mayhem-vui-test-line-fits-page ()
  ;; Padded to the column's width when the page has room...
  (should (equal (mayhem-vui-tests--line 40 (list "ab " (mayhem-fit "t" 4) " #1"))
                 "ab t    #1\n"))
  ;; ...and cut when it has not.
  (should (equal (mayhem-vui-tests--line 20 (list "ab " (mayhem-fit "title long name" 30) " #1"))
                 "ab title long na… #1\n")))

(ert-deftest mayhem-vui-test-cut-middle ()
  (should (equal (mayhem-cut-middle "short" 10) "short"))
  (should (equal (mayhem-cut-middle "stretch-20171101-adv-3" 11) "stret…adv-3"))
  (should (= (string-width (mayhem-cut-middle "stretch-20171101-adv-3" 11)) 11)))

(ert-deftest mayhem-vui-test-rows-highlight-apart ()
  ;; Hovering one row must not light up its neighbours too.
  (with-temp-buffer
    (vui-render (vui-fragment (mayhem-row "one\n" #'ignore "RET: x")
                              (mayhem-row (list "two") #'ignore "RET: x")))
    (should (eq (get-text-property 1 'mouse-face) 'highlight))
    (should-not (get-text-property 4 'mouse-face))
    (should (eq (get-text-property 5 'mouse-face) 'highlight))
    (should-not (get-text-property 8 'mouse-face))))

(provide 'mayhem-vui-tests)
;;; mayhem-vui-tests.el ends here
