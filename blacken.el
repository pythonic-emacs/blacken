;;; blacken.el --- Reformat python buffers using the "black" formatter

;; Copyright (C) 2018-2019 Artem Malyshev

;; Author: Artem Malyshev <proofit404@gmail.com>
;; Homepage: https://github.com/proofit404/blacken
;; Version: 0.0.1
;; Package-Requires: ((emacs "25.2"))

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

(require 'cl-lib)

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

(defcustom blacken-skip-string-normalization nil
  "Don't normalize string quotes or prefixes."
  :type 'boolean
  :safe 'booleanp)

(defcustom blacken-fast-unsafe nil
  "Skips temporary sanity checks."
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
           (number-to-string (cl-case blacken-line-length
                               ('fill fill-column)
                               (t blacken-line-length)))))
   (when blacken-allow-py36
     (list "--py36"))
   (when blacken-fast-unsafe
     (list "--fast"))
   (when blacken-skip-string-normalization
     (list "--skip-string-normalization"))
   '("-")))

;;;###autoload
(defun blacken-buffer (&optional display)
  "Try to blacken the current buffer.

Show black output, if black exit abnormally and DISPLAY is t."
  (interactive (list t))
  (let* ((original-buffer (current-buffer))
         (original-point (point))
         (original-window-pos (window-start))
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
            (goto-char original-point)
            (set-window-start (selected-window) original-window-pos))
          (mapc 'kill-buffer (list tmpbuf errbuf)))
      (error (message "%s" (error-message-string err))
             (when display
               (pop-to-buffer errbuf))))))

;;;###autoload
(define-minor-mode blacken-mode
  "Automatically run black before saving."
  :lighter " Black"
  (if blacken-mode
      (add-hook 'before-save-hook 'blacken-buffer nil t)
    (remove-hook 'before-save-hook 'blacken-buffer t)))

(provide 'blacken)

;;; blacken.el ends here
