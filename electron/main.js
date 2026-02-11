const { app, BrowserWindow, globalShortcut, ipcMain } = require("electron");
const { spawn } = require("child_process");
const path = require("path");

let mainWindow;
let pythonProcess;
let currentHotkey = null;
let currentMode = "push-to-talk";
let isActive = false;

// Find the Python backend
function getPythonCommand() {
  // In packaged app, use bundled binary
  const resourcePath = process.resourcesPath;
  const bundled = path.join(resourcePath, "listen", "listen");
  try {
    require("fs").accessSync(bundled, require("fs").constants.X_OK);
    return [bundled, ["serve"]];
  } catch {
    // Development: use system `listen` command
    return ["listen", ["serve"]];
  }
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 480,
    height: 640,
    minWidth: 360,
    minHeight: 480,
    titleBarStyle: "hiddenInset",
    backgroundColor: "#1a1a1a",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile("index.html");

  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

// Spawn the Python backend
function startBackend() {
  const [cmd, args] = getPythonCommand();

  pythonProcess = spawn(cmd, args, {
    stdio: ["pipe", "pipe", "pipe"],
  });

  let buffer = "";

  pythonProcess.stdout.on("data", (data) => {
    buffer += data.toString();
    const lines = buffer.split("\n");
    buffer = lines.pop(); // keep incomplete line in buffer

    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const msg = JSON.parse(line);
        if (mainWindow && !mainWindow.isDestroyed()) {
          mainWindow.webContents.send("backend-message", msg);
        }

        // Track state for hotkey management
        if (msg.type === "state") {
          if (msg.hotkey && msg.hotkey !== currentHotkey) {
            registerHotkey(msg.hotkey);
          }
          if (msg.mode) {
            currentMode = msg.mode;
          }
          if (msg.state === "recording" || msg.state === "listening") {
            isActive = true;
          } else if (
            msg.state === "ready" ||
            msg.state === "muted" ||
            msg.state === "stopped"
          ) {
            isActive = false;
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

function registerHotkey(hotkey) {
  // Unregister previous
  if (currentHotkey) {
    try {
      globalShortcut.unregister(formatHotkey(currentHotkey));
    } catch {
      // ignore
    }
  }

  currentHotkey = hotkey;
  const electronHotkey = formatHotkey(hotkey);

  try {
    const success = globalShortcut.register(electronHotkey, () => {
      // Toggle active state
      const newActive = !isActive;
      isActive = newActive;
      sendToBackend({ action: "set_active", active: newActive });
    });

    if (!success) {
      console.error(`Failed to register hotkey: ${electronHotkey}`);
    }
  } catch (err) {
    console.error(`Hotkey registration error: ${err.message}`);
  }
}

// Convert "ctrl+shift+space" to Electron format "Ctrl+Shift+Space"
function formatHotkey(hotkey) {
  return hotkey
    .split("+")
    .map((part) => {
      const p = part.trim().toLowerCase();
      if (p === "ctrl") return "Ctrl";
      if (p === "shift") return "Shift";
      if (p === "alt") return "Alt";
      if (p === "cmd" || p === "command" || p === "meta") return "Command";
      if (p === "space") return "Space";
      if (p === "tab") return "Tab";
      if (p === "enter" || p === "return") return "Return";
      return p.charAt(0).toUpperCase() + p.slice(1);
    })
    .join("+");
}

// IPC: renderer -> main -> Python
ipcMain.on("send-command", (_event, msg) => {
  sendToBackend(msg);
});

ipcMain.on("update-hotkey", (_event, hotkey) => {
  sendToBackend({ action: "set_hotkey", hotkey });
});

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
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("will-quit", () => {
  globalShortcut.unregisterAll();
  if (pythonProcess) {
    sendToBackend({ action: "quit" });
    setTimeout(() => {
      if (pythonProcess) {
        pythonProcess.kill();
      }
    }, 2000);
  }
});
