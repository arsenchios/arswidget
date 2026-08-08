const FIVE_HOUR = /(?:5\s*[- ]?\s*(?:hour|hours|час|часов|часа)|пятичас)/i;
const WEEKLY = /(?:week|weekly|недел)/i;
const CODEX = /codex/i;
const DEEPSEEK = /deepseek/i;
const GEMINI = /gemini/i;
const REMAINING = /(?:remaining|left|available|осталось|доступно|осталось лимита)/i;
const USED = /(?:used|consumed|использовано|потрачено|израсходовано)/i;
const HEARTBEAT_MS = 55_000;
const EMPTY_SCANS_BEFORE_WARNING = 6;
const WARNING_GRACE_MS = 20_000;

const openedAt = Date.now();

let lastUsage = "";
let lastReportAt = 0;
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

/// A percentage is read from the line it sits on, with two contexts around it.
///
/// `context` also covers the following line, because "remaining"/"used" and a
/// vendor name may sit on either side of the number — that is how the previous
/// version worked and it must keep working.
///
/// `captionContext` stops at the number, because the limit captions do not:
/// "5-hour" and "weekly" both landing in one window is exactly what used to
/// copy a single value into both Claude rows.
function readPercentage(lines, index) {
  const line = lines[index];
  const match = line.match(/(\d{1,3}(?:[.,]\d+)?)\s*%/);
  if (!match) return null;

  const value = Number(match[1].replace(",", "."));
  if (!Number.isFinite(value) || value < 0 || value > 100) return null;

  const prefix = lines.slice(Math.max(0, index - 2), index).join(" ");
  const captionContext = prefix ? `${prefix} ${line}` : line;
  const percentIndex = (prefix ? prefix.length + 1 : 0) + match.index;
  const suffix = lines[index + 1] ?? "";
  const context = suffix ? `${captionContext} ${suffix}` : captionContext;

  let remaining = null;
  if (REMAINING.test(context)) remaining = value;
  else if (USED.test(context)) remaining = 100 - value;
  if (remaining === null) return null;

  return { remaining, context, captionContext, percentIndex };
}

/// Distance from the percentage back to the nearest caption before it, or null
/// when that caption does not appear ahead of the number at all.
function distanceToCaptionBefore(pattern, context, percentIndex) {
  const scanner = new RegExp(pattern.source, `${pattern.flags.replace("g", "")}g`);
  let best = null;
  let match;

  while ((match = scanner.exec(context)) !== null) {
    if (match.index < percentIndex) {
      const distance = percentIndex - match.index;
      if (best === null || distance < best) best = distance;
    }
    if (match.index === scanner.lastIndex) scanner.lastIndex += 1;
  }

  return best;
}

function detectUsage() {
  if (!isUsagePage()) return {};

  const text = document.body?.innerText?.slice(0, 20_000) ?? "";
  const lines = text.split(/\n+/).map((line) => line.trim()).filter(Boolean);
  const usage = {};

  for (let index = 0; index < lines.length; index += 1) {
    const found = readPercentage(lines, index);
    if (!found) continue;

    const { remaining, context, captionContext, percentIndex } = found;

    if (location.hostname.includes("claude.ai")) {
      // Both windows can be named above the same number; keep the nearer one
      // instead of writing the value into both rows.
      const toFiveHour = distanceToCaptionBefore(FIVE_HOUR, captionContext, percentIndex);
      const toWeekly = distanceToCaptionBefore(WEEKLY, captionContext, percentIndex);

      if (toFiveHour !== null && (toWeekly === null || toFiveHour <= toWeekly)) {
        usage.claudeFiveHourRemaining = remaining;
      } else if (toWeekly !== null) {
        usage.claudeWeeklyRemaining = remaining;
      }
    }

    if ((location.hostname.includes("chatgpt.com") || location.hostname.includes("openai.com"))
      && CODEX.test(context) && WEEKLY.test(context)) {
      usage.codexWeeklyRemaining = remaining;
    }

    if (location.hostname.includes("platform.deepseek.com")
      && (REMAINING.test(context) || DEEPSEEK.test(context))) {
      usage.deepseekRemaining = remaining;
    }

    if ((location.hostname.includes("aistudio.google.com") || location.hostname.includes("gemini.google.com"))
      && (REMAINING.test(context) || GEMINI.test(context))) {
      usage.geminiRemaining = remaining;
    }
  }

  return usage;
}

function send(message) {
  try {
    chrome.runtime.sendMessage(message)?.catch?.(() => {});
  } catch {
    // The extension was reloaded or updated; this frame's port is gone.
  }
}

function reportUsage() {
  scheduled = false;
  if (!isEnabled) return;

  const usage = detectUsage();
  const serialized = JSON.stringify(usage);

  if (serialized === "{}") {
    if (isUsagePage()) {
      emptyScans += 1;
      noteNoDataIfNeeded();
    }
    return;
  }

  emptyScans = 0;
  noDataNotified = false;

  // Re-send unchanged values about once a minute: the widget dates the numbers
  // by their last real read, so silence has to mean "no longer being read".
  const now = Date.now();
  if (serialized === lastUsage && now - lastReportAt < HEARTBEAT_MS) return;

  lastUsage = serialized;
  lastReportAt = now;
  send({ type: "USAGE_FOUND", usage });
}

function scheduleReport() {
  if (scheduled) return;
  scheduled = true;
  window.setTimeout(reportUsage, 900);
}

function noteNoDataIfNeeded() {
  // The page looks like a usage page, but no percentages were found after a
  // few scans — the layout may have changed or the user may be logged out.
  // The grace period keeps a still-rendering page from raising a false alarm,
  // since DOM mutations alone can burn through the scan count in seconds.
  if (noDataNotified || emptyScans < EMPTY_SCANS_BEFORE_WARNING) return;
  if (Date.now() - openedAt < WARNING_GRACE_MS) return;
  noDataNotified = true;
  send({ type: "USAGE_PAGE_NO_DATA" });
}

function start() {
  if (isEnabled || !isUsagePage()) return;
  isEnabled = true;
  scheduleReport();
}

try {
  chrome.runtime.sendMessage({ type: "GET_CONSENT" }, (response) => {
    void chrome.runtime.lastError;
    if (response?.enabled) start();
  });
} catch {
  // Nothing to do without a live extension context.
}

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
  window.setInterval(reportUsage, 30_000);
}
