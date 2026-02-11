// ============================================================
// DOM elements
// ============================================================

const menuBtn = document.getElementById("menu-btn");
const settingsBackdrop = document.getElementById("settings-backdrop");
const settingsPopover = document.getElementById("settings-popover");
const transcriptContent = document.getElementById("transcript-content");
const modeSelect = document.getElementById("mode-select");
const hotkeyInput = document.getElementById("hotkey-input");
const globeBtn = document.getElementById("globe-btn");
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
// Recording sounds (Web Audio API)
// ============================================================

const audioCtx = new (window.AudioContext || window.webkitAudioContext)();

function playTone(freq, duration, type = "sine", volume = 0.15) {
  const osc = audioCtx.createOscillator();
  const gain = audioCtx.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(freq, audioCtx.currentTime);
  gain.gain.setValueAtTime(volume, audioCtx.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + duration);
  osc.connect(gain);
  gain.connect(audioCtx.destination);
  osc.start();
  osc.stop(audioCtx.currentTime + duration);
}

function playStartSound() {
  // Two-tone ascending chime
  playTone(660, 0.12, "sine", 0.13);
  setTimeout(() => playTone(880, 0.15, "sine", 0.13), 80);
}

function playStopSound() {
  // Single descending tone
  playTone(440, 0.15, "sine", 0.1);
}

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
// Globe key button (macOS only)
// ============================================================

async function initGlobeButton() {
  const available = await window.listen.getGlobeAvailable();
  if (available) {
    globeBtn.classList.remove("hidden");
  }
}

globeBtn.addEventListener("click", () => {
  const isCurrentlyGlobe =
    hotkeyInput.value.toLowerCase() === "fn" ||
    hotkeyInput.value.toLowerCase() === "globe";

  if (isCurrentlyGlobe) {
    // Toggle off — revert to F5
    hotkeyInput.value = "F5";
    hotkeyInput.dataset.current = "F5";
    globeBtn.classList.remove("active");
    window.listen.updateHotkey("F5");
  } else {
    // Set to Globe key
    hotkeyInput.value = "fn";
    hotkeyInput.dataset.current = "fn";
    globeBtn.classList.add("active");
    window.listen.updateHotkey("fn");
  }
});

initGlobeButton();

// ============================================================
// Settings popover
// ============================================================

function openSettings() {
  settingsPopover.classList.remove("hidden");
  settingsBackdrop.classList.remove("hidden");
}

function closeSettings() {
  settingsPopover.classList.add("hidden");
  settingsBackdrop.classList.add("hidden");
}

menuBtn.addEventListener("click", () => {
  if (settingsPopover.classList.contains("hidden")) {
    openSettings();
  } else {
    closeSettings();
  }
});

settingsBackdrop.addEventListener("click", closeSettings);

// Close on Escape
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && !settingsPopover.classList.contains("hidden")) {
    closeSettings();
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
// State tracking (no visible status indicator)
// ============================================================

function setStatus(state) {
  const prevState = currentState;
  currentState = state;

  // Play sounds on recording/listening transitions
  if (
    (state === "recording" || state === "listening") &&
    prevState !== "recording" &&
    prevState !== "listening"
  ) {
    playStartSound();
  } else if (
    (state === "ready" || state === "muted" || state === "stopped") &&
    (prevState === "recording" || prevState === "listening")
  ) {
    playStopSound();
  }
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
      setStatus("loading");
      break;
    case "model_loaded":
      modelLoaded = true;
      setStatus("ready");
      window.listen.send({ action: "start" });
      break;
    case "status":
      setStatus("loading");
      break;
    case "devices":
      populateDevices(msg.devices);
      break;
    case "error":
      setStatus("error");
      break;
  }
});

function handleState(msg) {
  if (msg.mode) modeSelect.value = msg.mode;
  if (msg.hotkey) {
    hotkeyInput.value = msg.hotkey;
    hotkeyInput.dataset.current = msg.hotkey;
    const isGlobe =
      msg.hotkey.toLowerCase() === "fn" || msg.hotkey.toLowerCase() === "globe";
    globeBtn.classList.toggle("active", isGlobe);
  }

  if (msg.state) {
    switch (msg.state) {
      case "idle":
        setStatus("loading");
        window.listen.send({ action: "get_devices" });
        window.listen.send({ action: "download_model" });
        break;
      case "ready":
        setStatus("ready");
        break;
      case "recording":
        setStatus("recording");
        break;
      case "listening":
        setStatus("listening");
        break;
      case "muted":
        setStatus("muted");
        break;
      case "stopped":
        setStatus("ready");
        break;
      case "quit":
        setStatus("ready");
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

// Hotkey input — accepts ANY key press (single key or combo)
let hotkeyListening = false;

hotkeyInput.addEventListener("click", () => {
  hotkeyListening = true;
  hotkeyInput.removeAttribute("readonly");
  hotkeyInput.value = "";
  hotkeyInput.placeholder = "Press any key...";
});

hotkeyInput.addEventListener("keydown", (e) => {
  if (!hotkeyListening) return;
  e.preventDefault();
  e.stopPropagation();

  const parts = [];
  if (e.ctrlKey) parts.push("ctrl");
  if (e.shiftKey) parts.push("shift");
  if (e.altKey) parts.push("alt");
  if (e.metaKey) parts.push("cmd");

  const key = e.key;

  // Skip if only a modifier was pressed (wait for the actual key)
  if (["Control", "Shift", "Alt", "Meta"].includes(key)) {
    return;
  }

  // Normalize the key name
  let keyName;
  if (key === " ") {
    keyName = "space";
  } else if (key === "Escape") {
    // Cancel hotkey recording
    hotkeyListening = false;
    hotkeyInput.setAttribute("readonly", "");
    hotkeyInput.placeholder = "Click to set...";
    hotkeyInput.value = hotkeyInput.dataset.current || "";
    hotkeyInput.blur();
    return;
  } else {
    keyName = key.length === 1 ? key.toLowerCase() : key;
  }

  parts.push(keyName);
  const hotkey = parts.join("+");

  hotkeyListening = false;
  hotkeyInput.value = hotkey;
  hotkeyInput.dataset.current = hotkey;
  hotkeyInput.setAttribute("readonly", "");
  hotkeyInput.placeholder = "Click to set...";
  window.listen.updateHotkey(hotkey);
  hotkeyInput.blur();
});

hotkeyInput.addEventListener("blur", () => {
  if (hotkeyListening) {
    hotkeyListening = false;
    hotkeyInput.value = hotkeyInput.dataset.current || "";
  }
  hotkeyInput.setAttribute("readonly", "");
  hotkeyInput.placeholder = "Click to set...";
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
