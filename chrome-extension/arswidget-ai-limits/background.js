const BRIDGE_URL = "http://127.0.0.1:63554/v1/ai-usage";
const USAGE_KEY = "arsWidgetUsage";
const STATUS_KEY = "arsWidgetBridgeStatus";
const CONSENT_KEY = "arsWidgetUsageConsent";

chrome.runtime.onInstalled.addListener(async () => {
  await chrome.storage.local.setAccessLevel({ accessLevel: "TRUSTED_CONTEXTS" });
  chrome.alarms.create("resendUsage", { periodInMinutes: 1 });
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "GET_CONSENT") {
    chrome.storage.local.get(CONSENT_KEY)
      .then(({ [CONSENT_KEY]: enabled = false }) => sendResponse({ enabled }));
    return true;
  }

  if (message?.type !== "USAGE_FOUND") return;

  mergeUsage(message.usage)
    .then(sendUsage)
    .then((ok) => sendResponse({ ok }))
    .catch(() => sendResponse({ ok: false }));
  return true;
});

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name !== "resendUsage") return;
  const { [USAGE_KEY]: usage = {}, [CONSENT_KEY]: enabled = false } = await chrome.storage.local.get([USAGE_KEY, CONSENT_KEY]);
  if (!enabled) return;
  await sendUsage(usage);
});

async function mergeUsage(candidate) {
  const { [USAGE_KEY]: current = {} } = await chrome.storage.local.get(USAGE_KEY);
  const merged = {
    ...current,
    ...pickPercentages(candidate),
    updatedAt: Date.now()
  };
  await chrome.storage.local.set({ [USAGE_KEY]: merged });
  return merged;
}

function pickPercentages(value = {}) {
  const result = {};
  for (const key of [
    "codexWeeklyRemaining",
    "claudeFiveHourRemaining",
    "claudeWeeklyRemaining"
  ]) {
    if (Number.isFinite(value[key]) && value[key] >= 0 && value[key] <= 100) {
      result[key] = Math.round(value[key] * 10) / 10;
    }
  }
  return result;
}

async function sendUsage(usage = {}) {
  const payload = pickPercentages(usage);
  if (Object.keys(payload).length === 0) return false;

  try {
    const response = await fetch(BRIDGE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    const ok = response.ok;
    await chrome.storage.local.set({
      [STATUS_KEY]: { connected: ok, updatedAt: Date.now() }
    });
    return ok;
  } catch {
    await chrome.storage.local.set({
      [STATUS_KEY]: { connected: false, updatedAt: Date.now() }
    });
    return false;
  }
}
