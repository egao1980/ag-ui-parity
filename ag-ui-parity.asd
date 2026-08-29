(defsystem "ag-ui-parity"
  :version "0.1.0"
  :description "Interop canary: ag-ui-protocol vs official Node/Python AG-UI SDKs"
  :author "egao1980"
  :license "MIT"
  :depends-on ((:version "ag-ui-protocol" "0.3.0")
               (:version "ag-ui-backend-sse" "0.2.1")
               (:version "protobuf-backend-cl-protobufs" "0.2.0")
               "http-protocol"
               "http-backend-async"
               "http-encoding-chipz"
               "http-encoding-brotli"
               "http-encoding-zstd"
               "cl-stack-ssl"
               "event-protocol"
               "event-backend-libuv"
               "http-server-protocol"
               "http-server-backend-hunchentoot"
               "babel"
               "uiop"
               "usocket"
               "rove")
  :properties (:cl-repo
               (:ci (:with ("dissect" "cl-stack-ssl")
                     :load-before-test ("cl+ssl" "cl-stack-ssl"
                                        "event-backend-libuv"
                                        "http-backend-async"
                                        "protobuf-backend-cl-protobufs"))))
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "catalog")
               (:file "peers")
               (:file "harness")
               (:file "report"))
  :in-order-to ((test-op (test-op "ag-ui-parity/tests"))))

(defsystem "ag-ui-parity/tests"
  :depends-on ("ag-ui-parity" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "lisp-client")
               (:file "foreign-client"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "ag-ui-parity tests failed"))))
