const BRIDGE_URL = "http://127.0.0.1:63554/v1/ai-usage";
const USAGE_KEY = "arsWidgetUsage";
const STATUS_KEY = "arsWidgetBridgeStatus";
const CONSENT_KEY = "arsWidgetUsageConsent";
const NOTIFY_KEY = "arsWidgetNotifyState";
const RESEND_ALARM = "resendUsage";
// Совпадает с content_scripts в манифесте: расходиться им нельзя.
const TRACKED_URLS = chrome.runtime.getManifest().content_scripts[0].matches;
const NOTIFY_COOLDOWN_MS = 15 * 60 * 1000;
// Единственные поля, которые уходят в приложение. Всё остальное отбрасывается.
const PERCENT_KEYS = [
  "codexWeeklyRemaining",
  "chatgptRemaining",
  "claudeFiveHourRemaining",
  "claudeWeeklyRemaining",
  "geminiRemaining",
  "perplexityRemaining",
  "cursorRemaining",
  "grokRemaining"
];
const BALANCE_KEYS = ["deepseekBalanceUSD"];

// A service worker is torn down after a few idle seconds, so anything the
// throttling logic needs to remember has to live in storage, not in module
// scope — otherwise every counter restarts at zero on the next wake-up.
async function readNotifyState() {
  const { [NOTIFY_KEY]: state = {} } = await chrome.storage.local.get(NOTIFY_KEY);
  return {
    consecutiveFailures: state.consecutiveFailures ?? 0,
    lastFailureAt: state.lastFailureAt ?? 0,
    lastNoDataAt: state.lastNoDataAt ?? 0
  };
}

async function writeNotifyState(patch) {
  const state = await readNotifyState();
  await chrome.storage.local.set({ [NOTIFY_KEY]: { ...state, ...patch } });
}

async function ensureAlarm() {
  const existing = await chrome.alarms.get(RESEND_ALARM);
  if (!existing) {
    chrome.alarms.create(RESEND_ALARM, { periodInMinutes: 1 });
  }
}

chrome.runtime.onInstalled.addListener(async () => {
  // The alarm is created first: if setAccessLevel is unavailable in this
  // Chrome build it must not take the periodic resend down with it.
  await ensureAlarm();
  try {
    await chrome.storage.local.setAccessLevel({ accessLevel: "TRUSTED_CONTEXTS" });
  } catch {
    // Default access level already excludes untrusted contexts.
  }
});

chrome.runtime.onStartup.addListener(ensureAlarm);

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "GET_CONSENT") {
    chrome.storage.local.get(CONSENT_KEY)
      .then(({ [CONSENT_KEY]: enabled = false }) => sendResponse({ enabled }))
      .catch(() => sendResponse({ enabled: false }));
    return true;
  }

  if (message?.type === "RESEND") {
    ensureAlarm();
    chrome.storage.local.get(USAGE_KEY)
      .then(({ [USAGE_KEY]: usage = {} }) => sendUsage(usage))
      .then((ok) => sendResponse({ ok }))
      .catch(() => sendResponse({ ok: false }));
    wakeContentScripts();
    return true;
  }

  if (message?.type === "USAGE_PAGE_NO_DATA") {
    notifyNoData();
    return;
  }

  if (message?.type !== "USAGE_FOUND") return;

  chrome.storage.local.get(CONSENT_KEY)
    .then(({ [CONSENT_KEY]: enabled = false }) => {
      if (!enabled) return false;
      return mergeUsage(message.usage).then(sendUsage);
    })
    .then((ok) => sendResponse({ ok }))
    .catch(() => sendResponse({ ok: false }));
  return true;
});

