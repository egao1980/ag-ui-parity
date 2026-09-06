(in-package #:ag-ui-parity/tests)

(deftest lisp-client-lisp-inprocess
  (ok (catalog-ok-p (lisp-inprocess-talk))))

(deftest lisp-client-lisp-http-server
  (ok (catalog-ok-p (lisp-http-lisp-server))))

(deftest lisp-client-lisp-wkt-proto
  (ok (catalog-ok-p (lisp-proto-lisp-server))))

(deftest lisp-client-lisp-oneof-proto
  (ok (oneof-catalog-ok-p (lisp-oneof-lisp-server))))

(deftest lisp-client-lisp-http-oneof
  (ok (oneof-catalog-ok-p (lisp-http-oneof-lisp-server))))

(deftest lisp-client-node-oneof-proto
  (if (http-peer-available-p :node)
      (ok (oneof-catalog-ok-p (lisp-oneof-node-roundtrip)))
      (skip "node HTTP peer not available")))

(deftest lisp-client-node-http-server
  (if (http-peer-available-p :node)
      (ok (catalog-ok-p (lisp-http-peer-server :node)))
      (skip "node HTTP peer not available")))

(deftest lisp-client-python-http-server
  (if (http-peer-available-p :python)
      (ok (catalog-ok-p (lisp-http-peer-server :python)))
      (skip "python HTTP peer not available")))
