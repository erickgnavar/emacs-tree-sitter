;;; tree-sitter-hl.el --- Syntax highlighting based on tree-sitter -*- lexical-binding: t; coding: utf-8 -*-

;; Copyright (C) 2020  Tuấn-Anh Nguyễn
;;
;; Author: Tuấn-Anh Nguyễn <ubolonton@gmail.com>
;;         Timo von Hartz <c0untlizzi@gmail.com>

;;; Commentary:

;; This file implements a new syntax highlighting based on `tree-sitter'.

;;; Code:

(require 'tree-sitter)

(eval-when-compile
  (require 'cl-lib))

;;; ----------------------------------------------------------------------------
;;; Faces for commonly used highlight names.

(defgroup tree-sitter-hl nil
  "Syntax highlighting using tree-sitter."
  :group 'tree-sitter)

(defgroup tree-sitter-hl-faces nil
  "All the faces of tree-sitter."
  :group 'tree-sitter-hl)

(defface tree-sitter-hl-face:attribute '((default :inherit font-lock-preprocessor-face))
  "Face used for attribute"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:comment '((default :inherit font-lock-comment-face))
  "Face used for comment"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:constant '((default :inherit font-lock-constant-face))
  "Face used for constant"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:constant.builtin '((default :inherit font-lock-builtin-face))
  "Face used for constant.builtin"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:constructor '((default :inherit font-lock-type-face))
  "Face used for constructor"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:escape '(())
  "Face used for escape"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:function '((default :inherit font-lock-function-name-face))
  "Face used for function"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:function.builtin '((default :inherit font-lock-builtin-face))
  "Face used for function.builtin"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:function.macro '((default :inherit font-lock-preprocessor-face))
  "Face used for function.macro"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:function.special '((default :inherit font-lock-preprocessor-face))
  "Face used for function.special"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:function.method '((default :inherit font-lock-function-name-face))
  "Face used for function.method"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:function.call '((default :inherit link :underline nil))
  "Face used for function.call"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:identifier '((default :inherit font-lock-function-name-face))
  "Face used for identifier"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:keyword '((default :inherit font-lock-keyword-face))
  "Face used for keyword"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:label '((default :inherit font-lock-preprocessor-face))
  "Face used for label"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:operator '((default :inherit font-lock-keyword-face))
  "Face used for operator"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:property '((default :inherit font-lock-variable-name-face))
  "Face used for property"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:punctuation '(())
  "Face used for punctuation"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:punctuation.bracket '(())
  "Face used for punctuation.bracket"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:punctuation.delimiter '(())
  "Face used for punctuation.delimiter"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:string '((default :inherit font-lock-string-face))
  "Face used for string"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:type '((default :inherit font-lock-type-face))
  "Faced used for type"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:type.builtin '((default :inherit font-lock-builtin-face))
  "Face used for type.builtin"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:variable '((default :inherit font-lock-variable-name-face))
  "Face used for variable"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:variable.builtin '((default :inherit font-lock-builtin-face))
  "Face used for variable.builtin"
  :group 'tree-sitter-hl-faces)

(defface tree-sitter-hl-face:variable.parameter '((default :inherit font-lock-variable-name-face))
  "Faced used for variable.parameter"
  :group 'tree-sitter-hl-faces)

;;; ----------------------------------------------------------------------------
;;; Interfaces for modes and end users.

(defvar-local tree-sitter-hl-default-patterns nil
  "Default syntax highlighting patterns.
This should be set by major modes that want to integrate with `tree-sitter-hl'.
It plays a similar role to `font-lock-defaults'.")

(defvar tree-sitter-hl--patterns-alist nil
  "Additional language-specific syntax highlighting patterns.
It plays a similar role to `font-lock-keywords-alist', except that its keys are
language symbols, not major mode symbols.")

(defvar-local tree-sitter-hl--extra-patterns-list nil
  "Additional buffer-local syntax highlighting patterns.")

(defvar-local tree-sitter-hl--query nil
  "Tree query used for syntax highlighting, compiled from patterns.")

(defun tree-sitter-hl--ensure-query ()
  "Return the tree query to be used for syntax highlighting in this buffer."
  (unless tree-sitter-hl--query
    (setq tree-sitter-hl--query
          (ts-make-query
           tree-sitter-language
           (mapconcat #'ts--stringify-patterns
                      (append tree-sitter-hl--extra-patterns-list
                              (list tree-sitter-hl-default-patterns))
                      "\n")
           ;; TODO: Allow this to be customized.
           (lambda (capture-name)
             ;; Use faces to tag captures. TODO: If a scope does not have a
             ;; corresponding face, check its ancestor scopes.
             (intern (format "tree-sitter-hl-face:%s" capture-name))))))
  tree-sitter-hl--query)

