(in-package #:ag-ui-parity/tests)

(deftest node-client-lisp-http-server
  (if (http-peer-available-p :node)
      (ok (catalog-ok-p
           (call-with-lisp-http-server
            (lambda (url) (foreign-http-client-talk :node url)))))
      (skip "node HTTP peer not available")))

(deftest python-client-lisp-http-server
  (if (http-peer-available-p :python)
      (ok (catalog-ok-p
           (call-with-lisp-http-server
            (lambda (url) (foreign-http-client-talk :python url)))))
      (skip "python HTTP peer not available")))
