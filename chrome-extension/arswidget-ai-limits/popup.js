const keys = [
  ["codexWeeklyRemaining", "Codex, неделя"],
  ["claudeFiveHourRemaining", "Claude, 5 часов"],
  ["claudeWeeklyRemaining", "Claude, неделя"]
];

async function render() {
  const { arsWidgetUsage = {}, arsWidgetBridgeStatus = {}, arsWidgetUsageConsent = false } = await chrome.storage.local.get([
    "arsWidgetUsage", "arsWidgetBridgeStatus", "arsWidgetUsageConsent"
  ]);
  const rows = keys.filter(([key]) => Number.isFinite(arsWidgetUsage[key]));
  const status = document.querySelector("#status");
  const limits = document.querySelector("#limits");

  document.querySelector("#consent").hidden = arsWidgetUsageConsent;
  document.querySelector("#disable").hidden = !arsWidgetUsageConsent;

  status.textContent = !arsWidgetUsageConsent
    ? "Сначала подтверди показ лимитов."
    : arsWidgetBridgeStatus.connected
    ? "ArsWidget подключён. Последние найденные значения:"
    : "Запусти ArsWidget, затем открой страницы лимитов.";

  if (rows.length) {
    limits.hidden = false;
    limits.replaceChildren(...rows.map(([key, title]) => {
      const row = document.createElement("div");
      row.className = "limit";
      row.innerHTML = `<span>${title}</span><strong>${Math.round(arsWidgetUsage[key])}%</strong>`;
      return row;
    }));
  }
}

document.querySelector("#enable").addEventListener("click", async () => {
  await chrome.storage.local.set({ arsWidgetUsageConsent: true });
  render();
});

document.querySelector("#disable").addEventListener("click", async () => {
  await chrome.storage.local.set({ arsWidgetUsageConsent: false });
  render();
});

document.querySelector("#openClaude").addEventListener("click", () => {
  chrome.tabs.create({ url: "https://claude.ai/settings/usage" });
});

document.querySelector("#openCodex").addEventListener("click", () => {
  chrome.tabs.create({ url: "https://chatgpt.com/#settings/Account" });
});

render();
