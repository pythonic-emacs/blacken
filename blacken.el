;;; blacken.el --- Reformat python buffers using the "black" formatter

;; Copyright (C) 2018-2019 Artem Malyshev

;; Author: Artem Malyshev <proofit404@gmail.com>
;; Homepage: https://github.com/proofit404/blacken
;; Version: 0.2.0
;; Package-Requires: ((emacs "25.2"))
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Keywords: convenience blacken

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation; either version 3, or (at your
;; option) any later version.
;;
;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Blacken uses black to format a Python buffer.  It can be called
;; explicitly on a certain buffer, but more conveniently, a minor-mode
;; 'blacken-mode' is provided that turns on automatically running
;; black on a buffer before saving.
;;
;; Installation:
;;
;; Add blacken.el to your load-path.
;;
;; To automatically format all Python buffers before saving, add the
;; function blacken-mode to python-mode-hook:
;;
;; (add-hook 'python-mode-hook 'blacken-mode)
;;
;;; Code:

(defgroup blacken nil
  "Reformat Python code with \"black\"."
  :group 'python)

(defcustom blacken-executable "black"
  "Name of the executable to run."
  :type 'string)

(defcustom blacken-line-length nil
  "Line length to enforce.

It must be an integer, nil or `fill'.
If `fill', the `fill-column' variable value is used."
  :type '(choice :tag "Line Length Limit"
           (const :tag "Use default" nil)
           (const :tag "Use fill-column" fill)
           (integer :tag "Line Length"))
  :safe 'integerp)

(defcustom blacken-allow-py36 nil
  "Allow using Python 3.6-only syntax on all input files."
  :type 'boolean
  :safe 'booleanp)
(make-obsolete-variable 'blacken-allow-py36 'blacken-target-version "0.2.0")

(defcustom blacken-target-version nil
  "Set the target python version."
  :type 'string)

(defcustom blacken-skip-string-normalization nil
  "Don't normalize string quotes or prefixes."
  :type 'boolean
  :safe 'booleanp)

(defcustom blacken-fast-unsafe nil
  "Skips temporary sanity checks."
  :type 'boolean
  :safe 'booleanp)

(defcustom blacken-only-if-project-is-blackened nil
  "Only blacken if project has a pyproject.toml with a [tool.black] section."
  :type 'boolean
  :safe 'booleanp)

(defun blacken-call-bin (input-buffer output-buffer error-buffer)
  "Call process black.

Send INPUT-BUFFER content to the process stdin.  Saving the
output to OUTPUT-BUFFER.  Saving process stderr to ERROR-BUFFER.
Return black process the exit code."
  (with-current-buffer input-buffer
    (let ((process (make-process :name "blacken"
                                 :command `(,blacken-executable ,@(blacken-call-args))
                                 :buffer output-buffer
                                 :stderr error-buffer
                                 :connection-type 'pipe
                                 :noquery t
                                 :sentinel (lambda (process event)))))
      (set-process-query-on-exit-flag (get-buffer-process error-buffer) nil)
      (set-process-sentinel (get-buffer-process error-buffer) (lambda (process event)))
      (save-restriction
        (widen)
        (process-send-region process (point-min) (point-max)))
      (process-send-eof process)
      (accept-process-output process nil nil t)
      (while (process-live-p process)
        (accept-process-output process nil nil t))
      (process-exit-status process))))

(defun blacken-call-args ()
  "Build black process call arguments."
  (append
   (when blacken-line-length
     (list "--line-length"
           (number-to-string (if (eq blacken-line-length 'fill)
                                 fill-column
                               blacken-line-length))))
   (if blacken-allow-py36
       (list "--target-version" "py36")
     (when blacken-target-version
       (list "--target-version" blacken-target-version)))
   (when blacken-fast-unsafe
     (list "--fast"))
   (when blacken-skip-string-normalization
     (list "--skip-string-normalization"))
   (when (and (buffer-file-name (current-buffer))
              (string-match "\\.pyi\\'" (buffer-file-name (current-buffer))))
     (list "--pyi"))
   '("-")))

(defun blacken-project-is-blackened (&optional display)
  "Whether the project has a pyproject.toml with [tool.black] in it."
  (when-let (parent (locate-dominating-file default-directory "pyproject.toml"))
    (with-temp-buffer
      (insert-file-contents (concat parent "pyproject.toml"))
      (re-search-forward "^\\[tool.black\\]$" nil t 1))))

;;;###autoload
(defun blacken-buffer (&optional display)
  "Try to blacken the current buffer.

Show black output, if black exit abnormally and DISPLAY is t."
  (interactive (list t))
  (let* ((original-buffer (current-buffer))
         (original-window-states (mapcar
                                  (lambda (w)
                                    (list w (window-point w) (window-start w)))
                                  (get-buffer-window-list)))
         (tmpbuf (get-buffer-create "*blacken*"))
         (errbuf (get-buffer-create "*blacken-error*")))
    ;; This buffer can be left after previous black invocation.  It
    ;; can contain error message of the previous run.
    (dolist (buf (list tmpbuf errbuf))
      (with-current-buffer buf
        (erase-buffer)))
    (condition-case err
        (if (not (zerop (blacken-call-bin original-buffer tmpbuf errbuf)))
            (error "Black failed, see %s buffer for details" (buffer-name errbuf))
          (unless (eq (compare-buffer-substrings tmpbuf nil nil original-buffer nil nil) 0)
            (with-current-buffer tmpbuf
              (copy-to-buffer original-buffer (point-min) (point-max)))
            (dolist (win-stt original-window-states)
              (set-window-point (car win-stt) (nth 1 win-stt))
              (set-window-start (car win-stt) (nth 2 win-stt))))
          (mapc 'kill-buffer (list tmpbuf errbuf)))
      (error (message "%s" (error-message-string err))
             (when display
               (with-current-buffer errbuf
                 (setq-local scroll-conservatively 0))
               (pop-to-buffer errbuf))))))

;;;###autoload
(define-minor-mode blacken-mode
  "Automatically run black before saving."
  :lighter " Black"
  (if blacken-mode
      (when (or (not blacken-only-if-project-is-blackened)
                (blacken-project-is-blackened))
        (add-hook 'before-save-hook 'blacken-buffer nil t))
    (remove-hook 'before-save-hook 'blacken-buffer t)))

(provide 'blacken)

;;; blacken.el ends here
