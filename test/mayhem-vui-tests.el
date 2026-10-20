;;; mayhem-vui-tests.el --- Tests for mayhem-vui.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for what a page part shows for a sync snapshot.

;;; Code:

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
  (should (equal (mayhem-vui-tests--parts (mayhem-page-heading nil nil nil))
                 '("Mayhem" "\n")))
  (should (equal (mayhem-vui-tests--parts (mayhem-page-heading "o" "p" "t"))
                 '((link "Mayhem") "/" (link "o") "/" (link "p") "/" "t" "\n")))
  (should (equal (mayhem-vui-tests--parts (mayhem-page-heading "o" "p" "t" " #3"))
                 '((link "Mayhem") "/" (link "o") "/" (link "p") "/" (link "t") " #3" "\n"))))

(provide 'mayhem-vui-tests)
;;; mayhem-vui-tests.el ends here
