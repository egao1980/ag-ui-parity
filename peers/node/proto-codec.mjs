import { encode, decode } from "@ag-ui/proto";
import { readFileSync } from "node:fs";

const mode = process.argv[2];
if (mode !== "encode" && mode !== "decode") {
  process.stderr.write("usage: proto-codec.mjs encode|decode\n");
  process.exit(2);
}

const input = readFileSync(0);
if (mode === "encode") {
  const event = JSON.parse(input.toString("utf8"));
  process.stdout.write(Buffer.from(encode(event)));
} else {
  process.stdout.write(JSON.stringify(decode(new Uint8Array(input))));
}
