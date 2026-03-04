;;; jss-browser-api.el -- definition and support code for jss's interface to a specific browser  -*- lexical-binding:t -*-
;;
;; Copyright (C) 2013 Edward Marco Baringer
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of
;; the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be
;; useful, but WITHOUT ANY WARRANTY; without even the implied
;; warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
;; PURPOSE. See the GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public
;; License along with this program; if not, write to the Free
;; Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
;; MA 02111-1307 USA

;;; Commentary:
;;; Code:

(require 'cl-lib)
(require 'eieio)
(require 'jss-utils)
(require 'jss-deferred)
(require 'jss-super-mode)

(fmakunbound 'jss-browser-host)
(fmakunbound 'jss-set-browser-host)

(fmakunbound 'jss-browser-port)
(fmakunbound 'jss-set-browser-port)

(fmakunbound 'jss-browser-buffer)
(fmakunbound 'jss-set-browser-buffer)

(defclass jss-generic-browser ()
  (;;(host :initarg :host :accessor jss-browser-host)
   (host :initarg :host
 	 :reader jss-browser-host
	 :writer jss-set-browser-host)
   ;; (port :initarg :port :accessor jss-browser-port)
   (port :initarg :port
	 :reader jss-browser-port
	 :writer jss-set-browser-port)
   (tabs :initform '())
   ;; (buffer :accessor jss-browser-buffer))
   (buffer :initform nil
           :reader jss-browser-buffer
           :writer jss-set-browser-buffer))
  (:documentation "A specific browswer running somewhere, that we
can communicate with, and which, hopefully, has tabs we can
attach a console to."))

(cl-defgeneric jss-browser-connected-p (browser)
  "Returns T if we are currently connected to `browser`.")

(cl-defgeneric jss-browser-connect (browser)
  "Connect to `browser`. Returns a deferred that will complete
when the connection has been established.")

(cl-defgeneric jss-browser-disconnect (browser)
  "Disconnect from `browser`. Returns a deferred that will
complete when the connection has been broken.")

(cl-defgeneric jss-browser-get-tabs (browser)
  "Gets, and stores for later retrevial via `jss-browser-tabs`,
the list of currently open tabs in in `brower`.

Since we store references to tab objects in various buffers it is
important that this method modify, but not recreate, any already
existing tab objects.")

(cl-defgeneric jss-browser-description (browser)
  "Gets a human readable description of this browser. This string
is used, as is, in the *jss-browser* buffer to tell the user what
browser they're connected to.")

(cl-defgeneric jss-browser-tabs (browser)
  "Returns a list of jss-generic-tab objects, one for each tab
that was available when `jss-browser-get-tabs` was called.")

(cl-defgeneric jss-browser-find-tab (browser tab-id)
  "Given `tab-id`, an arbitrary opaque object returned by a
previous call to jss-tab-id, returns the corresponding tab
object.

We will sometimes need to store tab IDs and not tab objects
directly, this method server to map back from the ID to original
object.

No assumptions are made about the id objects themselves, except
that they are globally unique.")

(cl-defgeneric jss-browser-cleanup (browser)
  "Releases any state held by `browser`.")

(cl-defmethod jss-browser-cleanup ((browser jss-generic-browser))
  t)

(defclass jss-generic-tab ()
  ((browser :initarg :browser :accessor jss-tab-browser)
   (console :initform nil :accessor jss-tab-console)
   (ios :initform (make-hash-table :test 'equal)
        :accessor jss-tab-ios)
   (scripts :initform (make-hash-table :test 'equal)
            :accessor jss-tab-scripts))
  (:documentation "A tab in a browser."))

(make-variable-buffer-local
 (defvar jss-current-tab-instance nil
   "The current tab that should be used if we need to interact
with the browser."))

(cl-defgeneric jss-tab-available-p (tab)
  "Returns T if `tab' can be debugged, which means we'll try to
attach a console to it, returns NIL otherwise (which usually, but
not always, means there's already an in-browser debugger attached
to `tab`.")

(cl-defgeneric jss-tab-id (tab)
  "Returns a globally unique identifier for the object `tab`. The
returned value will be compared to other tabs with equal and
never be used within the same emacs session.")

(cl-defgeneric jss-tab-title (tab)
  "Returns the current title (a string) of the tab. Used to
inform the user about the state of the page being viewed.

As much as possible this should stay synchronized with the
current state of the browser, but jss itself doesn't depend an
the accuracy of this method (though the user would appreciate it
if it was up to date).")

(cl-defgeneric jss-tab-url (tab)
  "Returns the current url of the tab. This is used both to
inform the user what url the tab is currently viewing and by
jss's debugger's auto-resume-points.

As much as possible this should reflect the current state of the
browser, nothing will break if this returns a stale url, but some
functionality will not work as expected.")

(cl-defgeneric jss-tab-connected-p (tab)
  "Returns T if jss has an open connection to `tab`. This
usually, but not always, means there's a console buffer for
`tab` (though sometimes there will be a console buffer but
jss-tab-connected-p will return nil)")

(cl-defgeneric jss-tab-connect (tab)
  "Creates a connection to `tab`, returns a deferred object which
will complete when the connection has been established.")

(cl-defgeneric jss-tab-reload (tab)
  "Tell the browser to reload the contents of `tab`.")

(cl-defgeneric jss-tab-make-console (tab &rest initargs)
  "Creates a console instance for `tab`, passing make-instance
`initargs`. This method is basically a factory for browsers
specific console implementations.")

(cl-defgeneric jss-tab-disable-network-monitor (tab)
  "Disables logging and tracking of network IO for `tab`.")

(cl-defgeneric jss-tab-enable-network-monitor (tab)
  "Enables logging and tracking of network IO.")

(cl-defgeneric jss-tab-object-properties (tab object-id)
  "Returns an alist of proerty names and values for the remote
with id `object-id` in the current context of `tab`.

The keys of the plist are strings (simple elisp strings) and the
values are remote object instances (both primitive and non).")

(cl-defgeneric jss-tab-ensure-console (tab)
  "If `tab` doesn't already have a console object, then create it (and initialize its buffer).

Either way, returns `tabs`'s console.")

(defclass jss-generic-script ()
  ((tab :initarg :tab :accessor jss-script-tab)
   (buffer :initform nil :accessor jss-script-buffer)
   (body :initform nil :accessor jss-script-body))
  (:documentation "Represents a single piece of javascript source
code where errors can occur.

A script object usually, but not neccessarily, corrseponds to a
url or a <script> tag (the main exception being code internal to
the browser itself."))

(cl-defgeneric jss-script-id (script)
  "Returns a globally unique identifier for the script
`script`. This is an object we store and later use to retrieve
`script` and also an indetifier we can present to the user to
distinguish scripts that have no other natural identifier.

It can happen that a give url or script tag is changed and
reloaded, in that case we may have multiple script objects which
map back to the same url or file, but which are in fact
different (different source text, different id).")

(cl-defgeneric jss-script-url (script)
  "Return a url, or as close to one as possible, describing where
the text for `script` came from. The returned url should help the
user understand, as much as possible, where to find the source of
`script`.")

(cl-defgeneric jss-script-get-body (script)
  "Returns a deferred which, when it completes, will pass the
source code, as an elisp string, of the script `script`.")

(cl-defgeneric jss-evaluate (context text)
 "run the javascript code `text` and return a deferred which,
after the code has run, will complete with the returned value (a
remote value instance.)

The context is the environment, either a tab or a frame, within
which to run `text`.")

(cl-defgeneric jss-tab-get-script (tab script-id)
  "Gets the script object with id `script-id` from `tab`.")

(cl-defmethod jss-tab-get-script ((tab jss-generic-tab) script-id)
  (gethash script-id (jss-tab-scripts tab)))

(cl-defgeneric jss-tab-set-script (tab script-id script))

(cl-defmethod jss-tab-set-script ((tab jss-generic-tab) script-id script)
  (setf (jss-script-tab script) tab
        (gethash script-id (jss-tab-scripts tab)) script))

(defsetf jss-tab-get-script jss-tab-set-script)

(defclass jss-generic-console ()
  ((tab :initarg :tab
        :initform nil
        :accessor jss-console-tab))
  (:documentation "Represents a console attached to a tab.

A console is an object which servers two pruposes:

1. It can log events that have occured in a specific tab (network
IO, DOM changes, exceptions, etc.

2. It con excute code, as javascript source strings, within the
state of a specific web page."))

(make-variable-buffer-local
 (defvar jss-current-console-instance nil))

(defun jss-current-console ()
  jss-current-console-instance)

(defun jss-current-tab ()
  (or jss-current-tab-instance
      (if (jss-current-console)
          (jss-console-tab (jss-current-console))
        nil)))

(cl-defgeneric jss-console-mode* (console)
  "Initialize the current buffer with `console`.")

(cl-defmethod jss-tab-ensure-console ((tab jss-generic-tab))
  (or (jss-tab-console tab)
      (let ((console (jss-tab-make-console tab :tab tab)))
        (setf (jss-tab-console tab) console)
        (with-current-buffer (jss-console-buffer console)
          (jss-console-mode* console))
        console)))

(cl-defgeneric jss-console-clear (console)
  "Clears, removes from the buffer and releases stored memory,
all the objects (log messages, network io and evaluation
results) currently attached to `console`.

This causes references to the IO, debugger and script items
attached to `console` to be released within emacs and also on the
browser (if applicable)")

(cl-defgeneric jss-console-buffer (console)
  "Returns the current buffer where `console`'s events are logged
and where its prompt lives.")

(cl-defmethod jss-console-buffer ((console jss-generic-console))
  (get-buffer-create
   (format "*JSS Console/%s*" (jss-tab-id (jss-console-tab console)))))

(cl-defgeneric jss-console-disconnect (console)
  "Close the connection between jss and the console `console`.

Returns a deferred which will complete when the connection has
been closed.")

(cl-defgeneric jss-console-insert-io (console io)
  "Insert into `console`'s log a link to the network io `io`")

(cl-defgeneric jss-console-update-io (console io)
  "Find the line in the current buffer (a console buffer)
corresponding to `io` and replace it with a line describing the
current state of `io`.")

(cl-defgeneric jss-console-insert-message-objects (console level objects)
  "Given a list of remote objects, such as those passed to jss by
the browser when code calls window.console.log, insert the
corresponding remote-value objects into the current buffer using
the face and label corresponding to `level`.")

(cl-defgeneric jss-console-debug-message (console format-control &rest format-args))
(cl-defgeneric jss-console-log-message   (console format-control &rest format-args))
(cl-defgeneric jss-console-warn-message  (console format-control &rest format-args))
(cl-defgeneric jss-console-error-message (console format-control &rest format-args))

(defclass jss-generic-io ()
  ((tab :accessor jss-io-tab :initform nil)
   (start-time :accessor jss-io-start :initarg :start-time)
   (lifecycle :initform '() :accessor jss-io-lifecycle :initarg :lifecycle
              :documentation "A list of (EVENT WHEN) describing,
              if possible genericly, the events that have occured
              for this IO. Must be kept in chronological
              order (oldest first).")
   (buffer :initform nil :accessor jss-io-buffer))
  (:documentation "An object that describes a single
request/response between the browser and a server."))

(cl-defmacro with-existing-io ((tab io-id) &rest body)
  `(let ((io (jss-tab-get-io ,tab ,io-id)))
     (if io
         (progn ,@body)
       (jss-log-event (list :io :unknown-io-io ,io-id)))))
(put 'with-existing-io 'lisp-indent-function 1)

(cl-defgeneric jss-io-id (io)
  "Returns a globally unique id identifying `io`.")

(cl-defgeneric jss-io-request-method (io)
  "Returns the HTTP request method (a string) used by`io`.")

(cl-defgeneric jss-io-request-url (io)
  "The url requested by `io`.")

(cl-defgeneric jss-io-request-data (io)
  "The POST data sent with `io`.")

(cl-defgeneric jss-io-request-headers (io)
  "Returns the HTTP request headers sent by `io` as an alist
whose keys and values are strings.")

(cl-defgeneric jss-io-raw-request-headers (io)
  "Returns the HTTP request headers sent by `io` as a
string (really a sequence of bytes)")

(cl-defgeneric jss-io-response-headers (io)
  "Returns the HTTP response headers sent by `io` as an alist
whose keys and values are strings.")

(cl-defgeneric jss-io-raw-response-headers (io)
  "Returns the HTTP response headers sent by `io` as a string (a
sequence of bytes)")

(cl-defgeneric jss-io-response-status (io)
  "Either an integer specifying the status code or nil specifying
that we're still waiting for the response.")

(cl-defgeneric jss-io-response-content-type (io)
  "The normalized content type returned by `io`")

(cl-defgeneric jss-io-response-content-length (io)
  "the length, in bytes (not characters) of data recevied by
`io`")

(cl-defgeneric jss-io-response-data (io)
  "The data, as a string (without encoding).")

(cl-defgeneric jss-tab-get-io (tab io-id)
  "returns the IO object in `tab` whose id is `io-id` (which is a
value as returned by `jss-io-id`")

(cl-defmethod jss-tab-get-io ((tab jss-generic-tab) io-id)
  (gethash io-id (jss-tab-ios tab)))

(cl-defmethod jss-tab-set-io ((tab jss-generic-tab) io-id io-object)
  (if (null (jss-io-tab io-object))
      (setf (jss-io-tab io-object) tab
            (gethash io-id (jss-tab-ios tab)) io-object)
    (unless (eq tab (jss-io-tab io-object))
      (error "Attempt to add IO %s to tab %s, but it's already registered with %s."
             io-object tab (jss-io-tab io-object)))))

(defsetf jss-tab-get-io jss-tab-set-io)

(defclass jss-generic-debugger ()
  ((buffer :accessor jss-debugger-buffer)
   (tab    :accessor jss-debugger-tab :initarg :tab))
  (:documentation "Represents some exception, and its state, on
the browser. "))

(cl-defgeneric jss-debugger-mode* (debugger)
  "Initializes the buffer for the debugger `debugger`.")

(cl-defgeneric jss-debugger-stack-frames (debugger)
  "Returns a list, in order from bottom (closest to the
exception) to top (farthest from the error, usually an event
handler in the browser) of jss-frame objects.")

(cl-defgeneric jss-debugger-exception (debugger)
  "Returns the exception, as a remote-value, describing what went
wrong with `debugger`")

(cl-defgeneric jss-debugger-resume    (debugger)
  "resume, continue or play depending on the terminology, from
exception.")

(cl-defgeneric jss-debugger-step-into (debugger)
  "Step into the next function call. Resumes the current debugger
and triggers a new one at the next function call in the current
stack.")

(cl-defgeneric jss-debugger-step-over (debugger)
    "Step over the next function call. Resumes the current
debugger and triggers a new one before the next function call.")

(cl-defgeneric jss-debugger-step-out  (debugger)
    "Step into the next function call. Resumes the current
debugger and triggers a new one in the next function called by
the function currently paused.")

(cl-defgeneric jss-tab-open-debugger (tab debugger)
  "Creates, and switches to, a new debugger buffer given the tab
instance `tab` and the debugger obejct `debugged`.")

;;; nb: do NOT name the debugger parameter debugger. it messes with emacs in strange ways.
(cl-defmethod jss-tab-open-debugger ((tab jss-generic-tab) dbg)
  (setf (jss-debugger-buffer dbg) (get-buffer-create (generate-new-buffer-name "*JSS Debugger*"))
        (jss-debugger-tab dbg) tab)
  (with-current-buffer (jss-debugger-buffer dbg)
    (jss-debugger-mode* dbg)
    (when (buffer-live-p (jss-debugger-buffer dbg)) 
      (switch-to-buffer (jss-debugger-buffer dbg)))))

(cl-defgeneric jss-debugger-cleanup (debugger)
  "Releases all objects, in emacs and the remote browser, tied to
`debugger`")

(cl-defmethod jss-debugger-cleanup ((debugger jss-generic-debugger))
  t)

(cl-defgeneric jss-tab-set-debugger-sensitivity (tab sensitivity)
  "Set the break level of `tab`'s debugger to `sensitivity` (:all, :uncaught or :never)")

(cl-defgeneric jss-debugger-insert-message (debugger)
  "Insert, at the current point, text describing why `debugger` has been opened (the ecxeption, the source location, etc.).")

(defclass jss-generic-stack-frame ()
  ((debugger :initarg :debugger :accessor jss-frame-debugger))
  (:documentation "Represents one stack frame, a function/method
call in some environment, that lead to a particulare execption
being signaled."))

(cl-defgeneric jss-frame-function-name (frame)
  "The name of the function enclosing this stack frame.")

(cl-defgeneric jss-frame-source-hint (frame)
  "A human readable string decribing, to the user, where this
frame \"is\". This string will be displayed but is not used
internally.")

(cl-defgeneric jss-frame-get-source-location (frame)
  "Return a deferred which completes with a list of (script
line-number column-number) which jss can use to open a buffer and
position point of the exact spot where this frame's exception
started.")

(cl-defgeneric jss-frame-restart (frame)
  "Restart execution from this frame, taking into effect any
changes to the global or local state that have been made. If this
is not possible signal an error.")

(cl-eval-when (compile load eval)
  (defvar jss-remote-value-counter 0))

(defclass jss-generic-remote-value ()
  ((id :accessor jss-remote-value-id
       :initform (cl-incf jss-remote-value-counter)
       :initarg :id))
  (:documentation "Represents some value in the browser."))

(cl-defgeneric jss-remote-value-description (remote-object)
  "Returns a human readable string describing, briefly and not
necessarily precisely, `remote-object`.")

(cl-defgeneric jss-remote-value-insert-description (remote-object)
  "Insert into the current buffer `remote-sbject`'s
description. Should, but need not, call
jss-remote-value-description.")

(cl-defmethod jss-remote-value-insert-description ((o jss-generic-remote-value))
  (insert (jss-limit-string-length (jss-remote-value-description o) 60)))

(defclass jss-generic-remote-primitive (jss-generic-remote-value)
  ((value :initarg :value :accessor jss-remote-primitive-value))
  (:documentation "A primitive, non divisible, remote object."))

(defclass jss-generic-remote-boolean (jss-generic-remote-primitive) ())

(defclass jss-generic-remote-true (jss-generic-remote-boolean) ())
(cl-defmethod jss-remote-value-description ((object jss-generic-remote-true)) "true")

(defclass jss-generic-remote-false (jss-generic-remote-boolean) ())
(cl-defmethod jss-remote-value-description ((object jss-generic-remote-false)) "false")

(defclass jss-generic-remote-string (jss-generic-remote-primitive) ())
(cl-defmethod jss-remote-value-description ((string jss-generic-remote-string))
  (prin1-to-string (jss-remote-primitive-value string)))

(cl-defmethod jss-remote-value-insert-description ((o jss-generic-remote-string))
  (insert (jss-remote-value-description o)))

(defclass jss-generic-remote-number (jss-generic-remote-primitive) ())
(cl-defmethod jss-remote-value-description ((number jss-generic-remote-number))
  (let ((value (jss-remote-primitive-value number)))
    (if (integerp value)
        (format "%d" value)
      (format "%g" value))))

(defclass jss-generic-remote-NaN (jss-generic-remote-primitive) ())
(cl-defmethod jss-remote-value-description ((object jss-generic-remote-NaN)) "NaN")

(defclass jss-generic-remote-plus-infinity (jss-generic-remote-primitive) ())
(cl-defmethod jss-remote-value-description ((object jss-generic-remote-plus-infinity)) "+Inf")

(defclass jss-generic-remote-minus-infinity (jss-generic-remote-primitive) ())
(cl-defmethod jss-remote-value-description ((object jss-generic-remote-minus-infinity)) "-Inf")

(defclass jss-generic-remote-undefined (jss-generic-remote-primitive) ())
(cl-defmethod jss-remote-value-description ((object jss-generic-remote-undefined)) "undefined")

(defclass jss-generic-remote-no-value (jss-generic-remote-primitive) ())
(cl-defmethod jss-remote-value-description ((object jss-generic-remote-no-value)) "no value.")

(defclass jss-generic-remote-null (jss-generic-remote-primitive) ())
(cl-defmethod jss-remote-value-description ((object jss-generic-remote-null)) "null")

(defclass jss-generic-remote-non-primitive (jss-generic-remote-value) ()
  (:documentation "A remote value that has properites."))

(defclass jss-generic-remote-object (jss-generic-remote-non-primitive) ())

(cl-defgeneric jss-remote-object-class-name (object))

(cl-defgeneric jss-remote-object-label (object))

(cl-defmethod jss-remote-value-description ((object jss-generic-remote-object))
  (let ((class-name (jss-remote-object-class-name object))
        (label  (jss-remote-object-label object)))
    (if (string= label class-name)
        (format "[%s]" label)
      (format "[%s %s]" class-name label))))

(cl-defgeneric jss-remote-object-get-properties (object tab))

(defclass jss-generic-remote-function (jss-generic-remote-non-primitive) ())
(cl-defgeneric jss-remote-function-get-source-location (function))

(defclass jss-generic-remote-array (jss-generic-remote-object) ())

(provide 'jss-browser-api)
