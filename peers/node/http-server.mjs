import express from "express";
import { EventEncoder } from "@ag-ui/encoder";
import { CAPABILITIES, eventsFor } from "./scenarios.mjs";

const port = Number(process.argv[2] || 0);
if (!port) {
  console.error("usage: http-server.mjs <port>");
  process.exit(2);
}

const encoder = new EventEncoder();
const app = express();
app.use(express.json({ limit: "1mb" }));

app.get("/", (_req, res) => {
  res.json(CAPABILITIES);
});

app.post("/", (req, res) => {
  res.status(200);
  res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache");
  for (const event of eventsFor(req.body ?? {})) {
    res.write(encoder.encode(event));
  }
  res.end();
});

app.listen(port, "127.0.0.1", () => {
  process.stdout.write(`AG_UI_HTTP_LISTEN ${port}\n`);
});
