const FIVE_HOUR = /(?:5\s*[- ]?\s*(?:hour|hours|час|часов|часа)|пятичас)/i;
const WEEKLY = /(?:week|weekly|недел)/i;
const CODEX = /codex/i;
const DEEPSEEK = /deepseek/i;
const GEMINI = /gemini/i;
const REMAINING = /(?:remaining|left|available|осталось|доступно|осталось лимита)/i;
const USED = /(?:used|consumed|использовано|потрачено|израсходовано)/i;
let lastUsage = "";
let scheduled = false;
let isEnabled = false;
let emptyScans = 0;
let noDataNotified = false;

function isUsagePage() {
  const path = location.pathname.toLowerCase();
  const hash = location.hash.toLowerCase();

  if (location.hostname.includes("claude.ai")) {
    return path.startsWith("/settings/usage");
  }

  if (location.hostname.includes("platform.deepseek.com")) {
    return path.includes("usage");
  }

  if (location.hostname.includes("aistudio.google.com")) {
    return true;
  }

  if (location.hostname.includes("gemini.google.com")) {
    return path.includes("usage") || hash.includes("usage");
  }

  return path.includes("settings") || path.includes("codex") || hash.includes("settings");
}

function percentageFrom(context) {
  const match = context.match(/(\d{1,3}(?:[.,]\d+)?)\s*%/);
  if (!match) return null;

  const value = Number(match[1].replace(",", "."));
  if (!Number.isFinite(value) || value < 0 || value > 100) return null;
  if (REMAINING.test(context)) return value;
  if (USED.test(context)) return 100 - value;
  return null;
}

function detectUsage() {
  if (!isUsagePage()) return {};

  const text = document.body?.innerText?.slice(0, 20_000) ?? "";
  const lines = text.split(/\n+/).map((line) => line.trim()).filter(Boolean);
  const usage = {};

  for (let index = 0; index < lines.length; index += 1) {
    const context = lines.slice(Math.max(0, index - 1), index + 2).join(" ");
    const percent = percentageFrom(context);
    if (percent === null) continue;

    if (location.hostname.includes("claude.ai")) {
      if (FIVE_HOUR.test(context)) usage.claudeFiveHourRemaining = percent;
      if (WEEKLY.test(context)) usage.claudeWeeklyRemaining = percent;
    }

    if ((location.hostname.includes("chatgpt.com") || location.hostname.includes("openai.com"))
      && CODEX.test(context) && WEEKLY.test(context)) {
      usage.codexWeeklyRemaining = percent;
    }

    if (location.hostname.includes("platform.deepseek.com")
      && (REMAINING.test(context) || DEEPSEEK.test(context))) {
      usage.deepseekRemaining = percent;
    }

    if ((location.hostname.includes("aistudio.google.com") || location.hostname.includes("gemini.google.com"))
      && (REMAINING.test(context) || GEMINI.test(context))) {
      usage.geminiRemaining = percent;
    }
  }

  return usage;
}

function reportUsage() {
  scheduled = false;
  if (!isEnabled) return;
  const usage = detectUsage();
  const serialized = JSON.stringify(usage);
  if (serialized === "{}" && isUsagePage()) {
    emptyScans += 1;
  }
  if (serialized === lastUsage || serialized === "{}") return;

  lastUsage = serialized;
  chrome.runtime.sendMessage({ type: "USAGE_FOUND", usage });
}

function scheduleReport() {
  if (scheduled) return;
  scheduled = true;
  window.setTimeout(reportUsage, 900);
}

function noteNoDataIfNeeded() {
  // The page looks like a usage page, but no percentages were found after a
  // few scans — the layout may have changed or the user may be logged out.
  if (noDataNotified || emptyScans < 6) return;
  noDataNotified = true;
  chrome.runtime.sendMessage({ type: "USAGE_PAGE_NO_DATA" });
}

function start() {
  if (isEnabled || !isUsagePage()) return;
  isEnabled = true;
  scheduleReport();
  if (isUsagePage()) {
    window.setTimeout(noteNoDataIfNeeded, 12_000);
  }
}

chrome.runtime.sendMessage({ type: "GET_CONSENT" }, (response) => {
  if (response?.enabled) start();
});

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === "USAGE_ENABLED") start();
});

if (isUsagePage()) {
  new MutationObserver(scheduleReport).observe(document.documentElement, {
    childList: true,
    subtree: true,
    characterData: true
  });
  // Periodic re-scan so login/layout issues are detected even on static pages.
  window.setInterval(reportUsage, 60_000);
}
