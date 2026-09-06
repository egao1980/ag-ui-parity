(in-package #:ag-ui-parity)

(defun print-matrix ()
  (format t "~&ag-ui-parity matrix~%")
  (format t "  peers: node=~a python=~a~%"
          (if (node-available-p) "yes" "no")
          (if (python-available-p) "yes" "no"))
  (format t "  catalog: GET capabilities + echo/tools/state/reasoning/interrupt/resume~%")
  (format t "  SSE JSON: Lisp↔Lisp, Lisp↔Node, Lisp↔Python~%")
  (format t "  WKT proto: Lisp↔Lisp only (application/vnd.ag-ui.event+proto)~%")
  (format t "  official oneof: Lisp↔Lisp + Lisp↔Node @ag-ui/proto (+oneof)~%")
  (values))
