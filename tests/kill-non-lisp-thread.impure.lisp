;;;; Testing signal handling in non-lisp threads.

;;;; This software is part of the SBCL system. See the README file for
;;;; more information.
;;;;
;;;; While most of SBCL is derived from the CMU CL system, the test
;;;; files (like this one) were written from scratch after the fork
;;;; from CMU CL.
;;;;
;;;; This software is in the public domain and is provided with
;;;; absolutely no warranty. See the COPYING and CREDITS files for
;;;; more information.

#-sb-thread
(sb-ext:quit :unix-status 104)

(use-package :sb-alien)

(defun run (program &rest arguments)
  (let* ((proc nil)
         (output
          (with-output-to-string (s)
            (setf proc (run-program program arguments
                                    :search (not (eql #\. (char program 0)))
                                    :output s)))))
    (unless (zerop (process-exit-code proc))
      (error "Bad exit code: ~S~%Output:~% ~S"
             (process-exit-code proc)
             output))
    output))

(run "cc" "-O3"
     "-I" "../src/runtime/"
     "kill-non-lisp-thread.c"
     #+(and (or linux freebsd) (or x86-64 ppc mips)) "-fPIC"
     #+(and x86-64 darwin) "-arch" #+(and x86-64 darwin) "x86_64"
     #+darwin "-bundle" #-darwin "-shared"
     "-o" "kill-non-lisp-thread.so")

(load-shared-object (truename "kill-non-lisp-thread.so"))

(define-alien-routine kill-non-lisp-thread void)

(with-test (:name :kill-non-lisp-thread)
  (let ((receivedp nil))
    (push (lambda ()
            (setq receivedp t))
          (sb-thread::thread-interruptions sb-thread:*current-thread*))
    (kill-non-lisp-thread)
    (sleep 1)
    (assert receivedp)))

(delete-file "kill-non-lisp-thread.so")
