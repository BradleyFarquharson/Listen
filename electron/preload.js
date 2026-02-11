const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("listen", {
  send: (msg) => ipcRenderer.send("send-command", msg),
  updateHotkey: (hotkey) => ipcRenderer.send("update-hotkey", hotkey),
  onMessage: (callback) =>
    ipcRenderer.on("backend-message", (_event, msg) => callback(msg)),
});
