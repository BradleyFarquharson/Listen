const {
  app,
  BrowserWindow,
  globalShortcut,
  ipcMain,
  nativeTheme,
  screen,
} = require("electron");
const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");

let mainWindow;
let pillWindow;
let pythonProcess;
let globeProcess = null;
let currentHotkey = null;
let currentMode = "push-to-talk";
let isActive = false;

// Find the Python backend
function getPythonCommand() {
  const resourcePath = process.resourcesPath;
  const bundled = path.join(resourcePath, "listen", "listen");
  try {
    fs.accessSync(bundled, fs.constants.X_OK);
    return [bundled, ["serve"]];
  } catch {
    return ["listen", ["serve"]];
  }
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 480,
    height: 640,
    minWidth: 380,
    minHeight: 500,
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 16, y: 16 },
    backgroundColor: nativeTheme.shouldUseDarkColors ? "#09090b" : "#ffffff",
    icon: path.join(__dirname, "..", "assets", "icon.png"),
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile("index.html");

  mainWindow.on("closed", () => {
    mainWindow = null;
    hidePill();
  });

  nativeTheme.on("updated", () => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send("system-theme-changed", {
        dark: nativeTheme.shouldUseDarkColors,
      });
    }
  });
}

// ============================================================
// Floating pill window
// ============================================================

function createPillWindow() {
  const display = screen.getPrimaryDisplay();
  const { width: screenW, height: screenH } = display.workAreaSize;
  const pillW = 200;
  const pillH = 48;

  pillWindow = new BrowserWindow({
    width: pillW,
    height: pillH,
    x: Math.round((screenW - pillW) / 2),
    y: screenH - pillH - 32, // 32px from bottom
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    skipTaskbar: true,
    resizable: false,
    movable: false,
    focusable: false,
    hasShadow: false,
    webPreferences: {
      contextIsolation: false,
      nodeIntegration: true,
    },
  });

  pillWindow.loadFile("pill.html");
  pillWindow.setIgnoreMouseEvents(true);

  pillWindow.on("closed", () => {
    pillWindow = null;
  });
}

function showPill(state) {
  if (!pillWindow || pillWindow.isDestroyed()) {
    createPillWindow();
  }

  // Wait for content to load before sending update
  if (pillWindow.webContents.isLoading()) {
    pillWindow.webContents.once("did-finish-load", () => {
      sendPillUpdate(state);
    });
  } else {
    sendPillUpdate(state);
  }

  pillWindow.showInactive();
}

function sendPillUpdate(state) {
  if (!pillWindow || pillWindow.isDestroyed()) return;

  let text, mode;
  if (state === "recording") {
    text = "Recording...";
    mode = "recording";
  } else if (state === "listening") {
    text = "Listening...";
    mode = "listening";
  } else {
    text = state;
    mode = "recording";
  }

  pillWindow.webContents.send("pill-update", { text, mode });
}

function hidePill() {
  if (pillWindow && !pillWindow.isDestroyed()) {
    pillWindow.close();
    pillWindow = null;
  }
}

// ============================================================
// Globe (fn) key listener — native Swift helper
// ============================================================

function isGlobeHotkey(hotkey) {
  const h = hotkey.toLowerCase().trim();
  return h === "fn" || h === "globe";
}

function getGlobeBinaryPath() {
  // Check resources dir (development)
  const devPath = path.join(__dirname, "resources", "globe-listener");
  if (fs.existsSync(devPath)) return devPath;

  // Check bundled resources (production)
  const prodPath = path.join(process.resourcesPath, "globe-listener");
  if (fs.existsSync(prodPath)) return prodPath;

  return null;
}

function startGlobeListener() {
  stopGlobeListener();

  if (process.platform !== "darwin") {
    console.warn("Globe key listener only supported on macOS");
    return false;
  }

  const binaryPath = getGlobeBinaryPath();
  if (!binaryPath) {
    console.error("Globe listener binary not found. Run: node scripts/build-globe-listener.js");
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send("backend-message", {
        type: "error",
        message: "Globe key binary not found. Run: npm run compile:native",
      });
    }
    return false;
  }

  globeProcess = spawn(binaryPath, [], {
    stdio: ["pipe", "pipe", "pipe"],
  });

  let buffer = "";

  globeProcess.stdout.on("data", (data) => {
    buffer += data.toString();
    const lines = buffer.split("\n");
    buffer = lines.pop();

    for (const line of lines) {
      const msg = line.trim();
      if (msg === "READY") {
        console.log("Globe listener ready");
        // Tell renderer the Globe key is active
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.webContents.send("backend-message", {
            type: "globe_status",
            active: true,
          });
        }
      } else if (msg === "FN_DOWN") {
        if (!isActive) {
          isActive = true;
          sendToBackend({ action: "set_active", active: true });
        }
      } else if (msg === "FN_UP") {
        if (isActive) {
          isActive = false;
          sendToBackend({ action: "set_active", active: false });
        }
      }
    }
  });

  globeProcess.stderr.on("data", (data) => {
    const msg = data.toString().trim();
    console.error("[globe]", msg);
    if (msg.includes("Accessibility")) {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send("backend-message", {
          type: "error",
          message: "Globe key requires Accessibility permission. Go to System Settings → Privacy & Security → Accessibility and add Listen.",
        });
      }
    }
  });

  globeProcess.on("close", (code) => {
    console.log(`Globe listener exited with code ${code}`);
    globeProcess = null;
  });

  return true;
}

function stopGlobeListener() {
  if (globeProcess) {
    globeProcess.kill();
    globeProcess = null;
  }
}

// ============================================================
// Python backend
// ============================================================

