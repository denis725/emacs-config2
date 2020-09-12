;;;;;;;;;;;;;;;;;;;;;;;
;; ALWAYS ON STARTUP ;;
;;;;;;;;;;;;;;;;;;;;;;;

;; custom.el
(setq custom-file "~/.emacs.d/custom.el")
(load custom-file 'noerror)


;; PACKAGING

;; Libraries in ~/emacs.d/lib should take precedence over other
;; libraries with same name
;; http://www.emacswiki.org/emacs/LoadPath
(let ((default-directory "~/.emacs.d/lib/"))
  (setq load-path
        (append
         (let ((load-path (copy-sequence load-path))) ;; Shadow
           (append
            (copy-sequence (normal-top-level-add-to-load-path '(".")))
            (normal-top-level-add-subdirs-to-load-path)))
         load-path)))

;; packaging using melpa
(when (>= emacs-major-version 24)
  (require 'package)
  (add-to-list
   'package-archives
   '("melpa" . "http://melpa.org/packages/")
   t)
  (package-initialize))


(eval-when-compile
  (require 'use-package))

;; APPEARANCE

; don't show the startup screen
(setq inhibit-startup-screen 1)

; don't show the menu bar
(menu-bar-mode 1)

; don't show the tool bar
(require 'tool-bar)
(tool-bar-mode 0)

; don't show the scroll bar
(scroll-bar-mode 0)

; deactivate blinking cursor
(blink-cursor-mode 0)

;; start on full screen
(custom-set-variables
 '(initial-frame-alist (quote ((fullscreen . maximized)))))
(split-window-right)

;;deactivate sound
(setq visible-bell t)

;; show matching parenthesis etc.
(show-paren-mode 1)

;; SESSION
;; reload buffers when opening
(desktop-save-mode 1)
(if (file-exists-p "~/.emacs.d/desktop.el")
    (load "~/.emacs.d/desktop"))

;; ask when closing emacs
(global-unset-key "\C-x\C-c")
(global-set-key "\C-x\C-c" 'confirm-exit-emacs)
(defun confirm-exit-emacs ()
  "Ask for confirmation before exiting Emacs."
  (interactive)
  (if (yes-or-no-p "Are you sure you want to exit? ")
      (save-buffers-kill-emacs)))

;; y or n are used instead of yes or no
(fset 'yes-or-no-p 'y-or-n-p)

;; MOVEMENT

;; add move line https://www.emacswiki.org/emacs/MoveLine
(defun move-line (n)
  "Move the current line up or down by N lines."
  (interactive "p")
  (setq col (current-column))
  (beginning-of-line) (setq start (point))
  (end-of-line) (forward-char) (setq end (point))
  (let ((line-text (delete-and-extract-region start end)))
    (forward-line n)
    (insert line-text)
    ;; restore point to original column in moved line
    (forward-line -1)
    (forward-char col)))

(defun move-line-up (n)
  "Move the current line up by N lines."
  (interactive "p")
  (move-line (if (null n) -1 (- n))))

(defun move-line-down (n)
  "Move the current line down by N lines."
  (interactive "p")
  (move-line (if (null n) 1 n)))

(global-set-key (kbd "M-<up>") 'move-line-up)
(global-set-key (kbd "M-<down>") 'move-line-down)

;; EDITING

;; delete marked text when typing
(pending-delete-mode t)

;; trigger text completion, easier to call and repeat on German keyboard than "M-/"
(global-set-key (kbd "S-SPC") 'dabbrev-expand)

;; Set C-w to backward kill word if no text selected, more sane
;; behavior IMO
(defun my-kill-word-or-region-dwim ()
  "If region active kill it from START to END else backward kill word."
  ;; Don't use `(interactive "r") (start end)` since that doesn't work
  ;; when no mark is set (e.g. in a completely new buffer).
  (interactive)
  (let ((start (mark)) (end (point)))
  (if (use-region-p)
      (kill-region start end)
    (backward-kill-word 1))))
(global-set-key (kbd "C-w") 'my-kill-word-or-region-dwim)


(defun my-cut-or-delete-dwim (&optional arg)
  "If region active kill it from start to end else kill ARG words (default=1)."
  ;; Don't use `(interactive "r") (start end)` since that doesn't work
  ;; when no mark is set (e.g. in a completely new buffer). This
  ;; command is not attached to a keybinding but is used during the
  ;; move hydra to somewhat emulate vim's delete word.
  (interactive "p")
  (or arg (setq arg 1))
  (let ((start (mark)) (end (point)))
    (if (use-region-p)
        (kill-region start end)
      (kill-word arg))))

;; opposite of fill-paragraph
;; https://stackoverflow.com/a/6707838
(defun my-unfill-paragraph ()
  "Replace newline chars in current paragraph by single spaces.
This command does the reverse of `fill-paragraph'."
  (interactive)
  (let ((fill-column most-positive-fixnum))
    (fill-paragraph nil)))
(global-set-key (kbd "M-Q") 'my-unfill-paragraph)


;; smart shift lines

(defun smart-shift-up (&optional arg)
  "Shift current line or region to the ARG lines backwardly."
  ;; TODO: Think about what things can shift up for convenient.
  (interactive "P")
  (let ((deactivate-mark nil))
    (smart-shift-lines (* -1 (cond ((equal arg nil) 1)
                                   ((equal arg '(4)) 4)
                                   (t arg))))
    (smart-shift-override-local-map)))

(defun smart-shift-down (&optional arg)
  "Shift current line or region to the ARG lines forwardly."
  ;; TODO: Think about what things can shift down for convenient.
  (interactive "P")
  (let ((deactivate-mark nil))
    (smart-shift-lines (cond ((equal arg nil) 1)
                             ((equal arg '(4)) 4)
                             (t arg)))
    (smart-shift-override-local-map)))

(defun smart-shift-lines (step)
  "Move the current line or region to STEP lines forwardly.

Negative value of STEP means move backwardly.  Notice: It won't
modify `kill-ring'."
  (and (not (integerp step))
       (error "smart-shift-lines's argument STEP should be an integer! step = %s"
              step))
  ;; There're two situation:
  ;;
  ;; (point) ---------------
  ;; ---------------- (mark)
  ;;
  ;; or
  ;;
  ;; (mark) ----------------
  ;; --------------- (point)
  ;;
  ;; So here are the point-excursion and mark-excursion.
  (let* ((beg (if (use-region-p)
                  (save-excursion
                    (goto-char (region-beginning))
                    (line-beginning-position 1))
                (line-beginning-position 1)))
         (end (if (use-region-p)
                  (save-excursion
                    (goto-char (region-end))
                    (line-beginning-position 2))
                (line-beginning-position 2)))
         (point-excursion (- (point) end))
         (mark-excursion (- (mark) (point)))
         (text (delete-and-extract-region beg end)))
    ;; Shift text.
    (forward-line step)
    (insert text)
    ;; Set new point.
    (goto-char (+ (point) point-excursion))
    ;; Set new mark.
    (when (use-region-p)
      (push-mark (+ (point) mark-excursion) t t))))


(defun smart-shift-override-local-map ()
  "Override local key map for continuous indentation."
  (setq overriding-local-map
        (let ((map (copy-keymap smart-shift-mode-map)))
          (define-key map (kbd "<left>") 'smart-shift-left)
          (define-key map (kbd "<right>") 'smart-shift-right)
          (define-key map (kbd "<up>") 'smart-shift-up)
          (define-key map (kbd "<down>") 'smart-shift-down)
          (define-key map [t] 'smart-shift-pass-through) ;done with shifting
          map))
  (message (propertize "Still in smart-shift key chord..."
                       'face 'error)))

(global-set-key (kbd "M-<up>") 'smart-shift-up)
(global-set-key (kbd "M-<down>") 'smart-shift-down)

;; custom command to comment and copy a region
(defun my-comment-and-copy ()
  "Comment the selected region and copy it below."
  (interactive)
  (kill-ring-save (region-beginning) (region-end))
  (exchange-point-and-mark)
  (comment-region (region-beginning) (region-end))
  (goto-char (region-end))
  (open-line 1)
  (yank)
  )
(global-set-key (kbd "C-c #") 'my-comment-and-copy)


;; BUFFERS & WINDOWS
;; Switch to previous buffer
(global-set-key (kbd "C-q") 'mode-line-other-buffer)

;; move to other window, more ergonomic than "C-x o"
(global-set-key (kbd "C-o") 'other-window)


;; APPEARANCE

;; add themes folder
(add-to-list 'custom-theme-load-path "~/.emacs.d/themes/")

;; load-theme first unloads other custom themes (otherwise there can be errors)
;; https://stackoverflow.com/a/18796138
;; (defadvice load-theme (before theme-dont-propagate activate)
;;   "Tell `load-theme` to first unload other custom themes."
;;   (mapcar #'disable-theme custom-enabled-themes))


;;http://ergoemacs.org/emacs/whitespace-mode.html
(progn
 ;; Make whitespace-mode with very basic background coloring for whitespaces.
  (setq whitespace-style (quote (face spaces tabs newline space-mark tab-mark newline-mark )))

  ;; Make whitespace-mode and whitespace-newline-mode use “¶” for end
  ;; of line char and “▷” for tab.
  (setq whitespace-display-mappings
        ;; all numbers are unicode codepoint in decimal. e.g. (insert-char 182 1)
        '(
          (space-mark 32 [183] [46]) ; SPACE 32 「 」, 183 MIDDLE DOT 「·」, 46 FULL STOP 「.」
          (newline-mark 10 [182 10]) ; LINE FEED,
          (tab-mark 9 [9655 9] [92 9]) ; tab
          )))

;; OS

;; in OS X, inject PATH etc., see here: http://www.flycheck.org/en/latest/user/troubleshooting.html
;; https://github.com/purcell/exec-path-from-shell
;; (when (memq window-system '(mac ns x))
;;   (exec-path-from-shell-initialize))

;; System locale to use for formatting time values.
(setq system-time-locale "C")         ; Make sure that the weekdays in the
                                      ; time stamps of your Org mode files and
                                      ; in the agenda appear in English.


;; SHELL
(defun my-switch-shell-run-last-cmd ()
  "Switch to shell buffer and run last cmd."
  (interactive)
  (let ((bname (buffer-name)))
    (if (not (string= bname "*shell*"))
        (other-window 1))
    (switch-to-buffer "*shell*")
    (goto-char (point-max))
    (comint-previous-input 1)
    (comint-send-input)
    (if (not (string= bname "*shell*"))
        (other-window 1))))
(global-set-key (kbd "C-S-o") 'my-switch-shell-run-last-cmd)


;;;;;;;;;;;;;;
;; PACKAGES ;;
;;;;;;;;;;;;;;

;; magit
(use-package magit
  :ensure t
  ;; Magit https://magit.vc/manual/magit/Getting-started.html#Getting-started
  :config (global-magit-file-mode 1)
  :init (setenv "GIT_PAGER" "cat")
  :bind ("C-x g" . 'magit-status))


;; tramp
(use-package tramp
  :init
  (setq tramp-auto-save-directory "~/.emacs.d/tramp-autosave"))

(use-package docker-tramp
  :ensure t)


;; PYTHON

;; anaconda mode
(use-package anaconda-mode
  :ensure t

  :init
  (add-hook 'python-mode-hook 'anaconda-mode)
  (add-hook 'python-mode-hook 'anaconda-eldoc-mode)

  :bind
  (
   ("C-x p" . my-runpytest)
   ("M-<left>" . python-indent-shift-left)
   ("M-<right>" . python-indent-shift-right)
   ("M-p" . python-add-breakpoint))

  :config
  ;; special movement for programming modes
  (defun my-backw-paragraph-or-fun-start ()
    "Beginning of paragraph or def if Python mode."
    (interactive)
    (if (equal major-mode 'python-mode)
	(python-nav-backward-defun)
      (backward-paragraph)))

  (defun my-forw-paragraph-or-fun-end ()
    "End of paragraph or def if Python mode."
    (interactive)
    (if (equal major-mode 'python-mode)
	(python-nav-forward-defun)
      (forward-paragraph)))

  (defun python-add-breakpoint ()
    "Add a Python breakpoint."
    (interactive)
    (newline-and-indent)
    (insert "import pdb; pdb.set_trace()")
    (highlight-lines-matching-regexp "^[ ]*import pdb; pdb.set_trace()"))

  ;; macro for running pytest
  (fset 'my-runpytest
	(lambda (&optional arg) "Keyboard macro." (interactive "p") (kmacro-exec-ring-item (quote ([24 111 24 98 115 104 101 return 18 112 121 46 116 101 115 116 32 return return] 0 "%d")) arg)))
  (global-set-key (kbd "C-x p") 'my-runpytest)

  ;; Use IPython for REPL
  ;; https://realpython.com/emacs-the-best-python-editor/#integration-with-jupyter-and-ipython
  (setq python-shell-interpreter "jupyter"
	python-shell-interpreter-args "console --simple-prompt"
	python-shell-prompt-detect-failure-warning nil)
  (add-to-list 'python-shell-completion-native-disabled-interpreters
	       "jupyter")
  )

(use-package pyvenv
  :ensure t
  :config (setenv "WORKON_HOME" "~/anaconda3/envs"))

(use-package python-pytest
  :ensure t
  :bind ("C-c p" . python-pytest-popup))

;; FLYCHECK
(use-package flycheck
  :ensure t
  :init
  (global-flycheck-mode)
  (add-hook 'python-mode-hook 'flycheck-mode)
  :config
  ;; https://github.com/flycheck/flycheck/issues/1437
  (setq flycheck-python-pylint-executable "pylint")
  (setq flycheck-pylintrc "pylintrc"))


;; CRUX

(use-package crux
  :demand
  :ensure t

  :bind
  ("C-a" . crux-move-beginning-of-line)
  ("C-k" . 'crux-smart-kill-line))


;; YASNIPPET
(use-package yasnippet
  :ensure t

  :init
  (add-hook 'python-mode-hook '(lambda () (set (make-local-variable 'yas-indent-line) 'fixed)))

  :config
  (setq yas-snippet-dirs '("~/emacs.d/snippets"))
  (yas-global-mode 1)
  (setq yas-indent-line 'fixed))

(use-package yasnippet-snippets
  :ensure t)


;; SEARCH
;; Ivy, Swiper, Council
(use-package swiper
  :demand
  :ensure t)
(use-package counsel
  :demand
  :ensure t)
(use-package avy
  :demand
  :ensure t
  :bind ("M-s" . 'avy-goto-char))
(use-package ivy-rich
  :demand
  :ensure t
  :config (ivy-rich-mode 1))
(use-package wgrep
  :demand
  :ensure t)

(use-package ivy
  :demand
  :ensure t

  :config
  (ivy-mode 1)
  (setq ivy-use-virtual-buffers t)
  (setq enable-recursive-minibuffers t)
  (setq ivy-use-selectable-prompt t)

  :init
  ;; E.g., if you have ivy candidates, press C-c C-o (ivy-occur) to
  ;; bring them to their own buffer, then C-x C-q (or just "e")
  ;; (ivy-wgrep-change-to-wgrep-mode) to make the buffer editable, then
  ;; C-c C-c to apply the changes. This can be used, for instance, to
  ;; rename a variable in a whole folder with counsel-get-grep.
  (add-hook 'ivy-occur-grep-mode-hook
	    (lambda () (local-set-key (kbd "e") #'ivy-wgrep-change-to-wgrep-mode)))

  :bind
  ("M-x" . counsel-M-x)
  ("C-s" . swiper)
  ("C-x C-f" . counsel-find-file)
  ("C-c r" . counsel-rg)
  ("C-c C-o" . occur)  ;; ivy-occur seems to be broken https://github.com/abo-abo/swiper/issues/2571
  )


;; HYDRA
(use-package hydra
  :ensure t

  :config
  ;; increase font size, good for presentations
  ;; press C-c C-+ to increase once, then + or - repeatedly
  (defhydra hydra-zoom (global-map "C-�")
    "Increase or decrease text scale"
    ("g" text-scale-increase "in")
    ("+" text-scale-increase "in")
    ("l" text-scale-decrease "out")
    ("-" text-scale-decrease "out")
    ("r" (text-scale-set 0) "reset")
    ("q" nil "quit")
    ("0" (text-scale-set 0) :bind nil :exit t))

  ;; movement
  (defhydra hydra-move (global-map "C-c C-h")
    "move like in modal editor"
    ("p" previous-line "line u")
    ("n" next-line "line d")
    ("k" previous-line)  ;; as in vim
    ("j" next-line)  ;; as in vim
    ("," backward-paragraph "§ u")
    ("." forward-paragraph "§ d")
    (";" my-backw-paragraph-or-fun-start "§ u")
    (":" my-forw-paragraph-or-fun-end "§ d")
    ("f" forward-char "char fw")
    ("b" backward-char "char bw")
    ("w" forward-word "word fw")  ;; as in vim
    ("F" forward-word "word fw")
    ("W" backward-word "word bw")
    ("B" backward-word "word bw")
    ("a" crux-move-beginning-of-line "line bg")
    ("e" end-of-line "line end")
    ("v" scroll-up-command "page up")
    ("V" scroll-down-command "page dw")
    ("<" beginning-of-buffer "file bg")
    (">" end-of-buffer "file end")
    ("m" set-mark-command)
    ("c" kill-ring-save "cp")
    ("d" my-cut-or-delete-dwim "cut")
    ("D" backward-kill-word "bk kill word")
    ("x" kill-region)
    ("y" yank "yank")
    ("u" undo "undo")
    ("h" mark-whole-buffer "mk all")
    ("r" rectangle-mark-mode "rect")
    ("+" er/expand-region)
    ("-" (lambda () (interactive) (er/expand-region -1)))
    ("#" comment-dwim "comment")
    ("<up>" move-line-up "line up")
    ("<down>" move-line-down "line down")
    ("o" other-window "other window")
    ("q" nil "quit")
    ("i" nil "quit"))

  ;; The most common move commands now activate hydra-move; e.g., when
  ;; pressing C-n to move to the next line, hydra-move is activated, so
  ;; that just pressing n will move one line further. That means that
  ;; for instance pressing C-n n n moves 3 lines forward, C-p b moves
  ;; back one line and one character, etc. The reasoning behind this is
  ;; that often I don't bother to activate the move hydra (C-ö) because
  ;; the first command doesn't do anything, making it less
  ;; economical. However, I often want to move more than, say, one word
  ;; forward, so I would like to activate the move hydra nonetheless.

  (defun my-next-line-hydra ()
    "Move next line and activate move hydra."
    (interactive)
    (hydra-move/next-line))
  ;; (define-key minibuffer-local-map "C-n" [next-line])
  ;; de-activate in ivy-minibuffer
  (define-key ivy-minibuffer-map (kbd "C-n") #'ivy-next-line)

  (defun my-prev-line-hydra ()
    "Move prev line and activate move hydra."
    (interactive)
    (hydra-move/previous-line))
  ;; de-activate in ivy-minibuffer
  (define-key ivy-minibuffer-map (kbd "C-p") #'ivy-previous-line)

  (defun my-forward-char-hydra ()
    "Move forward char and activate move hydra."
    (interactive)
    (hydra-move/forward-char))

  (defun my-backward-char-hydra ()
    "Move backward char and activate move hydra."
    (interactive)
    (hydra-move/backward-char))

  (defun my-forward-word-hydra ()
    "Move forward word and activate move hydra."
    (interactive)
    (hydra-move/forward-word))

  (defun my-backward-word-hydra ()
    "Move backward word  and activate move hydra."
    (interactive)
    (hydra-move/backward-word))

  (defun my-forward-paragraph-hydra ()
    "Move forward paragraph and activate move hydra."
    (interactive)
    (hydra-move/forward-paragraph))

  (defun my-backward-paragraph-hydra ()
    "Move backward paragraph and activate move hydra."
    (interactive)
    (hydra-move/backward-paragraph))

  ;; flycheck
  ;; hydra for flycheck, see https://github.com/abo-abo/hydra/wiki/Flycheck
  (defhydra hydra-flycheck
    (:pre (flycheck-list-errors)
	  :post (quit-windows-on "*Flycheck errors*")
	  :hint nil)
    "Errors"
    ("f" flycheck-error-list-set-filter "Filter")
    ("j" flycheck-next-error "next")
    ("n" flycheck-next-error "next")
    ("k" flycheck-previous-error "prev")
    ("p" flycheck-previous-error "prev")
    ("g" flycheck-first-error "First")
    ("G" (progn (goto-char (point-max)) (flycheck-previous-error)) "Last")
    ("q" nil))

  :bind
  ; zoom
  ("C-c C-+" . hydra-zoom/text-scale-increase)
  ("C-c C--" . hydra-zoom/text-scale-decrease)

  ; movement
  ("C-," . my-backward-paragraph-hydra)
  ("C-;" . hydra-move/my-backw-paragraph-or-fun-start)
  ("C-n" . my-next-line-hydra)
  ("C-p" . my-prev-line-hydra)
  ("C-f" . my-forward-char-hydra)
  ("C-b" . my-backward-char-hydra)
  ("M-f" . my-forward-word-hydra)
  ("M-b" . my-backward-word-hydra)
  ("C-." . my-forward-paragraph-hydra)
  ("C-:" . hydra-move/my-forw-paragraph-or-fun-end)

  ;; flycheck
  ("C-c ! !" . hydra-flycheck/flycheck-next-error)
  )


;; ORG MODE
(use-package org
  :init
  (setq org-agenda-files (list "~/Dropbox/Wohnung/Umzug/Aufgaben.org"
			       "~/work/orga"))
  (setq org-default-notes-file "~/work/orga/notes.org")

  ;; org mode TODO states
  (setq org-todo-keywords
	'((sequence "TODO" "DOING" "WAITING" "DONE")))

  ;; agenda view 1 month
  (setq org-agenda-span 'month)

  ;; http://orgmode.org/worg/org-tutorials/orgtutorial_dto.php
  (setq org-log-done t)
  (setq org-startup-indented t)
  (setq org-refile-targets '((nil :maxlevel . 3)
			     (org-agenda-files :maxlevel . 1)))

  ;; when using org-refile, show the file name as well, allows to refile
  ;; to the top level of that file
  ;; https://blog.aaronbieber.com/2017/03/19/organizing-notes-with-refile.html
  (setq org-refile-use-outline-path 'file)
  (setq org-outline-path-complete-in-steps nil)

  (add-hook 'org-mode-hook #'visual-line-mode)

  (org-babel-do-load-languages
   'org-babel-load-languages
   '(
     (python . t)
     (shell . t)))

  :bind
  ("C-c l" . org-store-link)
  ("C-c a" . org-agenda)
  ("C-c c" . org-capture)
  ("C-c b" . org-iswitchb))

(use-package org-re-reveal
  :ensure t)

;; from https://protesilaos.com/dotemacs/
(use-package org-superstar
  :ensure
  :init
  (add-hook 'org-mode-hook (lambda () (org-superstar-mode 1)))
  :config
  (setq org-superstar-remove-leading-stars t)
  (setq org-superstar-headline-bullets-list '("◉" ("○" ?◈) "◆" "◇" "▶" "▷")))


;; ORG ROAM
;; https://github.com/org-roam/org-roam
;; https://www.orgroam.com/
;; https://blog.jethro.dev/posts/introducing_org_roam/

;; org-roam-graph by default expects to find the dot executable from
;; the graphviz package in the exec-path. Ensure graphviz is installed
;; and found if you want to use this feature or customize your
;; configuration for org-roam-graph to use a different tool.
(use-package org-roam
  :ensure t
  :hook
  (after-init . org-roam-mode)
  :custom
  (org-roam-directory "~/work/orga")
  :bind
  (:map org-roam-mode-map
        (("C-c n l" . org-roam)
         ("C-c n f" . org-roam-find-file)
         ("C-c n g" . org-roam-graph-show))
        :map org-mode-map
        (("C-c n i" . org-roam-insert))
        (("C-c n I" . org-roam-insert-immediate))))

;; APPEARANCE
(use-package zenburn-theme
  :demand
  :ensure t)

(use-package powerline
  :demand
  :ensure t
  :config (powerline-default-theme))

(use-package beacon
  :demand
  :ensure t
  :config (beacon-mode 1))

;; MARKUP LANGUAGES

;; rst mode

(use-package rst
  :init
  (defun my-rst-insert-external-link ()
    "Insert a link in rst mode."
    (interactive)
    (let* ((url (read-string "Enter URL: "))
	   (desc (read-string "Enter description: ")))
      (insert (format "`%s <%s>`_" desc url))))
  :bind
  ;; add command C-c i to insert external link, C-c C-l is taken
  ;; already
  ("C-c i" . my-rst-insert-external-link)
  )

;; markdown mode
(use-package markdown-mode
  :ensure t
  :commands (markdown-mode gfm-mode)
  :mode (("README\\.md\\'" . gfm-mode)
         ("\\.md\\'" . markdown-mode)
         ("\\.markdown\\'" . markdown-mode))
  :init (setq markdown-command "multimarkdown"))

(use-package markdown-toc
  :ensure t)
