;;;; This file contains implementation-dependent parts of the type
;;;; support code. This is stuff which deals with the mapping from
;;;; types defined in Common Lisp to types actually supported by an
;;;; implementation.

;;;; This software is part of the SBCL system. See the README file for
;;;; more information.
;;;;
;;;; This software is derived from the CMU CL system, which was
;;;; written at Carnegie Mellon University and released into the
;;;; public domain. The software is in the public domain and is
;;;; provided with absolutely no warranty. See the COPYING and CREDITS
;;;; files for more information.

(in-package "SB!KERNEL")

;;;; FIXME: I'm not sure where to put this. -- WHN 19990817

(def!type sb!vm:word () `(unsigned-byte ,sb!vm:n-word-bits))
(def!type sb!vm:signed-word () `(signed-byte ,sb!vm:n-word-bits))


;;;; implementation-dependent DEFTYPEs

;;; Make DOUBLE-FLOAT a synonym for LONG-FLOAT, SINGLE-FLOAT for
;;; SHORT-FLOAT. This is expanded before the translator gets a chance,
;;; so we will get precedence.
#!-long-float
(setf (info :type :kind 'long-float) :defined)
#!-long-float
(sb!xc:deftype long-float (&optional low high)
  `(double-float ,low ,high))
(setf (info :type :kind 'short-float) :defined)
(sb!xc:deftype short-float (&optional low high)
  `(single-float ,low ,high))

;;; an index into an integer
(sb!xc:deftype bit-index () `(integer 0 ,sb!xc:most-positive-fixnum))

;;; worst-case values for float attributes
(sb!xc:deftype float-exponent ()
  #!-long-float 'double-float-exponent
  #!+long-float 'long-float-exponent)
(sb!xc:deftype float-digits ()
  #!-long-float `(integer 0 ,sb!vm:double-float-digits)
  #!+long-float `(integer 0 ,sb!vm:long-float-digits))
(sb!xc:deftype float-radix () '(integer 2 2))
(sb!xc:deftype float-int-exponent ()
  #!-long-float 'double-float-int-exponent
  #!+long-float 'long-float-int-exponent)

;;; a code for BOOLE
(sb!xc:deftype boole-code () '(unsigned-byte 4))

;;; a byte specifier (as generated by BYTE)
(sb!xc:deftype byte-specifier () 'cons)

;;; result of CHAR-INT
(sb!xc:deftype char-int () 'char-code)

;;; PATHNAME pieces, as returned by the PATHNAME-xxx functions
(sb!xc:deftype pathname-host () '(or sb!impl::host null))
(sb!xc:deftype pathname-device ()
  '(or simple-string (member nil :unspecific)))
(sb!xc:deftype pathname-directory () 'list)
(sb!xc:deftype pathname-name ()
  '(or simple-string sb!impl::pattern (member nil :unspecific :wild)))
(sb!xc:deftype pathname-type ()
  '(or simple-string sb!impl::pattern (member nil :unspecific :wild)))
(sb!xc:deftype pathname-version ()
  '(or integer (member nil :newest :wild :unspecific)))

;;; internal time format. (Note: not a FIXNUM, ouch..)
(sb!xc:deftype internal-time () 'unsigned-byte)

(sb!xc:deftype bignum-element-type () `(unsigned-byte ,sb!vm:n-word-bits))
(sb!xc:deftype bignum-type () 'bignum)
;;; FIXME: see also DEFCONSTANT MAXIMUM-BIGNUM-LENGTH in
;;; src/code/bignum.lisp.  -- CSR, 2004-07-19
(sb!xc:deftype bignum-index ()
  '(integer 0 #.(1- (ash 1 (- 32 sb!vm:n-widetag-bits)))))

;;;; hooks into the type system

(sb!xc:deftype unboxed-array (&optional dims)
  (collect ((types (list 'or)))
    (dolist (type *specialized-array-element-types*)
      (when (subtypep type '(or integer character float (complex float)))
        (types `(array ,type ,dims))))
    (types)))

(sb!xc:deftype simple-unboxed-array (&optional dims)
  (collect ((types (list 'or)))
    (dolist (type *specialized-array-element-types*)
      (when (subtypep type '(or integer character float (complex float)))
        (types `(simple-array ,type ,dims))))
    (types)))

;;; Return the symbol that describes the format of FLOAT.
(declaim (ftype (function (float) symbol) float-format-name))
(defun float-format-name (x)
  (etypecase x
    (single-float 'single-float)
    (double-float 'double-float)
    #!+long-float (long-float 'long-float)))

;;; This function is called when the type code wants to find out how
;;; an array will actually be implemented. We set the
;;; SPECIALIZED-ELEMENT-TYPE to correspond to the actual
;;; specialization used in this implementation.
(declaim (ftype (function (array-type) array-type) specialize-array-type))
(defun specialize-array-type (type)
  (let ((eltype (array-type-element-type type)))
    (setf (array-type-specialized-element-type type)
          (if (or (eq eltype *wild-type*)
                  ;; This is slightly dubious, but not as dubious as
                  ;; assuming that the upgraded-element-type should be
                  ;; equal to T, given the way that the AREF
                  ;; DERIVE-TYPE optimizer works.  -- CSR, 2002-08-19
                  (unknown-type-p eltype))
              *wild-type*
              (dolist (stype-name *specialized-array-element-types*
                                  *universal-type*)
                ;; FIXME: Mightn't it be better to have
                ;; *SPECIALIZED-ARRAY-ELEMENT-TYPES* be stored as precalculated
                ;; SPECIFIER-TYPE results, instead of having to calculate
                ;; them on the fly this way? (Call the new array
                ;; *SPECIALIZED-ARRAY-ELEMENT-SPECIFIER-TYPES* or something..)
                (let ((stype (specifier-type stype-name)))
                  (aver (not (unknown-type-p stype)))
                  (when (csubtypep eltype stype)
                    (return stype))))))
    type))

(defun sb!xc:upgraded-array-element-type (spec &optional environment)
  #!+sb-doc
  "Return the element type that will actually be used to implement an array
   with the specifier :ELEMENT-TYPE Spec."
  (declare (ignore environment))
  (if (unknown-type-p (specifier-type spec))
      (error "undefined type: ~S" spec)
      (type-specifier (array-type-specialized-element-type
                       (specifier-type `(array ,spec))))))

(defun sb!xc:upgraded-complex-part-type (spec &optional environment)
  #!+sb-doc
  "Return the element type of the most specialized COMPLEX number type that
   can hold parts of type SPEC."
  (declare (ignore environment))
  (let ((type (specifier-type spec)))
    (cond
      ((eq type *empty-type*) nil)
      ((unknown-type-p type) (error "undefined type: ~S" spec))
      (t
       (let ((ctype (specifier-type `(complex ,spec))))
         (cond
           ((eq ctype *empty-type*) '(eql 0))
           ((csubtypep ctype (specifier-type '(complex single-float)))
            'single-float)
           ((csubtypep ctype (specifier-type '(complex double-float)))
            'double-float)
           #!+long-float
           ((csubtypep ctype (specifier-type '(complex long-float)))
            'long-float)
           ((csubtypep ctype (specifier-type '(complex rational)))
            'rational)
           (t 'real)))))))

;;; Return the most specific integer type that can be quickly checked that
;;; includes the given type.
(defun containing-integer-type (subtype)
  (dolist (type '(fixnum
                  (signed-byte 32)
                  (unsigned-byte 32)
                  integer)
                (error "~S isn't an integer type?" subtype))
    (when (csubtypep subtype (specifier-type type))
      (return type))))

;;; If TYPE has a CHECK-xxx template, but doesn't have a corresponding
;;; PRIMITIVE-TYPE, then return the template's name. Otherwise, return NIL.
(defun hairy-type-check-template-name (type)
  (declare (type ctype type))
  (typecase type
    (cons-type
     (if (type= type (specifier-type 'cons))
         'sb!c:check-cons
         nil))
    (built-in-classoid
     (if (type= type (specifier-type 'symbol))
         'sb!c:check-symbol
         nil))
    (numeric-type
     (cond ((type= type (specifier-type 'fixnum))
            'sb!c:check-fixnum)
           #!+#.(cl:if (cl:= 32 sb!vm:n-word-bits) '(and) '(or))
           ((type= type (specifier-type '(signed-byte 32)))
            'sb!c:check-signed-byte-32)
           #!+#.(cl:if (cl:= 32 sb!vm:n-word-bits) '(and) '(or))
           ((type= type (specifier-type '(unsigned-byte 32)))
            'sb!c:check-unsigned-byte-32)
           #!+#.(cl:if (cl:= 64 sb!vm:n-word-bits) '(and) '(or))
           ((type= type (specifier-type '(signed-byte 64)))
            'sb!c:check-signed-byte-64)
           #!+#.(cl:if (cl:= 64 sb!vm:n-word-bits) '(and) '(or))
           ((type= type (specifier-type '(unsigned-byte 64)))
            'sb!c:check-unsigned-byte-64)
           (t nil)))
    (fun-type
     'sb!c:check-fun)
    (t
     nil)))