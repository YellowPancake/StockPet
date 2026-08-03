"use strict";

const { contextBridge, ipcRenderer } = require("electron");

const eventChannels = new Set([
  "state-changed",
  "quotes-updated",
  "stock-alert",
  "alert-dismiss",
  "refresh-status",
  "update-download-progress",
]);

contextBridge.exposeInMainWorld("stockPet", {
  bootstrap: () => ipcRenderer.invoke("bootstrap"),
  updateState: (patch) => ipcRenderer.invoke("state:update", patch),
  search: (query) => ipcRenderer.invoke("stocks:search", query),
  addSymbol: (symbol) => ipcRenderer.invoke("stocks:add", symbol),
  removeSymbol: (quoteID) => ipcRenderer.invoke("stocks:remove", quoteID),
  moveSymbol: (quoteID, direction) => ipcRenderer.invoke("stocks:move", quoteID, direction),
  refresh: () => ipcRenderer.invoke("quotes:refresh"),
  previewAlert: (direction) => ipcRenderer.invoke("alert:preview", direction),
  openSettings: () => ipcRenderer.invoke("settings:open"),
  openAuthor: () => ipcRenderer.invoke("external:open-author"),
  checkForUpdate: () => ipcRenderer.invoke("update:check"),
  downloadUpdate: (route) => ipcRenderer.invoke("update:download", route),
  showOverlay: () => ipcRenderer.invoke("overlay:show"),
  beginWindowDrag: (x, y) => ipcRenderer.send("overlay:drag-start", { x, y }),
  dragWindow: (x, y) => ipcRenderer.send("overlay:drag-move", { x, y }),
  endWindowDrag: () => ipcRenderer.send("overlay:drag-end"),
  on: (channel, callback) => {
    if (!eventChannels.has(channel)) return () => {};
    const listener = (_event, value) => callback(value);
    ipcRenderer.on(channel, listener);
    return () => ipcRenderer.removeListener(channel, listener);
  },
});
