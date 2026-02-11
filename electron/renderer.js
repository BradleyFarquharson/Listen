// DOM elements
const statusDot = document.getElementById("status-dot");
const statusText = document.getElementById("status-text");
const transcriptContent = document.getElementById("transcript-content");
const modeSelect = document.getElementById("mode-select");
const hotkeyInput = document.getElementById("hotkey-input");
const deviceSelect = document.getElementById("device-select");

let modelLoaded = false;

// Show empty state
function showEmptyState() {
  if (transcriptContent.children.length === 0) {
    transcriptContent.innerHTML =
      '<div class="empty-state">Transcriptions will appear here</div>';
  }
}
showEmptyState();

// Update status display
function setStatus(state, text) {
  statusDot.className = "";
  statusDot.classList.add(state);
  statusText.textContent = text;
}

// Add transcription line
function addTranscription(text) {
  // Remove empty state
  const empty = transcriptContent.querySelector(".empty-state");
  if (empty) empty.remove();

  const line = document.createElement("div");
  line.className = "transcript-line";
  line.textContent = text;
  transcriptContent.appendChild(line);

  // Auto-scroll
  const transcript = document.getElementById("transcript");
  transcript.scrollTop = transcript.scrollHeight;
}

// Handle messages from Python backend
window.listen.onMessage((msg) => {
  switch (msg.type) {
    case "state":
      handleState(msg);
      break;

    case "transcription":
      addTranscription(msg.text);
      break;

    case "model_loading":
      setStatus("loading", `Loading model: ${msg.model}...`);
      break;

    case "model_loaded":
      modelLoaded = true;
      setStatus("ready", "Model loaded \u2014 starting...");
      // Auto-start capture after model loads
      window.listen.send({ action: "start" });
      break;

    case "status":
      setStatus("loading", msg.message);
      break;

    case "devices":
      populateDevices(msg.devices);
      break;

    case "error":
      setStatus("error", `Error: ${msg.message}`);
      console.error("Backend error:", msg.message);
      break;
  }
});

function handleState(msg) {
  // Update mode selector
  if (msg.mode) {
    modeSelect.value = msg.mode;
  }

  // Update hotkey display
  if (msg.hotkey) {
    hotkeyInput.value = msg.hotkey;
  }

  // Update status
  if (msg.state) {
    switch (msg.state) {
      case "idle":
        setStatus("loading", "Initializing...");
        // Request devices and start model download
        window.listen.send({ action: "get_devices" });
        window.listen.send({ action: "download_model" });
        break;
      case "ready":
        setStatus("ready", "Ready \u2014 tap hotkey to record");
        break;
      case "recording":
        setStatus("recording", "Recording...");
        break;
      case "listening":
        setStatus("listening", "Listening...");
        break;
      case "muted":
        setStatus("muted", "Muted \u2014 tap hotkey to unmute");
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

// Populate device dropdown
function populateDevices(devices) {
  // Keep "System Default" as first option
  deviceSelect.innerHTML = '<option value="">System Default</option>';

  for (const dev of devices) {
    const option = document.createElement("option");
    option.value = dev.index;
    option.textContent = dev.name;
    deviceSelect.appendChild(option);
  }
}

// Settings event listeners
modeSelect.addEventListener("change", () => {
  window.listen.send({ action: "set_mode", mode: modeSelect.value });
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
    window.listen.updateHotkey(hotkey);
    hotkeyInput.blur();
  }
});

deviceSelect.addEventListener("change", () => {
  const val = deviceSelect.value;
  const device = val === "" ? null : parseInt(val, 10);
  window.listen.send({ action: "set_device", device });

  // Restart capture with new device if running
  if (modelLoaded) {
    window.listen.send({ action: "stop" });
    setTimeout(() => {
      window.listen.send({ action: "start" });
    }, 500);
  }
});
