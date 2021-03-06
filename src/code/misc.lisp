;;;; that part of misc.lisp functionality which is used on the
;;;; cross-compilation host Lisp as well as the target Lisp

;;;; This software is part of the SBCL system. See the README file for
;;;; more information.
;;;;
;;;; This software is derived from the CMU CL system, which was
;;;; written at Carnegie Mellon University and released into the
;;;; public domain. The software is in the public domain and is
;;;; provided with absolutely no warranty. See the COPYING and CREDITS
;;;; files for more information.

(in-package "SB!IMPL")

(defun sb!xc:lisp-implementation-type ()
  "SBCL")

(defun sb!xc:lisp-implementation-version ()
  #.(format nil "~A~@[.~A~]"
            (sb-cold:read-from-file "version.lisp-expr")
            (let ((pathname "branch-version.lisp-expr"))
              (when (probe-file pathname)
                (sb-cold:read-from-file pathname)))))
