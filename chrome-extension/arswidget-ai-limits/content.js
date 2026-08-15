// Читает с уже открытой страницы только видимые проценты остатка лимитов.
//
// Все сайты описаны одной таблицей SITES ниже: чтобы добавить сервис, нужна
// одна запись. Ничего, кроме процентов, со страницы не берётся.

const FIVE_HOUR = /(?:5\s*[- ]?\s*(?:hour|hours|час|часов|часа)|пятичас)/i;
const WEEKLY = /(?:week|weekly|недел)/i;
const MONTHLY = /(?:month|monthly|месяц)/i;
const CODEX = /codex/i;
const REMAINING = /(?:remaining|left|available|осталось|доступно|осталось лимита)/i;
const USED = /(?:used|consumed|использовано|потрачено|израсходовано)/i;
const CLAUDE_CURRENT_SESSION = /(?:current\s+session|текущ\S*\s+сесси)/i;
const CLAUDE_WEEKLY_LIMITS = /(?:weekly\s+limits?|недельн\S*\s+лимит)/i;
const CLAUDE_USAGE_CREDITS = /(?:usage\s+credits?|кредит\S*\s+использ)/i;

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

/// Один сервис — одна запись.
///   hosts    — на каких доменах работаем
///   isUsage  — похоже ли это на страницу лимитов (путь и хэш в нижнем регистре)
///   read     — записывает найденные проценты в usage
///
/// `ctx` в read: { value, context, captionContext, percentIndex }.
/// `context` захватывает и строку после числа — слово-признак и название
/// сервиса могут стоять с любой стороны. `captionContext` обрывается на числе,
/// потому что подпись лимита всегда стоит перед ним.
const SITES = [
  {
    key: "claude",
    hosts: ["claude.ai"],
    // Claude now opens this screen through /new#settings/usage for many
    // accounts, so checking only the old pathname silently skipped scans.
    isUsage: (path, hash) => path.startsWith("/settings/usage") || hash.includes("settings/usage"),
    read: (ctx, usage) => {
      // "Usage credits" is paid API credit usage, not a plan quota.
      if (CLAUDE_USAGE_CREDITS.test(ctx.context)) return;

      // Обе подписи могут попасть в одно окно текста; берём ближнюю слева,
      // иначе одно и то же число уходит сразу в обе строки.
      const toFiveHour = Math.min(
        distanceToCaptionBefore(FIVE_HOUR, ctx.captionContext, ctx.percentIndex) ?? Infinity,
        distanceToCaptionBefore(CLAUDE_CURRENT_SESSION, ctx.captionContext, ctx.percentIndex) ?? Infinity
      );
      const toWeekly = Math.min(
        distanceToCaptionBefore(WEEKLY, ctx.captionContext, ctx.percentIndex) ?? Infinity,
        distanceToCaptionBefore(CLAUDE_WEEKLY_LIMITS, ctx.captionContext, ctx.percentIndex) ?? Infinity
      );
      if (Number.isFinite(toFiveHour) && (!Number.isFinite(toWeekly) || toFiveHour <= toWeekly)) {
        usage.claudeFiveHourRemaining = ctx.value;
      } else if (Number.isFinite(toWeekly)) {
        usage.claudeWeeklyRemaining = ctx.value;
      }
    }
  },
  {
    key: "openai",
    hosts: ["chatgpt.com", "openai.com"],
    isUsage: (path, hash) =>
      path.includes("settings") || path.includes("codex") || hash.includes("settings"),
    read: (ctx, usage) => {
      // Codex и обычный ChatGPT живут в одних и тех же настройках аккаунта,
      // поэтому разделяем их по названию рядом с числом.
      if (CODEX.test(ctx.context)) {
        if (WEEKLY.test(ctx.context)) usage.codexWeeklyRemaining = ctx.value;
        return;
      }
      if (WEEKLY.test(ctx.context) || MONTHLY.test(ctx.context) || REMAINING.test(ctx.context)) {
        usage.chatgptRemaining = ctx.value;
      }
    }
  },
  {
    key: "deepseek",
    hosts: ["platform.deepseek.com"],
    isUsage: (path) => path.includes("usage"),
    read: () => {}
  },
  {
    key: "gemini",
    hosts: ["aistudio.google.com", "gemini.google.com"],
    isUsage: (path, hash) =>
      path.includes("usage") || hash.includes("usage") || path === "/" || path === "",
    read: (ctx, usage) => { usage.geminiRemaining = ctx.value; }
  },
  {
    key: "perplexity",
    hosts: ["perplexity.ai"],
    isUsage: (path) => path.includes("settings") || path.includes("account"),
    read: (ctx, usage) => { usage.perplexityRemaining = ctx.value; }
  },
  {
    key: "cursor",
    hosts: ["cursor.com", "cursor.sh"],
    isUsage: (path) => path.includes("dashboard") || path.includes("settings") || path.includes("usage"),
    read: (ctx, usage) => { usage.cursorRemaining = ctx.value; }
  },
  {
    key: "grok",
    hosts: ["grok.com"],
    isUsage: (path) => path.includes("settings") || path.includes("usage") || path.includes("subscription"),
    read: (ctx, usage) => { usage.grokRemaining = ctx.value; }
  }
];

