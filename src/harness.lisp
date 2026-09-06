(in-package #:ag-ui-parity)

(defun %ensure-http-server ()
  (or http-server-protocol:*http-server-backend*
      (http-server-backend-hunchentoot:use-hunchentoot-backend)))

(defun call-with-async-http (fn)
  "Bind http-backend-async × libuv so sync HTTP:POST awaits the loop."
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
         (accept (ecase format
                   (:json ag-ui-protocol:+ag-ui-sse-media-type+)
                   (:protobuf ag-ui-protocol:+ag-ui-proto-media-type+)
                   (:oneof ag-ui-protocol:+ag-ui-oneof-media-type+)))
         (res (http:post url
                         :content payload
                         :headers `(("content-type" . "application/json")
                                    ("accept" . ,accept))))
         (status (http-protocol:response-status res)))
    (unless (<= 200 status 299)
      (error "POST ~a HTTP ~a" scenario status))
    (let ((body (http-protocol:response-body res)))
      (ecase format
        (:protobuf
         (ag-ui-protocol:decode-ag-ui-framed
          (if (and (vectorp body) (not (stringp body)))
              body
              (error "protobuf response was not octets"))))
        (:oneof
         (ag-ui-protocol:decode-ag-ui-framed-oneof
          (if (and (vectorp body) (not (stringp body)))
              body
              (error "oneof response was not octets"))))
        (:json
         (ag-ui-protocol:decode-ag-ui-sse-stream
          (if (stringp body)
              body
              (babel:octets-to-string body :encoding :utf-8))))))))

(defun lisp-talk (url &key (format :json))
  (call-with-async-http
   (lambda ()
     (let ((scenarios nil)
           (names (if (eq format :oneof) *oneof-scenarios* *scenarios*)))
       (dolist (name names)
         (setf scenarios
               (nconc scenarios
                      (%scenario-plist name
                                       (summarize-events
                                        (%run-scenario url name :format format))))))
       (list :capabilities (%fetch-capabilities url)
             :scenarios scenarios)))))

(defun lisp-inprocess-talk ()
  (let* ((agent (make-parity-agent))
         (scenarios nil))
    (dolist (name *scenarios*)
      (setf scenarios
            (nconc scenarios
                   (%scenario-plist name
                                    (summarize-events
                                     (ag-ui-protocol:run-agent agent (%make-input name)))))))
    (list :capabilities (ag-ui-protocol:get-capabilities agent)
          :scenarios scenarios)))

(defun %materialize-clack-body (body)
  "Hunchentoot will not write a Clack streaming function. Buffer it."
  (cond
    ((functionp body)
     (list (with-output-to-string (s)
             (funcall body s))))
    (t body)))

(defun make-parity-app ()
  (let ((inner (ag-ui-protocol:make-ag-ui-app (make-parity-agent) :path "/")))
    (lambda (env)
      (let ((res (funcall inner env)))
        (cond
          ;; Binary proto/oneof: already a response function (octet writer).
          ((functionp res) res)
          ((and (consp res) (functionp (third res)))
           (list (first res) (second res)
                 (%materialize-clack-body (third res))))
          (t res))))))

(defun call-with-lisp-http-server (fn)
  (%ensure-http-server)
  (let* ((port (%free-port))
         (url (format nil "http://127.0.0.1:~a/" port))
         (app (make-parity-app)))
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

(defun %frame-events (events)
  (let ((out (make-array 0 :element-type '(unsigned-byte 8)
                           :adjustable t :fill-pointer 0)))
    (map nil (lambda (ev)
               (loop for b across (ag-ui-protocol:encode-ag-ui-framed ev)
                     do (vector-push-extend b out)))
         events)
    (coerce out '(simple-array (unsigned-byte 8) (*)))))

(defun lisp-proto-lisp-server ()
  "WKT framed round-trip (Lisp-only)."
  (let* ((agent (make-parity-agent))
         (scenarios nil))
    (dolist (name *scenarios*)
      (let* ((events (ag-ui-protocol:run-agent agent (%make-input name)))
             (decoded (ag-ui-protocol:decode-ag-ui-framed (%frame-events events))))
        (setf scenarios
              (nconc scenarios (%scenario-plist name (summarize-events decoded))))))
    (list :capabilities (ag-ui-protocol:get-capabilities agent)
          :scenarios scenarios)))

(defun %frame-oneof-events (events)
  (let ((out (make-array 0 :element-type '(unsigned-byte 8)
                           :adjustable t :fill-pointer 0)))
    (map nil (lambda (ev)
               (loop for b across (ag-ui-protocol:encode-ag-ui-framed-oneof ev)
                     do (vector-push-extend b out)))
         events)
    (coerce out '(simple-array (unsigned-byte 8) (*)))))

(defun lisp-oneof-lisp-server ()
  "Official Event oneof framed round-trip (in-process)."
  (let* ((agent (make-parity-agent))
         (scenarios nil))
    (dolist (name *oneof-scenarios*)
      (let* ((events (ag-ui-protocol:run-agent agent (%make-input name)))
             (decoded (ag-ui-protocol:decode-ag-ui-framed-oneof
                       (%frame-oneof-events events))))
        (setf scenarios
              (nconc scenarios (%scenario-plist name (summarize-events decoded))))))
    (list :capabilities (ag-ui-protocol:get-capabilities agent)
          :scenarios scenarios)))

(defun lisp-http-oneof-lisp-server ()
  (call-with-lisp-http-server
   (lambda (url) (lisp-talk url :format :oneof))))

(defun %proto-codec ()
  (uiop:native-namestring
   (merge-pathnames "node/proto-codec.mjs" *peer-root*)))

(defun %write-bytes (path octets)
  (with-open-file (s path :direction :output
                         :element-type '(unsigned-byte 8)
                         :if-exists :supersede
                         :if-does-not-exist :create)
    (write-sequence octets s)))

(defun %read-bytes (path)
  (with-open-file (s path :element-type '(unsigned-byte 8))
    (let ((buf (make-array (file-length s) :element-type '(unsigned-byte 8))))
      (read-sequence buf s)
      buf)))

(defun node-proto-encode (event)
  (uiop:with-temporary-file (:pathname in :keep t)
    (uiop:with-temporary-file (:pathname out :keep t)
      (unwind-protect
           (progn
             (with-open-file (s in :direction :output :if-exists :supersede)
               (write-string (ag-ui-protocol:encode-ag-ui-event event
                                                               :format :json)
                             s))
             (with-open-file (os out :direction :output
                                    :element-type '(unsigned-byte 8)
                                    :if-exists :supersede)
               (uiop:run-program (list (which "node") (%proto-codec) "encode")
                                 :input in :output os :error-output :string))
             (%read-bytes out))
        (ignore-errors (delete-file in))
        (ignore-errors (delete-file out))))))

(defun node-proto-decode (octets)
  (uiop:with-temporary-file (:pathname in :keep t)
    (uiop:with-temporary-file (:pathname out :keep t)
      (unwind-protect
           (progn
             (%write-bytes in octets)
             (uiop:run-program (list (which "node") (%proto-codec) "decode")
                               :input in :output out :error-output :string)
             (ag-ui-protocol:decode-ag-ui-event
              (uiop:read-file-string out) :format :json))
        (ignore-errors (delete-file in))
        (ignore-errors (delete-file out))))))

(defun lisp-oneof-node-roundtrip ()
  "Lisp↔Node @ag-ui/proto encode/decode for oneof catalog events."
  (unless (node-available-p)
    (error "node peer not available"))
  (let* ((agent (make-parity-agent))
         (scenarios nil))
    (dolist (name *oneof-scenarios*)
      (let* ((events (ag-ui-protocol:run-agent agent (%make-input name)))
             (via-node
              (mapcar (lambda (ev)
                        (node-proto-decode
                         (ag-ui-protocol:encode-ag-ui-event-oneof ev)))
                      events))
             (via-lisp
              (mapcar (lambda (ev)
                        (ag-ui-protocol:decode-ag-ui-event-oneof
                         (node-proto-encode ev)))
                      events)))
        (unless (equal (mapcar #'ag-ui-protocol:ag-ui-event-type events)
                       (mapcar #'ag-ui-protocol:ag-ui-event-type via-node))
          (error "Lisp→Node type mismatch in ~a" name))
        (unless (equal (mapcar #'ag-ui-protocol:ag-ui-event-type events)
                       (mapcar #'ag-ui-protocol:ag-ui-event-type via-lisp))
          (error "Node→Lisp type mismatch in ~a" name))
        (setf scenarios
              (nconc scenarios (%scenario-plist name (summarize-events via-lisp))))))
    (list :capabilities (ag-ui-protocol:get-capabilities agent)
          :scenarios scenarios)))

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
                (nconc scenarios (%scenario-plist name (%foreign-summary sub)))))))
    (list :capabilities (%foreign-capabilities rec)
          :scenarios scenarios)))

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
