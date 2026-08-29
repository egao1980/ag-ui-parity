# ag-ui-parity matrix

Status: `have` · `partial` · `missing` · `skip`

Catalog: GET capabilities + last-user-text scenarios (`echo` `tools` `state` `reasoning` `interrupt` `resume`).

## SSE JSON

| Route | Lisp→Lisp | Lisp→Node | Lisp→Python | Node→Lisp | Python→Lisp |
|-------|-----------|-----------|-------------|-----------|-------------|
| GET capabilities | have | have | have | have | have |
| run lifecycle | have | have | have | have | have |
| text streaming | have | have | have | have | have |
| tool triad | have | have | have | have | have |
| state snapshot/delta | have | have | have | have | have |
| reasoning | have | have | have | have | have |
| interrupt / resume | have | have | have | have | have |

Lisp→Lisp also has an in-process (no HTTP) route.

Python→Lisp uses official `ag_ui.core` Event models over httpx. The Python SDK ships encoder + types, not `HttpAgent`.

## WKT proto (`application/vnd.ag-ui.event+proto`)

JSON dump → `google.protobuf.Value` via serdes `:wkt`. **Not** the official Event oneof.

| Route | Lisp→Lisp | Lisp→Node | Lisp→Python | Node→Lisp | Python→Lisp |
|-------|-----------|-----------|-------------|-----------|-------------|
| framed events | have (in-process) | skip | skip | skip | skip |

## skipped

| Route | notes |
|-------|-------|
| official `@ag-ui/proto` Event oneof | different binary; SSE JSON is the interop path |
| HTTP WKT proto via Hunchentoot | Clack octet bodies are written as strings |
| TEXT_MESSAGE_CHUNK / TOOL_CALL_CHUNK expansion | covered in `ag-ui-protocol` unit tests |
| capabilities negotiation | discovery only — GET is presence, not a handshake |
