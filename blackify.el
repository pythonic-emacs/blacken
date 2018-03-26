;;; blackify.el --- (automatically) format python buffers using black.

;; Copyright (C) 2018 Artem Malyshev

;; Author: Artem Malyshev <proofit404@gmail.com>
;; Homepage: https://github.com/proofit404/blackify
;; Version: 0.0.1
;; Package-Requires: ()

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
;; Blackify uses black to format a Python buffer.  It can be called
;; explicitly on a certain buffer, but more conveniently, a minor-mode
;; 'black-mode' is provided that turns on automatically running black
;; on a buffer before saving.
;;
;; Installation:
;;
;; Add blackify.el to your load-path.
;;
;; To automatically format all Python buffers before saving, add the function
;; black-mode to python-mode-hook:
;;
;; (add-hook 'python-mode-hook 'black-mode)
;;
;;; Code:

(defvar blackify-line-length nil)

(defun blackify-call-bin (input-buffer output-buffer)
  "Call process black on INPUT-BUFFER saving the output to OUTPUT-BUFFER.

Return black process the exit code."
  (with-current-buffer input-buffer
    (let (args)
      (when blackify-line-length
        (push "--multi-line" args)
        (push (number-to-string blackify-line-length) args))
      (push "-" args)
      (apply 'call-process-region (point-min) (point-max) "black" nil output-buffer nil (reverse args)))))

;;;###autoload
(defun blackify-buffer (&optional display)
  "Try to blackify the current buffer.

Show black output, if black exit abnormally and DISPLAY is t."
  (interactive (list t))
  (let* ((original-buffer (current-buffer))
         (original-point (point))
         (original-window-pos (window-start))
         (tmpbuf (get-buffer-create "*blackify*")))
    ;; This buffer can be left after previous black invocation.  It
    ;; can contain error message of the previous run.
    (with-current-buffer tmpbuf
      (erase-buffer))
    (condition-case err
        (if (not (zerop (blackify-call-bin original-buffer tmpbuf)))
            (error "Black failed, see %s buffer for details" (buffer-name tmpbuf))
          (with-current-buffer tmpbuf
            (copy-to-buffer original-buffer (point-min) (point-max)))
          (kill-buffer tmpbuf)
          (goto-char original-point)
          (set-window-start (selected-window) original-window-pos))
      (error (message "%s" (error-message-string err))
             (when display
               (pop-to-buffer tmpbuf))))))

;;;###autoload
(define-minor-mode black-mode
  "Automatically run black before saving."
  :lighter " Black"
  (if black-mode
      (add-hook 'before-save-hook 'blackify-buffer nil t)
    (remove-hook 'before-save-hook 'blackify-buffer t)))

(provide 'blackify)

;;; blackify.el ends here