async function wakeContentScripts() {
  const tabs = await chrome.tabs.query({});
  for (const tab of tabs) {
    if (typeof tab.id !== "number") continue;
    chrome.tabs.sendMessage(tab.id, { type: "USAGE_ENABLED" }).catch(() => {});
  }
}

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name !== RESEND_ALARM) return;
  const { [USAGE_KEY]: usage = {}, [CONSENT_KEY]: enabled = false } = await chrome.storage.local.get([USAGE_KEY, CONSENT_KEY]);
  if (!enabled) return;
  // Сначала просим страницы перечитать себя, потом отправляем.
  // Свои таймеры у фоновой вкладки Chrome придушивает вплоть до полной
  // остановки, поэтому возраст значений рос до часа, хотя вкладка открыта.
  // Будильник расширения не придушивается, а доставка сообщений будит вкладку.
  await rescanOpenTabs();
  await sendUsage(usage);
});

/// Просит все подходящие вкладки перечитать страницу.
async function rescanOpenTabs() {
  let tabs = [];
  try {
    tabs = await chrome.tabs.query({ url: TRACKED_URLS });
  } catch {
    return;
  }
  await Promise.all(tabs.map((tab) => {
    if (typeof tab.id !== "number") return Promise.resolve();
    return chrome.tabs.sendMessage(tab.id, { type: "RESCAN" }).catch(() => {});
  }));
}

async function mergeUsage(candidate) {
  const values = pickUsageValues(candidate);
  const { [USAGE_KEY]: current = {} } = await chrome.storage.local.get(USAGE_KEY);
  if (Object.keys(values).length === 0) return current;

  const merged = {
    ...current,
    ...values,
    // When a page was last really read. The widget shows the age of this, so
    // values left over from a closed tab stop looking fresh.
    updatedAt: Date.now()
  };
  await chrome.storage.local.set({ [USAGE_KEY]: merged });
  return merged;
}

function pickUsageValues(value = {}) {
  const result = {};
  for (const key of PERCENT_KEYS) {
    if (Number.isFinite(value[key]) && value[key] >= 0 && value[key] <= 100) {
      result[key] = Math.round(value[key] * 10) / 10;
    }
  }
  for (const key of BALANCE_KEYS) {
    if (Number.isFinite(value[key]) && value[key] >= 0 && value[key] <= 1_000_000) {
      result[key] = Math.round(value[key] * 100) / 100;
    }
  }
  return result;
}

async function notifyFailure() {
  const state = await readNotifyState();
  const consecutiveFailures = state.consecutiveFailures + 1;
  await writeNotifyState({ consecutiveFailures });

  if (consecutiveFailures < 3 || Date.now() - state.lastFailureAt < NOTIFY_COOLDOWN_MS) return;
  await writeNotifyState({ lastFailureAt: Date.now() });
  chrome.notifications.create({
    type: "basic",
    iconUrl: "icons/icon-128.png",
    title: "ArsWidget не отвечает",
    message: "Запусти ArsWidget на этом Mac, чтобы лимиты продолжали передаваться. Вкладки лимитов можно закрепить."
  });
}

async function notifyNoData() {
  const state = await readNotifyState();
  if (Date.now() - state.lastNoDataAt < NOTIFY_COOLDOWN_MS) return;
  await writeNotifyState({ lastNoDataAt: Date.now() });
  chrome.notifications.create({
    type: "basic",
    iconUrl: "icons/icon-128.png",
    title: "Страница лимитов изменилась",
    message: "Расширение не находит проценты на открытой странице. Проверь, что ты залогинен, или обнови страницу."
  });
}

async function sendUsage(usage = {}) {
  const payload = pickUsageValues(usage);
  if (Object.keys(payload).length === 0) return false;
  if (Number.isFinite(usage.updatedAt)) {
    payload.capturedAt = usage.updatedAt;
  }

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
    if (ok) {
      await writeNotifyState({ consecutiveFailures: 0 });
    } else {
      await notifyFailure();
    }
    return ok;
  } catch {
    await chrome.storage.local.set({
      [STATUS_KEY]: { connected: false, updatedAt: Date.now() }
    });
    await notifyFailure();
    return false;
  }
}
