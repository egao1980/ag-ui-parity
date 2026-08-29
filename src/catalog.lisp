(in-package #:ag-ui-parity)

(defparameter *scenarios* '("echo" "tools" "state" "reasoning" "interrupt" "resume")
  "User-message keys that select a canned event sequence.")

(defun %thread (input)
  (or (ag-ui-protocol:run-agent-input-thread-id input) "thread"))

(defun %run (input)
  (or (ag-ui-protocol:run-agent-input-run-id input) "run"))

(defun %started (input)
  (ag-ui-protocol:make-run-started-event :thread-id (%thread input) :run-id (%run input)))

(defun %finished (input &key result outcome)
  (ag-ui-protocol:make-run-finished-event
   :thread-id (%thread input) :run-id (%run input)
   :result result :outcome outcome))

(defun %echo-events (input)
  (let ((mid "msg-echo"))
    (list (%started input)
          (ag-ui-protocol:make-text-message-start-event :message-id mid :role "assistant")
          (ag-ui-protocol:make-text-message-content-event :message-id mid :delta "pong")
          (ag-ui-protocol:make-text-message-end-event :message-id mid)
          (%finished input))))

(defun %tools-events (input)
  (list (%started input)
        (ag-ui-protocol:make-tool-call-start-event :tool-call-id "tc-1" :tool-call-name "echo")
        (ag-ui-protocol:make-tool-call-args-event :tool-call-id "tc-1" :delta "{\"x\":1}")
        (ag-ui-protocol:make-tool-call-end-event :tool-call-id "tc-1")
        (ag-ui-protocol:make-tool-call-result-event
         :message-id "msg-tool" :tool-call-id "tc-1" :content "ok")
        (%finished input)))

(defun %state-events (input)
  (list (%started input)
        (ag-ui-protocol:make-state-snapshot-event
         :snapshot (ag-ui-protocol:json-object "count" 0))
        (ag-ui-protocol:make-state-delta-event
         :delta (vector (ag-ui-protocol:json-object
                         "op" "replace" "path" "/count" "value" 1)))
        (%finished input)))

(defun %reasoning-events (input)
  (let ((mid "msg-reason"))
    (list (%started input)
          (ag-ui-protocol:make-reasoning-start-event :message-id mid)
          (ag-ui-protocol:make-reasoning-message-start-event :message-id mid)
          (ag-ui-protocol:make-reasoning-message-content-event :message-id mid :delta "think")
          (ag-ui-protocol:make-reasoning-message-end-event :message-id mid)
          (ag-ui-protocol:make-reasoning-end-event :message-id mid)
          (%finished input))))

(defun %interrupt-events (input)
  (list (%started input)
        (ag-ui-protocol:make-run-interrupted-event
         :thread-id (%thread input) :run-id (%run input)
         :interrupts (list (ag-ui-protocol:make-interrupt
                            :id "int-1"
                            :reason "tool_call"
                            :message "approve?")))))

(defun %slot (object name)
  (ag-ui-protocol:event-field object (find-symbol name :ag-ui-protocol)))

(defun %resume-resolved-p (input)
  (let ((entries (%slot input "RESUME")))
    (and (plusp (length (or entries #())))
         (let ((entry (elt entries 0)))
           (and (string= (ag-ui-protocol:resume-interrupt-id entry) "int-1")
                (string= (ag-ui-protocol:resume-status entry) "resolved"))))))

(defun %resume-events (input)
  (unless (%resume-resolved-p input)
    (return-from %resume-events
      (list (%started input)
            (ag-ui-protocol:make-run-error-event :message "resume missing int-1" :code "resume"))))
  (let ((mid "msg-resume"))
    (list (%started input)
          (ag-ui-protocol:make-text-message-start-event :message-id mid :role "assistant")
          (ag-ui-protocol:make-text-message-content-event :message-id mid :delta "approved")
          (ag-ui-protocol:make-text-message-end-event :message-id mid)
          (%finished input))))

(defun parity-handler (input)
  "Canned sequences keyed by the last user message."
  (let ((scenario (ag-ui-protocol:last-user-text input)))
    (cond
      ((string= scenario "echo") (%echo-events input))
      ((string= scenario "tools") (%tools-events input))
      ((string= scenario "state") (%state-events input))
      ((string= scenario "reasoning") (%reasoning-events input))
      ((string= scenario "interrupt") (%interrupt-events input))
      ((string= scenario "resume") (%resume-events input))
      (t (%echo-events input)))))

(defun make-parity-agent (&key (name "parity"))
  (ag-ui-protocol:make-ag-ui-agent :name name :handler #'parity-handler))

(defun %event-type (event)
  (or (ag-ui-protocol:ag-ui-event-type event)
      (%slot event "EVENT-TYPE")
      ""))

(defun %text-deltas (events)
  (with-output-to-string (out)
    (map nil (lambda (ev)
               (when (typep ev 'ag-ui-protocol:text-message-content-event)
                 (write-string (or (ag-ui-protocol:text-message-delta ev) "") out)))
         events)))

(defun %reasoning-deltas (events)
  (with-output-to-string (out)
    (map nil (lambda (ev)
               (when (typep ev 'ag-ui-protocol:reasoning-message-content-event)
                 (write-string (or (ag-ui-protocol:text-message-delta ev) "") out)))
         events)))

(defun %first-tool-name (events)
  (let ((ev (find-if (lambda (e) (typep e 'ag-ui-protocol:tool-call-start-event)) events)))
    (and ev (ag-ui-protocol:tool-call-name ev))))

(defun %snapshot-count (events)
  (let ((ev (find-if (lambda (e) (typep e 'ag-ui-protocol:state-snapshot-event)) events)))
    (and ev (ag-ui-protocol:param (ag-ui-protocol:state-snapshot-value ev) "count"))))

(defun %delta-value (events)
  (let ((ev (find-if (lambda (e) (typep e 'ag-ui-protocol:state-delta-event)) events)))
    (when ev
      (let* ((patch (ag-ui-protocol:state-delta-patch ev))
             (op (and (plusp (length patch)) (elt patch 0))))
        (ag-ui-protocol:param op "value")))))

(defun %interrupt-id (events)
  (let ((ev (find-if (lambda (e) (typep e 'ag-ui-protocol:run-finished-event)) events)))
    (when ev
      (let* ((outcome (%slot ev "OUTCOME"))
             (ints (and outcome (%slot outcome "INTERRUPTS")))
             (first (and ints (plusp (length ints)) (elt ints 0))))
        (and first (ag-ui-protocol:interrupt-id first))))))

(defun %outcome-type (events)
  (let ((ev (find-if (lambda (e) (typep e 'ag-ui-protocol:run-finished-event)) events)))
    (when ev
      (let ((outcome (%slot ev "OUTCOME")))
        (and outcome (ag-ui-protocol:run-outcome-type outcome))))))

(defun summarize-events (events)
  (list :types (map 'list #'%event-type events)
        :text (%text-deltas events)
        :reasoning (%reasoning-deltas events)
        :tool (%first-tool-name events)
        :snapshot-count (%snapshot-count events)
        :delta-value (%delta-value events)
        :outcome (%outcome-type events)
        :interrupt-id (%interrupt-id events)))

(defun scenario-ok-p (name summary)
  (let ((types (getf summary :types)))
    (flet ((has (type) (member type types :test #'string=)))
      (and (has "RUN_STARTED")
           (ecase (intern (string-upcase name) :keyword)
             (:echo (and (has "TEXT_MESSAGE_CONTENT")
                         (equal (getf summary :text) "pong")
                         (has "RUN_FINISHED")))
             (:tools (and (has "TOOL_CALL_START")
                          (has "TOOL_CALL_ARGS")
                          (has "TOOL_CALL_END")
                          (equal (getf summary :tool) "echo")))
             (:state (and (has "STATE_SNAPSHOT")
                          (has "STATE_DELTA")
                          (eql (getf summary :snapshot-count) 0)
                          (eql (getf summary :delta-value) 1)))
             (:reasoning (and (has "REASONING_START")
                              (has "REASONING_MESSAGE_CONTENT")
                              (equal (getf summary :reasoning) "think")
                              (has "REASONING_END")))
             (:interrupt (and (string= (getf summary :outcome) "interrupt")
                              (equal (getf summary :interrupt-id) "int-1")))
             (:resume (and (has "TEXT_MESSAGE_CONTENT")
                           (equal (getf summary :text) "approved")
                           (has "RUN_FINISHED"))))))))

(defun %capabilities-ok-p (caps)
  (and caps
       (let ((id (ag-ui-protocol:capabilities-identity caps))
             (tr (ag-ui-protocol:capabilities-transport caps)))
         (and id (search "parity" (string-downcase
                                   (or (ag-ui-protocol:identity-name id) "")))
              tr (ag-ui-protocol:transport-streaming-p tr)))))

(defun catalog-ok-p (report)
  (and (%capabilities-ok-p (getf report :capabilities))
       (every (lambda (name)
                (scenario-ok-p name (getf (getf report :scenarios)
                                          (intern (string-upcase name) :keyword))))
              *scenarios*)))