function currentSite() {
  const host = location.hostname.toLowerCase();
  return SITES.find((site) => site.hosts.some((candidate) => host.includes(candidate))) ?? null;
}

function isUsagePage() {
  const site = currentSite();
  if (!site) return false;
  return Boolean(site.isUsage(location.pathname.toLowerCase(), location.hash.toLowerCase()));
}

/// Процент относится к своей строке, прочитанной вместе с парой строк выше.
function readPercentage(lines, index) {
  const line = lines[index];
  const match = line.match(/(\d{1,3}(?:[.,]\d+)?)\s*%/);
  if (!match) return null;

  const raw = Number(match[1].replace(",", "."));
  if (!Number.isFinite(raw) || raw < 0 || raw > 100) return null;

  // Current Claude labels are a few lines above the bar and percentage.
  const prefix = lines.slice(Math.max(0, index - 6), index).join(" ");
  const captionContext = prefix ? `${prefix} ${line}` : line;
  const percentIndex = (prefix ? prefix.length + 1 : 0) + match.index;
  const suffix = lines[index + 1] ?? "";
  const context = suffix ? `${captionContext} ${suffix}` : captionContext;

  // Страницы пишут либо «осталось», либо «использовано» — без одного из этих
  // слов число может означать что угодно, и мы его не берём.
  let value = null;
  if (REMAINING.test(context)) value = raw;
  else if (USED.test(context)) value = 100 - raw;
  if (value === null) return null;

  return { value, context, captionContext, percentIndex };
}

/// Расстояние от числа назад до ближайшей подписи, или null, если подписи
/// перед числом нет.
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
  const site = currentSite();
  if (!site || !isUsagePage()) return {};

  const text = document.body?.innerText?.slice(0, 20_000) ?? "";
  if (site.key === "deepseek") {
    const balance = readDeepSeekBalance(text);
    return balance === null ? {} : { deepseekBalanceUSD: balance };
  }
  const lines = text.split(/\n+/).map((line) => line.trim()).filter(Boolean);
  const usage = {};

  for (let index = 0; index < lines.length; index += 1) {
    const found = readPercentage(lines, index);
    if (found) site.read(found, usage);
  }

  return usage;
}

// DeepSeek shows prepaid API balance, not a plan percentage. Read only the
// dollar amount nearest the explicit balance label.
function readDeepSeekBalance(text) {
  const label = /topped[- ]up\s+balance/i;
  const match = label.exec(text);
  if (!match) return null;

  const area = text.slice(match.index, match.index + 700);
  const amount = area.match(/\$\s*([\d,]+(?:\.\d{1,2})?)/);
  if (!amount) return null;

  const value = Number(amount[1].replace(/,/g, ""));
  return Number.isFinite(value) && value >= 0 && value <= 1_000_000 ? value : null;
}

function send(message) {
  try {
    chrome.runtime.sendMessage(message)?.catch?.(() => {});
  } catch {
    // Расширение перезагрузили или обновили — канал этого кадра уже закрыт.
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

  // Раз в минуту повторяем даже неизменившиеся значения: виджет датирует
  // цифры последним реальным чтением, поэтому тишина должна означать, что
  // страницу больше не читают.
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
  // Похоже на страницу лимитов, но процентов не нашли за несколько проходов:
  // сменилась вёрстка или человек не залогинен. Отсрочка не даёт ещё
  // рисующейся странице поднять ложную тревогу — одних изменений DOM хватает,
  // чтобы за секунды исчерпать счётчик проходов.
  if (noDataNotified || emptyScans < EMPTY_SCANS_BEFORE_WARNING) return;
  if (Date.now() - openedAt < WARNING_GRACE_MS) return;
  noDataNotified = true;
  send({ type: "USAGE_PAGE_NO_DATA" });
}

function start() {
  // Согласие запоминается; страница ли это лимитов — проверяется на каждом
  // проходе, потому что эти сайты подменяют страницу без перезагрузки.
  if (isEnabled) return;
  isEnabled = true;
  scheduleReport();
}

/// Claude, ChatGPT, AI Studio и подобные — одностраничные приложения: заход на
/// сайт и переход в раздел лимитов меняет адрес без загрузки документа. Без
/// этого наблюдения расширение молчит у всех, кто пришёл не по прямой ссылке.
function watchForPageChanges() {
  let lastHref = location.href;
  window.setInterval(() => {
    if (location.href === lastHref) return;
    lastHref = location.href;
    emptyScans = 0;
    noDataNotified = false;
    lastUsage = "";
    scheduleReport();
  }, 1000);
}

try {
  chrome.runtime.sendMessage({ type: "GET_CONSENT" }, (response) => {
    void chrome.runtime.lastError;
    if (response?.enabled) start();
  });
} catch {
  // Без живого контекста расширения делать нечего.
}

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === "USAGE_ENABLED") start();
});

new MutationObserver(scheduleReport).observe(document.documentElement, {
  childList: true,
  subtree: true,
  characterData: true
});
// Периодический пересчёт, чтобы заметить разлогин или смену вёрстки даже на
// статичной странице.
window.setInterval(reportUsage, 30_000);
watchForPageChanges();