;;; TODO: Support adding/removing language-specific patterns.
(defun tree-sitter-hl-add-patterns (patterns)
  "Add buffer-local syntax highlighting PATTERNS.
These will take precedence over `tree-sitter-hl-default-patterns', as well as
previously added patterns."
  ;; Do nothing if the patterns are already on top.
  (unless (equal patterns (cl-first tree-sitter-hl--extra-patterns-list))
    (let ((old-list tree-sitter-hl--extra-patterns-list)
          (old-query tree-sitter-hl--query))
      ;; Update the patterns list and request the query to be rebuilt...
      (setq tree-sitter-hl--extra-patterns-list
            (append (list patterns) (remove patterns old-list)))
      (setq tree-sitter-hl--query nil)
      ;; ... and build it if possible. During a major mode's hook, we may not
      ;; even know the language, in which case we let `tree-sitter-hl--setup'
      ;; build the query later on.
      (when tree-sitter-language
        (tree-sitter--error-protect (tree-sitter-hl--ensure-query)
          ;; When the newly added patterns are invalid, restore the old state.
          (setq tree-sitter-hl--query old-query
                tree-sitter-hl--extra-patterns-list old-list))
        ;; Everything is in place. Request a re-render.
        (when (bound-and-true-p tree-sitter-hl-mode)
          (tree-sitter-hl--invalidate))))))

;;; ----------------------------------------------------------------------------
;;; Internal workings.

(defvar-local tree-sitter-hl--query-cursor nil)


(defconst tree-sitter-hl--extend-region-limit 2048
  "The max size of the extended region, in characters.")

(defconst tree-sitter-hl--extend-region-levels 4
  "The max number of levels to walk up the syntax tree to extend the region.")

(defun tree-sitter-hl--extend-region (beg end)
  "Return a \"safe\" region that encloses (BEG . END), to run the query on.
Because a match is returned only when all nodes in the pattern intersect the
query cursor's range, relying on `ts-changed-ranges' alone is insufficient.

Another pathological case is `jit-lock--run-funtions' being called on a very
small region. An example is when `evil-adjust-cursor' triggers a
`vertical-motion' (outside of a redisplay).

See https://github.com/tree-sitter/tree-sitter/issues/598."
  (pcase-let* ((region `(,beg . ,end))
               (root-node (ts-root-node tree-sitter-tree))
               (node (ts-get-descendant-for-position-range root-node beg end))
               (`(,beg . ,end) (ts-node-position-range node))
               (level 0))
    ;; Repeatedly extend the region, within the limit. TODO: What if the region
    ;; of the minimal enclosing node is already too large?
    (while (and node
                (< (- end beg) tree-sitter-hl--extend-region-limit))
      (setcar region beg)
      (setcdr region end)
      ;; Walk up to the parent node.
      (when (setq node (when (<= (cl-incf level)
                                 tree-sitter-hl--extend-region-levels)
                         (ts-get-parent node)))
        (let ((range (ts-node-position-range node)))
          (setf `(,beg . ,end) range))))
    ;; TODO: Extend to whole lines?
    region))

