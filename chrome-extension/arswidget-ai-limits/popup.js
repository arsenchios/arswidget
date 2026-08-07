const METRICS = [
  { key: "codexWeeklyRemaining", title: "Codex, неделя", provider: "Codex" },
  { key: "claudeFiveHourRemaining", title: "Claude, 5 часов", provider: "Claude" },
  { key: "claudeWeeklyRemaining", title: "Claude, неделя", provider: "Claude" },
  { key: "deepseekRemaining", title: "DeepSeek", provider: "DeepSeek" },
  { key: "geminiRemaining", title: "Gemini", provider: "Gemini" }
];

function ageText(timestamp) {
  if (!Number.isFinite(timestamp)) return "";
  const seconds = Math.max(0, (Date.now() - timestamp) / 1000);
  if (seconds < 90) return "обновлено только что";
  if (seconds < 3600) return `обновлено ${Math.round(seconds / 60)} мин назад`;
  if (seconds < 86400) return `обновлено ${Math.round(seconds / 3600)} ч назад`;
  return "значения давно не обновлялись";
}

async function render() {
  const {
    arsWidgetUsage = {},
    arsWidgetBridgeStatus = {},
    arsWidgetUsageConsent = false
  } = await chrome.storage.local.get(["arsWidgetUsage", "arsWidgetBridgeStatus", "arsWidgetUsageConsent"]);

  const status = document.querySelector("#status");
  const limits = document.querySelector("#limits");
  const missing = document.querySelector("#missing");
  const freshness = document.querySelector("#freshness");
  const rows = METRICS.filter(({ key }) => Number.isFinite(arsWidgetUsage[key]));

  document.querySelector("#consent").hidden = arsWidgetUsageConsent;
  document.querySelector("#disable").hidden = !arsWidgetUsageConsent;

  status.textContent = !arsWidgetUsageConsent
    ? "Сначала подтверди показ лимитов."
    : arsWidgetBridgeStatus.connected
    ? "ArsWidget подключён."
    : "Запусти ArsWidget, затем открой страницы лимитов.";

  limits.replaceChildren(...rows.map(({ key, title }) => {
    const row = document.createElement("div");
    row.className = "limit";

    const name = document.createElement("span");
    name.textContent = title;

    const value = document.createElement("strong");
    value.textContent = `${Math.round(arsWidgetUsage[key])}%`;

    row.append(name, value);
    return row;
  }));
  // Without this the last known rows stayed on screen after the data was gone.
  limits.hidden = rows.length === 0;

  const text = rows.length ? ageText(arsWidgetUsage.updatedAt) : "";
  freshness.textContent = text;
  freshness.hidden = !text;

  const missingNames = [...new Set(
    METRICS.filter(({ key }) => !Number.isFinite(arsWidgetUsage[key])).map(({ provider }) => provider)
  )].filter((provider) => !rows.some((row) => row.provider === provider));

  missing.textContent = missingNames.length
    ? `Ещё можно подключить: ${missingNames.join(", ")}. Открой нужную страницу лимитов.`
    : "";
  missing.hidden = !missingNames.length;
}

document.querySelector("#enable").addEventListener("click", async () => {
  await chrome.storage.local.set({ arsWidgetUsageConsent: true });
  // Tabs already open must start reporting without a manual reload.
  chrome.runtime.sendMessage({ type: "RESEND" }).catch(() => {});
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

document.querySelector("#openDeepSeek").addEventListener("click", () => {
  chrome.tabs.create({ url: "https://platform.deepseek.com/usage" });
});

document.querySelector("#openGemini").addEventListener("click", () => {
  chrome.tabs.create({ url: "https://aistudio.google.com/" });
});

document.querySelector("#refresh").addEventListener("click", () => {
  chrome.runtime.sendMessage({ type: "RESEND" }).catch(() => {});
  window.setTimeout(render, 500);
});

// Values can land while the popup is open.
chrome.storage.onChanged.addListener((_changes, area) => {
  if (area === "local") render();
});

render();
