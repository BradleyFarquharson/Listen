#!/usr/bin/env node

/**
 * Compiles the macOS Globe key listener from Swift source.
 * Only runs on macOS. Caches the build based on source hash.
 */

const { execSync } = require("child_process");
const fs = require("fs");
const crypto = require("crypto");
const path = require("path");

const RESOURCES = path.join(__dirname, "..", "resources");
const SOURCE = path.join(RESOURCES, "macos-globe-listener.swift");
const BINARY = path.join(RESOURCES, "globe-listener");
const HASH_FILE = BINARY + ".sha256";

if (process.platform !== "darwin") {
  console.log("Skipping Globe listener build (not macOS)");
  process.exit(0);
}

if (!fs.existsSync(SOURCE)) {
  console.error(`Source not found: ${SOURCE}`);
  process.exit(1);
}

// Check if recompile is needed
const sourceHash = crypto
  .createHash("sha256")
  .update(fs.readFileSync(SOURCE))
  .digest("hex");

if (fs.existsSync(BINARY) && fs.existsSync(HASH_FILE)) {
  const savedHash = fs.readFileSync(HASH_FILE, "utf-8").trim();
  if (savedHash === sourceHash) {
    console.log("Globe listener binary is up to date, skipping compile.");
    process.exit(0);
  }
}

// Determine target architecture
const archArg = process.argv.find((a) => a.startsWith("--arch="));
const arch = archArg
  ? archArg.split("=")[1]
  : process.env.TARGET_ARCH || process.arch;

const swiftTarget =
  arch === "arm64" ? "arm64-apple-macosx11.0" : "x86_64-apple-macosx10.15";

console.log(`Compiling Globe listener for ${arch} (${swiftTarget})...`);

const cacheDir = path.join(RESOURCES, ".module-cache");
if (!fs.existsSync(cacheDir)) {
  fs.mkdirSync(cacheDir, { recursive: true });
}

// Try xcrun swiftc first, fallback to plain swiftc
const commands = [
  `xcrun swiftc "${SOURCE}" -O -target ${swiftTarget} -module-cache-path "${cacheDir}" -o "${BINARY}"`,
  `swiftc "${SOURCE}" -O -target ${swiftTarget} -o "${BINARY}"`,
];

let compiled = false;
for (const cmd of commands) {
  try {
    execSync(cmd, { stdio: "inherit" });
    compiled = true;
    break;
  } catch (err) {
    console.warn(`Command failed: ${cmd}`);
  }
}

if (!compiled) {
  console.error(
    "Failed to compile Globe listener. Ensure Xcode Command Line Tools are installed:"
  );
  console.error("  xcode-select --install");
  process.exit(1);
}

// Set executable permission and save hash
fs.chmodSync(BINARY, 0o755);
fs.writeFileSync(HASH_FILE, sourceHash);

console.log(`Globe listener compiled: ${BINARY}`);