(defun tree-sitter-hl--append-text-property (start end prop value &optional object)
  "Append VALUE to PROP of the text from START to END.
This is similar to `font-lock-append-text-property', but deduplicates values. It
also expects VALUE to be a single value, not a list."
  (let (next prev)
    (while (/= start end)
      (setq next (next-single-property-change start prop object end)
            prev (get-text-property start prop object))
      ;; Canonicalize old forms of face property.
      (and (memq prop '(face font-lock-face))
           (listp prev)
           (or (keywordp (car prev))
               (memq (car prev) '(foreground-color background-color)))
           (setq prev (list prev)))
      (unless (listp prev)
        (setq prev (list prev)))
      (unless (memq value prev)
        (put-text-property start next prop
                           (append prev (list value))
                           object))
      (setq start next))))

(defun tree-sitter-hl--highlight-capture (capture)
  "Highlight the given CAPTURE."
  (pcase-let* ((`(,face . ,node) capture)
               (`(,beg . ,end) (ts-node-position-range node)))
    ;; (message " %s <- %s <- [%s %s]" face name beg end)
    ;; TODO: Consider giving certain combinations of highlight names their own
    ;; faces. For example, it might be desirable for fontification of a node
    ;; that matches both "constructor" and "variable" to be different from the
    ;; union of "constructor fontification" and "variable fontification".
    (when (facep face)
      (tree-sitter-hl--append-text-property beg end 'face face))))

;;; TODO: Handle embedded DSLs (injections).
(defun tree-sitter-hl--highlight-region (beg end &optional _loudly)
  "Highlight the region (BEG . END).
This is intended to be used as a buffer-local override of
`font-lock-fontify-region-function'."
  (ts--save-context
    ;; Extend the region to be highlighted, based on some heuristics, so that
    ;; querying works in certain pathological cases. This is analogous to the
    ;; extension done by `font-lock-default-fontify-region'. TODO: Consider
    ;; distinguishing region to query from region to fontify.
    (let ((region (tree-sitter-hl--extend-region beg end)))
      (setf `(,beg . ,end) region))
    (ts-set-byte-range tree-sitter-hl--query-cursor
                       (position-bytes beg)
                       (position-bytes end))
    (let* ((root-node (ts-root-node tree-sitter-tree))
           (matches  (ts-query-matches
                      tree-sitter-hl--query
                      root-node
                      tree-sitter-hl--query-cursor
                      #'ts--node-text)))
      ;; Prioritize captures from earlier patterns.
      (sort matches (lambda (m1 m2)
                      (< (car m1) (car m2))))
      ;; TODO: Handle quitting.
      (let ((inhibit-point-motion-hooks t))
        (with-silent-modifications
          (font-lock-unfontify-region beg end)
          ;; TODO: Handle uncaptured nodes.
          (seq-doseq (match matches)
            (pcase-let ((`(_ . ,captures) match))
              (seq-do #'tree-sitter-hl--highlight-capture captures)))))
      ;; TODO: Return the actual region being fontified.
      `(jit-lock-bounds ,beg . ,end))))

(defun tree-sitter-hl--invalidate (&optional old-tree)
  "Mark regions of text to be rehighlighted after a text change.
Installed on `tree-sitter-after-change-functions'.

OLD-TREE is the tree before the edit."
  (if old-tree
      ;; Incremental parse.
      (seq-doseq (range (ts-changed-ranges old-tree tree-sitter-tree))
        ;; TODO: How about invalidating a single large range?
        (pcase-let* ((`[,beg-byte ,end-byte] range)
                     (beg (byte-to-position beg-byte))
                     (end (byte-to-position end-byte)))
          ;; TODO: How about calling `jit-lock-refontify' directly?
          (font-lock-flush beg end)))
    ;; First parse.
    (font-lock-flush)))

;;; ----------------------------------------------------------------------------
;;; Setup and teardown.

;;; TODO: We want to work even without `font-lock-mode', right?
(defun tree-sitter-hl--setup ()
  "Set up `tree-sitter-hl' in the current buffer.
This assumes both `tree-sitter-mode' and `font-lock-mode' were already enabled."
  ;; TODO: If there's an error, disable `tree-sitter-hl--extra-patterns-list'
  ;; and retry.
  (tree-sitter-hl--ensure-query)
  (unless tree-sitter-hl--query-cursor
    (setq tree-sitter-hl--query-cursor (ts-make-query-cursor))
    ;; Invalidate the buffer only if we were actually disabled previously.
    (tree-sitter-hl--invalidate))
  ;; TODO: Override `font-lock-extend-after-change-region-function', or hook
  ;; into `jit-lock-after-change-extend-region-functions' directly. For that to
  ;; work, we need to make sure `tree-sitter--after-change' runs before
  ;; `jit-lock-after-change'.
  (add-hook 'tree-sitter-after-change-functions
            #'tree-sitter-hl--invalidate
            nil :local)
  ;; XXX
  (add-function :override (local 'font-lock-fontify-region-function)
                #'tree-sitter-hl--highlight-region))

(defun tree-sitter-hl--teardown ()
  "Tear down `tree-sitter-hl' in the current buffer."
  (remove-function (local 'font-lock-fontify-region-function)
                   #'tree-sitter-hl--highlight-region)
  (remove-hook 'tree-sitter-after-change-functions
               #'tree-sitter-hl--invalidate
               :local)
  (setq tree-sitter-hl--query nil)
  (when tree-sitter-hl--query-cursor
    (setq tree-sitter-hl--query-cursor nil)
    ;; Invalidate the buffer only if we were actually enabled previously.
    (font-lock-flush)))

;;;###autoload
(define-minor-mode tree-sitter-hl-mode
  "Toggle syntax highlighting based on Tree-sitter's syntax tree.
Enabling this automatically enables `tree-sitter-mode' in the buffer.

To enable this automatically whenever `tree-sitter-mode' is enabled:

 (add-hook 'tree-sitter-after-on-hook #'tree-sitter-hl-mode)"
  :init-value nil
  :group 'tree-sitter
  (tree-sitter--handle-dependent tree-sitter-hl-mode
    #'tree-sitter-hl--setup
    #'tree-sitter-hl--teardown))

(provide 'tree-sitter-hl)
;;; tree-sitter-hl.el ends here