function startBackend() {
  const [cmd, args] = getPythonCommand();

  pythonProcess = spawn(cmd, args, {
    stdio: ["pipe", "pipe", "pipe"],
  });

  let buffer = "";

  pythonProcess.stdout.on("data", (data) => {
    buffer += data.toString();
    const lines = buffer.split("\n");
    buffer = lines.pop();

    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const msg = JSON.parse(line);
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.webContents.send("backend-message", msg);
        }

        if (msg.type === "state") {
          if (msg.hotkey && msg.hotkey !== currentHotkey) {
            registerHotkey(msg.hotkey);
          }
          if (msg.mode) {
            currentMode = msg.mode;
          }

          // Show/hide pill based on active state
          if (msg.state === "recording" || msg.state === "listening") {
            isActive = true;
            showPill(msg.state);
          } else if (
            msg.state === "ready" ||
            msg.state === "muted" ||
            msg.state === "stopped"
          ) {
            isActive = false;
            hidePill();
          }
        }
      } catch {
        // ignore non-JSON lines
      }
    }
  });

  pythonProcess.stderr.on("data", (data) => {
    console.error("[python]", data.toString().trim());
  });

  pythonProcess.on("close", (code) => {
    console.log(`Python process exited with code ${code}`);
    pythonProcess = null;
  });
}

function sendToBackend(msg) {
  if (pythonProcess && pythonProcess.stdin.writable) {
    pythonProcess.stdin.write(JSON.stringify(msg) + "\n");
  }
}

// ============================================================
// Hotkey registration
// ============================================================

function registerHotkey(hotkey) {
  // Unregister previous hotkey
  if (currentHotkey) {
    if (isGlobeHotkey(currentHotkey)) {
      stopGlobeListener();
    } else {
      try {
        globalShortcut.unregister(formatHotkey(currentHotkey));
      } catch {
        // ignore
      }
    }
  }

  currentHotkey = hotkey;

  // Globe/fn key — use native Swift listener
  if (isGlobeHotkey(hotkey)) {
    const started = startGlobeListener();
    if (!started && mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send("backend-message", {
        type: "error",
        message: "Could not start Globe key listener.",
      });
    }
    return;
  }

  // Regular hotkey — use Electron globalShortcut
  const electronHotkey = formatHotkey(hotkey);

  try {
    const success = globalShortcut.register(electronHotkey, () => {
      const newActive = !isActive;
      isActive = newActive;
      sendToBackend({ action: "set_active", active: newActive });
    });

    if (!success) {
      console.error(`Failed to register hotkey: ${electronHotkey}`);
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send("backend-message", {
          type: "error",
          message: `Could not register hotkey "${hotkey}". Try a function key (F1-F24) or a modifier combo (e.g. Ctrl+Space).`,
        });
      }
    }
  } catch (err) {
    console.error(`Hotkey registration error: ${err.message}`);
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send("backend-message", {
        type: "error",
        message: `Invalid hotkey "${hotkey}". Try a function key (F1-F24) or a modifier combo (e.g. Ctrl+Space).`,
      });
    }
  }
}

// Convert our hotkey format to Electron accelerator format.
function formatHotkey(hotkey) {
  return hotkey
    .split("+")
    .map((part) => {
      const p = part.trim().toLowerCase();
      if (p === "ctrl" || p === "control") return "Ctrl";
      if (p === "shift") return "Shift";
      if (p === "alt" || p === "option") return "Alt";
      if (p === "cmd" || p === "command" || p === "meta") return "Command";
      if (p === "space") return "Space";
      if (p === "tab") return "Tab";
      if (p === "enter" || p === "return") return "Return";
      if (p === "backspace") return "Backspace";
      if (p === "delete") return "Delete";
      if (p === "escape" || p === "esc") return "Escape";
      if (p === "arrowup" || p === "up") return "Up";
      if (p === "arrowdown" || p === "down") return "Down";
      if (p === "arrowleft" || p === "left") return "Left";
      if (p === "arrowright" || p === "right") return "Right";
      if (p === "pageup") return "PageUp";
      if (p === "pagedown") return "PageDown";
      if (p === "home") return "Home";
      if (p === "end") return "End";
      if (p === "insert") return "Insert";
      if (p === "printscreen") return "PrintScreen";
      // Function keys: f1-f24
      const fMatch = p.match(/^f(\d+)$/);
      if (fMatch) return `F${fMatch[1]}`;
      // Single letter/number — uppercase for Electron
      if (p.length === 1) return p.toUpperCase();
      // Anything else — capitalize first letter
      return p.charAt(0).toUpperCase() + p.slice(1);
    })
    .join("+");
}

// ============================================================
// IPC handlers
// ============================================================

ipcMain.on("send-command", (_event, msg) => {
  sendToBackend(msg);
});

ipcMain.on("update-hotkey", (_event, hotkey) => {
  sendToBackend({ action: "set_hotkey", hotkey });
});

ipcMain.handle("get-system-dark", () => {
  return nativeTheme.shouldUseDarkColors;
});

// Tell the renderer whether the Globe key is available on this platform
ipcMain.handle("get-globe-available", () => {
  if (process.platform !== "darwin") return false;
  return getGlobeBinaryPath() !== null;
});

// ============================================================
// App lifecycle
// ============================================================

app.whenReady().then(() => {
  createWindow();
  startBackend();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  sendToBackend({ action: "quit" });
  hidePill();
  stopGlobeListener();
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("will-quit", () => {
  globalShortcut.unregisterAll();
  hidePill();
  stopGlobeListener();
  if (pythonProcess) {
    sendToBackend({ action: "quit" });
    setTimeout(() => {
      if (pythonProcess) {
        pythonProcess.kill();
      }
    }, 2000);
  }
});
