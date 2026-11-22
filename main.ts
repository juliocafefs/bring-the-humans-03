// bring-the-humans-03 entry program (Node 22, standard library only).
//
// The entry itself is a TikTok video; this program's whole job is to hand
// the grader this repository's VIDEO.json, the file that names the video.
// Before copying anything it reads the file and validates it: VIDEO.json
// must be a small JSON object whose "url" is a full TikTok video address
// (https://www.tiktok.com/@<handle>/video/<id>) — a short link or a photo
// post address would be refused by the gate, so it is refused here first.
// Only a valid file is copied, byte for byte, into the output directory.
//
// No network, no wall clock, no state: two runs write the same bytes.
//
// Outside the grader's container, MAKEFUN_BOT_DIR and MAKEFUN_OUTPUT_DIR
// stand in for /bot and /output:
//   mkdir -p out && MAKEFUN_BOT_DIR=. MAKEFUN_OUTPUT_DIR=out node main.ts

import { copyFileSync, mkdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const botDir = process.env.MAKEFUN_BOT_DIR ?? "/bot";
const outDir = process.env.MAKEFUN_OUTPUT_DIR ?? "/output";
const sourcePath = join(botDir, "VIDEO.json");
const targetPath = join(outDir, "VIDEO.json");

// The gate's own caps and address shape (see the kit's RULES.txt, "The gate").
const MAX_VIDEO_JSON_BYTES = 16384;
const TIKTOK_VIDEO_URL =
  /^https:\/\/(www\.|m\.)?tiktok\.com\/@[^/]+\/video\/\d+\/?([?#].*)?$/;

function fail(message: string): never {
  console.error(`main.ts: ${message}`);
  process.exit(1);
}

// --- read -----------------------------------------------------------------
let raw: string;
try {
  const size = statSync(sourcePath).size;
  if (size > MAX_VIDEO_JSON_BYTES) {
    fail(
      `VIDEO.json is ${size} bytes; the gate allows at most ${MAX_VIDEO_JSON_BYTES}`,
    );
  }
  raw = readFileSync(sourcePath, "utf8");
} catch (err) {
  fail(`cannot read ${sourcePath}: ${(err as Error).message}`);
}

// --- validate ---------------------------------------------------------------
let parsed: unknown;
try {
  parsed = JSON.parse(raw!);
} catch {
  fail("VIDEO.json is not valid JSON");
}

const url = (parsed as { url?: unknown } | null)?.url;
if (typeof url !== "string" || !TIKTOK_VIDEO_URL.test(url)) {
  fail(
    'VIDEO.json must be an object whose "url" is a full TikTok video ' +
      "address, https://www.tiktok.com/@<handle>/video/<id>",
  );
}

// --- hand over --------------------------------------------------------------
mkdirSync(outDir, { recursive: true });
copyFileSync(sourcePath, targetPath);
console.log(`main.ts: VIDEO.json -> ${targetPath} (video: ${url})`);
