(in-package #:ag-ui-parity)

(defun %ensure-http-server ()
  (or http-server-protocol:*http-server-backend*
      (http-server-backend-hunchentoot:use-hunchentoot-backend)))

(defun call-with-async-http (fn)
  "Bind http-backend-async × libuv so sync HTTP:POST awaits the loop."
  (asdf:load-system "event-backend-libuv")
  (asdf:load-system "http-backend-async")
  (let* ((eb (event-backend-libuv:make-libuv-backend))
         (el (event-protocol:make-event-loop eb))
         (hb (http-backend-async:make-async-backend))
         (http-backend-async:*event-backend-maker* (lambda () eb)))
    (event-protocol:with-event-backend (eb)
      (event-protocol:with-event-loop-var (el)
        (let ((http-protocol:*http-backend* hb))
          (funcall fn))))))

(defun %make-input (scenario)
  (ag-ui-protocol:make-run-agent-input
   :thread-id (format nil "t-~a" scenario)
   :run-id (format nil "r-~a" scenario)
   :messages (vector (ag-ui-protocol:make-ag-ui-message
                      :id (format nil "u-~a" scenario)
                      :role "user"
                      :content scenario))
   :resume (when (string= scenario "resume")
             (vector (ag-ui-protocol:make-resume-entry
                      :interrupt-id "int-1"
                      :status "resolved"
                      :payload (ag-ui-protocol:json-object "approved" t))))))

(defun %fetch-capabilities (url)
  (let ((res (http:get url :headers '(("accept" . "application/json")))))
    (unless (<= 200 (http-protocol:response-status res) 299)
      (error "GET capabilities HTTP ~a" (http-protocol:response-status res)))
    (let ((body (http-protocol:response-body res)))
      (ag-ui-protocol:decode-agent-capabilities
       (if (stringp body)
           body
           (babel:octets-to-string body :encoding :utf-8))))))

(defun %run-scenario (url scenario &key (format :json))
  (let* ((input (%make-input scenario))
         (payload (ag-ui-protocol:encode-json
                   (ag-ui-protocol:encode-run-agent-input input)))
         (accept (if (eq format :protobuf)
                     ag-ui-protocol:+ag-ui-proto-media-type+
                     ag-ui-protocol:+ag-ui-sse-media-type+))
         (res (http:post url
                         :content payload
                         :headers `(("content-type" . "application/json")
                                    ("accept" . ,accept))))
         (status (http-protocol:response-status res)))
    (unless (<= 200 status 299)
      (error "POST ~a HTTP ~a" scenario status))
    (let ((body (http-protocol:response-body res)))
      (if (eq format :protobuf)
          (ag-ui-protocol:decode-ag-ui-framed
           (if (and (vectorp body) (not (stringp body)))
               body
               (error "protobuf response was not octets")))
          (ag-ui-protocol:decode-ag-ui-sse-stream
           (if (stringp body)
               body
               (babel:octets-to-string body :encoding :utf-8)))))))

(defun lisp-talk (url &key (format :json))
  (call-with-async-http
   (lambda ()
     (let ((scenarios nil))
       (dolist (name *scenarios*)
         (setf scenarios
               (list* (intern (string-upcase name) :keyword)
                      (summarize-events (%run-scenario url name :format format))
                      scenarios)))
       (list :capabilities (%fetch-capabilities url)
             :scenarios (nreverse scenarios))))))

(defun lisp-inprocess-talk ()
  (let* ((agent (make-parity-agent))
         (scenarios nil))
    (dolist (name *scenarios*)
      (setf scenarios
            (list* (intern (string-upcase name) :keyword)
                   (summarize-events
                    (ag-ui-protocol:run-agent agent (%make-input name)))
                   scenarios)))
    (list :capabilities (ag-ui-protocol:get-capabilities agent)
          :scenarios (nreverse scenarios))))

(defun call-with-lisp-http-server (fn)
  (%ensure-http-server)
  (let* ((port (%free-port))
         (url (format nil "http://127.0.0.1:~a/" port))
         (app (ag-ui-protocol:make-ag-ui-app (make-parity-agent) :path "/")))
    (http-server-protocol:with-server
        (s app :host "127.0.0.1" :port port)
      (sleep 0.15)
      (funcall fn url))))

(defun lisp-http-talk (url)
  (lisp-talk url))

(defun lisp-http-lisp-server ()
  (call-with-lisp-http-server #'lisp-talk))

(defun lisp-http-peer-server (kind)
  (with-peer-http-server (url kind)
    (lisp-talk url)))

(defun lisp-proto-lisp-server ()
  (call-with-lisp-http-server
   (lambda (url) (lisp-talk url :format :protobuf))))

(defun parse-json-line (line)
  (when (and line (plusp (length (string-trim '(#\space) line))))
    (ignore-errors (ag-ui-protocol:decode-json line))))

(defun %js (obj key)
  (and obj (ag-ui-protocol:param obj key)))

(defun %js-string (obj key)
  (let ((v (%js obj key)))
    (cond
      ((null v) "")
      ((stringp v) v)
      (t (princ-to-string v)))))

(defun %foreign-summary (rec)
  (list :types (map 'list #'identity (or (%js rec "types") #()))
        :text (%js-string rec "text")
        :reasoning (%js-string rec "reasoning")
        :tool (let ((v (%js rec "tool"))) (and v (if (stringp v) v (princ-to-string v))))
        :snapshot-count (%js rec "snapshotCount")
        :delta-value (%js rec "deltaValue")
        :outcome (%js-string rec "outcome")
        :interrupt-id (%js-string rec "interruptId")))

(defun %foreign-capabilities (rec)
  (ag-ui-protocol:make-agent-capabilities
   :identity (make-instance 'ag-ui-protocol:identity-capabilities
                            :name (%js-string rec "name"))
   :transport (make-instance 'ag-ui-protocol:transport-capabilities
                             :streaming (eq (%js rec "streaming") t))))

(defun %foreign-report (rec)
  (let ((raw (or (%js rec "scenarios") (ag-ui-protocol:json-object)))
        (scenarios nil))
    (dolist (name *scenarios*)
      (let ((sub (%js raw name)))
        (when sub
          (setf scenarios
                (list* (intern (string-upcase name) :keyword)
                       (%foreign-summary sub)
                       scenarios)))))
    (list :capabilities (%foreign-capabilities rec)
          :scenarios (nreverse scenarios))))

(defun foreign-http-client-talk (kind url)
  (let ((cmd (http-client-command kind url)))
    (multiple-value-bind (out err)
        (uiop:run-program cmd
                          :output :string
                          :error-output :string
                          :ignore-error-status t)
      (let ((parsed (loop for line in (uiop:split-string out :separator '(#\newline))
                          for rec = (parse-json-line line)
                          when rec collect rec)))
        (unless parsed
          (error "foreign HTTP client ~a produced no JSON~%cmd: ~s~%stdout:~%~a~%stderr:~%~a"
                 kind cmd out err))
        (%foreign-report (first (last parsed)))))))
