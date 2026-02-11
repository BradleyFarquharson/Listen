// ============================================================
// DOM elements
// ============================================================

const statusDot = document.getElementById("status-dot");
const statusText = document.getElementById("status-text");
const menuBtn = document.getElementById("menu-btn");
const settingsOverlay = document.getElementById("settings-overlay");
const settingsClose = document.getElementById("settings-close");
const transcriptContent = document.getElementById("transcript-content");
const modeSelect = document.getElementById("mode-select");
const hotkeyInput = document.getElementById("hotkey-input");
const deviceSelect = document.getElementById("device-select");
const statWords = document.getElementById("stat-words");
const statSegments = document.getElementById("stat-segments");
const statTime = document.getElementById("stat-time");

let modelLoaded = false;
let currentState = "idle";

// Stats tracking
let totalWords = 0;
let totalSegments = 0;
let sessionStartTime = null;
let sessionTimer = null;

// ============================================================
// Theme management
// ============================================================

let themePreference = localStorage.getItem("theme") || "system";

async function initTheme() {
  const systemDark = await window.listen.getSystemDark();
  applyTheme(themePreference, systemDark);
  document.querySelectorAll(".theme-btn").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.theme === themePreference);
  });
}

function applyTheme(preference, systemDark) {
  const dark =
    preference === "system" ? systemDark : preference === "dark";
  document.documentElement.classList.toggle("dark", dark);
}

document.querySelectorAll(".theme-btn").forEach((btn) => {
  btn.addEventListener("click", async () => {
    themePreference = btn.dataset.theme;
    localStorage.setItem("theme", themePreference);
    const systemDark = await window.listen.getSystemDark();
    applyTheme(themePreference, systemDark);
    document.querySelectorAll(".theme-btn").forEach((b) => {
      b.classList.toggle("active", b.dataset.theme === themePreference);
    });
  });
});

window.listen.onSystemThemeChanged(async (data) => {
  if (themePreference === "system") {
    applyTheme("system", data.dark);
  }
});

initTheme();

// ============================================================
// Settings menu
// ============================================================

menuBtn.addEventListener("click", () => {
  settingsOverlay.classList.remove("hidden");
});

settingsClose.addEventListener("click", () => {
  settingsOverlay.classList.add("hidden");
});

// Close on backdrop click (clicking the overlay itself, not the panel)
settingsOverlay.addEventListener("click", (e) => {
  if (e.target === settingsOverlay) {
    settingsOverlay.classList.add("hidden");
  }
});

// Close on Escape
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && !settingsOverlay.classList.contains("hidden")) {
    settingsOverlay.classList.add("hidden");
  }
});

// ============================================================
// Session timer
// ============================================================

function startSessionTimer() {
  if (sessionStartTime) return;
  sessionStartTime = Date.now();
  sessionTimer = setInterval(updateTimerDisplay, 1000);
}

function updateTimerDisplay() {
  if (!sessionStartTime) return;
  const elapsed = Math.floor((Date.now() - sessionStartTime) / 1000);
  const mins = Math.floor(elapsed / 60);
  const secs = elapsed % 60;
  statTime.textContent = `${mins}:${secs.toString().padStart(2, "0")}`;
}

// ============================================================
// Status updates
// ============================================================

function setStatus(state, text) {
  currentState = state;
  statusDot.className = "";
  statusDot.classList.add(state);
  statusText.textContent = text;
}

// ============================================================
// Transcription display + stats
// ============================================================

function addTranscription(text) {
  // Update stats
  const wordCount = text.trim().split(/\s+/).filter(Boolean).length;
  totalWords += wordCount;
  totalSegments += 1;
  statWords.textContent = totalWords.toLocaleString();
  statSegments.textContent = totalSegments.toLocaleString();

  // Start timer on first transcription
  startSessionTimer();

  // Add transcript line
  const line = document.createElement("div");
  line.className = "transcript-line";
  line.textContent = text;
  transcriptContent.appendChild(line);

  const transcript = document.getElementById("transcript");
  transcript.scrollTop = transcript.scrollHeight;
}

// ============================================================
// Backend message handler
// ============================================================

window.listen.onMessage((msg) => {
  switch (msg.type) {
    case "state":
      handleState(msg);
      break;
    case "transcription":
      addTranscription(msg.text);
      break;
    case "model_loading":
      setStatus("loading", "Loading model...");
      break;
    case "model_loaded":
      modelLoaded = true;
      setStatus("ready", "Model loaded");
      window.listen.send({ action: "start" });
      break;
    case "status":
      setStatus("loading", msg.message);
      break;
    case "devices":
      populateDevices(msg.devices);
      break;
    case "error":
      setStatus("error", msg.message);
      break;
  }
});

function handleState(msg) {
  if (msg.mode) modeSelect.value = msg.mode;
  if (msg.hotkey) hotkeyInput.value = msg.hotkey;

  if (msg.state) {
    switch (msg.state) {
      case "idle":
        setStatus("loading", "Initializing...");
        window.listen.send({ action: "get_devices" });
        window.listen.send({ action: "download_model" });
        break;
      case "ready":
        setStatus("ready", "Ready");
        break;
      case "recording":
        setStatus("recording", "Recording...");
        break;
      case "listening":
        setStatus("listening", "Listening...");
        break;
      case "muted":
        setStatus("muted", "Muted");
        break;
      case "stopped":
        setStatus("ready", "Stopped");
        break;
      case "quit":
        setStatus("ready", "Disconnected");
        break;
    }
  }
}

// ============================================================
// Device dropdown
// ============================================================

function populateDevices(devices) {
  deviceSelect.innerHTML = '<option value="">System Default</option>';
  for (const dev of devices) {
    const option = document.createElement("option");
    option.value = dev.index;
    option.textContent = dev.name;
    deviceSelect.appendChild(option);
  }
}

// ============================================================
// Settings event listeners
// ============================================================

modeSelect.addEventListener("change", () => {
  window.listen.send({ action: "set_mode", mode: modeSelect.value });
});

hotkeyInput.addEventListener("click", () => {
  hotkeyInput.removeAttribute("readonly");
  hotkeyInput.value = "";
  hotkeyInput.placeholder = "Press a key combo...";
});

hotkeyInput.addEventListener("keydown", (e) => {
  e.preventDefault();
  const parts = [];
  if (e.ctrlKey) parts.push("ctrl");
  if (e.shiftKey) parts.push("shift");
  if (e.altKey) parts.push("alt");
  if (e.metaKey) parts.push("cmd");

  const key = e.key.toLowerCase();
  if (!["control", "shift", "alt", "meta"].includes(key)) {
    parts.push(key === " " ? "space" : key);
  }

  if (parts.length >= 2) {
    const hotkey = parts.join("+");
    hotkeyInput.value = hotkey;
    hotkeyInput.setAttribute("readonly", "");
    hotkeyInput.placeholder = "Press keys...";
    window.listen.updateHotkey(hotkey);
    hotkeyInput.blur();
  }
});

hotkeyInput.addEventListener("blur", () => {
  hotkeyInput.setAttribute("readonly", "");
  hotkeyInput.placeholder = "Press keys...";
});

deviceSelect.addEventListener("change", () => {
  const val = deviceSelect.value;
  const device = val === "" ? null : parseInt(val, 10);
  window.listen.send({ action: "set_device", device });

  if (modelLoaded) {
    window.listen.send({ action: "stop" });
    setTimeout(() => {
      window.listen.send({ action: "start" });
    }, 500);
  }
});
