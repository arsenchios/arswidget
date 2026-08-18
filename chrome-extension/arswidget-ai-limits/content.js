// Читает с уже открытой страницы только видимые проценты остатка лимитов.
//
// Все сайты описаны одной таблицей SITES ниже: чтобы добавить сервис, нужна
// одна запись. Ничего, кроме процентов, со страницы не берётся.

const FIVE_HOUR = /(?:5\s*[- ]?\s*(?:hour|hours|час|часов|часа)|пятичас)/i;
const WEEKLY = /(?:week|weekly|недел)/i;
const MONTHLY = /(?:month|monthly|месяц)/i;
const CODEX = /codex/i;
const CHATGPT = /chat\s?gpt/i;
const REMAINING = /(?:remaining|left|available|осталось|доступно|залишилось)/i;
const USED = /(?:used|consumed|spent|использован\S*|израсходован\S*|потрачен\S*|витрачен\S*)/i;
// Ни «осталось», ни «использовано» на странице нет — но это явно счётчик
// лимита. Такие числа берём как приблизительные, а не выбрасываем.
const LIMIT_HINT = /(?:limit|quota|resets?|session|лимит|квота|сброс|сесси)/i;
const CLAUDE_CURRENT_SESSION = /(?:current\s+session|текущ\S*\s+сесси)/i;
const CLAUDE_WEEKLY_LIMITS = /(?:weekly\s+limits?|недельн\S*\s+лимит)/i;
const CLAUDE_USAGE_CREDITS = /(?:usage\s+credits?|кредит\S*\s+использ)/i;
// Кнопка «обновить» на самой странице лимитов. Слово должно стоять отдельно, а
// подпись — быть короткой: «Update plan», «Upgrade» и всё, что уводит на
// оплату, нажимать нельзя ни при каких условиях.
const REFRESH_LABEL = /(?:^|\s)(?:refresh|reload|обновить|обновление|оновити)(?:\s|$)/i;
const REFRESH_FORBIDDEN = /(?:plan|billing|upgrade|subscription|checkout|delete|cancel|logout|sign\s?out|тариф|оплат|подписк|удал|отмен|выход)/i;
const REFRESH_LABEL_MAX = 24;

const HEARTBEAT_MS = 55_000;
const EMPTY_SCANS_BEFORE_WARNING = 6;
const WARNING_GRACE_MS = 20_000;
// Сколько строк вокруг числа считаем его окружением.
const CAPTION_LINES_BEFORE = 6;
const CONTEXT_LINES_AFTER = 2;

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
///   read     — записывает найденные проценты через sink.set(...)
///   guessDirection — можно ли додумывать «использовано», когда слова нет
///
/// `ctx` в read: { value, context, captionContext, percentIndex, confident }.
/// `context` захватывает и строки после числа — слово-признак может стоять с
/// любой стороны. `captionContext` обрывается на числе, потому что подпись
/// лимита всегда стоит перед ним.
const SITES = [
  {
    key: "claude",
    hosts: ["claude.ai"],
    // Claude now opens this screen through /new#settings/usage for many
    // accounts, so checking only the old pathname silently skipped scans.
    isUsage: (path, hash) => path.startsWith("/settings/usage") || hash.includes("settings/usage"),
    // Подписи здесь однозначные, а слово «used» сайт иногда рисует отдельным
    // элементом — без догадки страница читается вхолостую.
    guessDirection: true,
    read: (ctx, sink) => {
      // На странице три блока подряд: сессия, недельные лимиты и «Usage
      // credits» (это оплаченные API-кредиты, не квота тарифа). Раньше
      // достаточно было слов «Usage credits» где угодно рядом, и недельный
      // процент выбрасывался только потому, что следующей строкой начинался
      // блок кредитов. Поэтому смотрим, чья подпись ближе СЛЕВА от числа.
      const distances = [
        ["claudeFiveHourRemaining", nearest(ctx, FIVE_HOUR, CLAUDE_CURRENT_SESSION)],
        ["claudeWeeklyRemaining", nearest(ctx, WEEKLY, CLAUDE_WEEKLY_LIMITS)],
        [null, nearest(ctx, CLAUDE_USAGE_CREDITS)]
      ].filter(([, distance]) => distance !== null);

      if (distances.length === 0) return;
      distances.sort((left, right) => left[1] - right[1]);
      const [key] = distances[0];
      if (key) sink.set(key, ctx.value, ctx.confident);
    }
  },
  {
    key: "openai",
    hosts: ["chatgpt.com", "openai.com"],
    isUsage: (path, hash) =>
      path.includes("settings") || path.includes("codex") || hash.includes("settings"),
    guessDirection: true,
    read: (ctx, sink) => {
      // Codex и обычный ChatGPT живут в одних и тех же настройках аккаунта.
      // Простой проверки «есть ли слово Codex рядом» не хватает: окно текста
      // шириной в шесть строк, и название с самого верха перетягивало чужое
      // число себе. Считаем, чьё название стоит ближе слева от процента.
      const toCodex = nearest(ctx, CODEX);
      const toChatGPT = nearest(ctx, CHATGPT);

      if (toCodex !== null && (toChatGPT === null || toCodex <= toChatGPT)) {
        if (WEEKLY.test(ctx.context)) sink.set("codexWeeklyRemaining", ctx.value, ctx.confident);
        return;
      }
      if (WEEKLY.test(ctx.context) || MONTHLY.test(ctx.context) || REMAINING.test(ctx.context)) {
        sink.set("chatgptRemaining", ctx.value, ctx.confident);
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
    read: (ctx, sink) => { sink.set("geminiRemaining", ctx.value, ctx.confident); }
  },
  {
    key: "perplexity",
    hosts: ["perplexity.ai"],
    isUsage: (path) => path.includes("settings") || path.includes("account"),
    read: (ctx, sink) => { sink.set("perplexityRemaining", ctx.value, ctx.confident); }
  },
  {
    key: "cursor",
    hosts: ["cursor.com", "cursor.sh"],
    isUsage: (path) => path.includes("dashboard") || path.includes("settings") || path.includes("usage"),
    read: (ctx, sink) => { sink.set("cursorRemaining", ctx.value, ctx.confident); }
  },
  {
    key: "grok",
    hosts: ["grok.com"],
    isUsage: (path) => path.includes("settings") || path.includes("usage") || path.includes("subscription"),
    read: (ctx, sink) => { sink.set("grokRemaining", ctx.value, ctx.confident); }
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

/// Копилка значений. Точно распознанное число не даёт себя перезаписать
/// следующим таким же, а догадка уступает место точному значению.
function createSink() {
  const values = {};
  const confident = {};

  return {
    values,
    get approximate() {
      return Object.keys(values).filter((key) => !confident[key]);
    },
    set(key, value, isConfident) {
      const known = key in values;
      // Первое точное значение — главное: страницы перечисляют сначала общий
      // лимит, потом частные, и общий нужнее.
      if (known && (confident[key] || !isConfident)) return;
      values[key] = value;
      confident[key] = Boolean(isConfident);
    }
  };
}

/// Процент относится к своей строке, прочитанной вместе с соседними.
function readPercentage(lines, index, site) {
  const line = lines[index];
  const match = line.match(/(\d{1,3}(?:[.,]\d+)?)\s*%/);
  if (!match) return null;

  const raw = Number(match[1].replace(",", "."));
  if (!Number.isFinite(raw) || raw < 0 || raw > 100) return null;

  // Current Claude labels are a few lines above the bar and percentage.
  const prefix = lines.slice(Math.max(0, index - CAPTION_LINES_BEFORE), index).join(" ");
  const captionContext = prefix ? `${prefix} ${line}` : line;
  const percentIndex = (prefix ? prefix.length + 1 : 0) + match.index;
  const suffix = lines.slice(index + 1, index + 1 + CONTEXT_LINES_AFTER).join(" ");
  const context = suffix ? `${captionContext} ${suffix}` : captionContext;

  // Страницы пишут либо «осталось», либо «использовано». Слов может быть два
  // сразу — соседняя строка чужого блока попадает в то же окно, — поэтому
  // берём то, что стоит ближе к самому числу.
  const toRemaining = nearestTo(REMAINING, context, percentIndex);
  const toUsed = nearestTo(USED, context, percentIndex);

  let value = null;
  let confident = true;
  if (toRemaining !== null && (toUsed === null || toRemaining <= toUsed)) {
    value = raw;
  } else if (toUsed !== null) {
    value = 100 - raw;
  } else if (site.guessDirection && LIMIT_HINT.test(context)) {
    // Слово-признак пропало (сайт перерисовал вёрстку), но это явно счётчик
    // лимита. Все такие страницы показывают израсходованное — считаем так же
    // и помечаем значение как приблизительное.
    value = 100 - raw;
    confident = false;
  }
  if (value === null) return null;

  return { value, context, captionContext, percentIndex, confident };
}

/// Расстояние от числа назад до ближайшей подписи, или null, если подписи
/// перед числом нет.
function distanceToCaptionBefore(pattern, context, percentIndex) {
  let best = null;
  for (const index of matchIndexes(pattern, context)) {
    if (index >= percentIndex) continue;
    const distance = percentIndex - index;
    if (best === null || distance < best) best = distance;
  }
  return best;
}

/// Ближайшее слово-признак с любой стороны от числа.
function nearestTo(pattern, context, percentIndex) {
  let best = null;
  for (const index of matchIndexes(pattern, context)) {
    const distance = Math.abs(index - percentIndex);
    if (best === null || distance < best) best = distance;
  }
  return best;
}

/// Ближайшая слева подпись из перечисленных.
function nearest(ctx, ...patterns) {
  let best = null;
  for (const pattern of patterns) {
    const distance = distanceToCaptionBefore(pattern, ctx.captionContext, ctx.percentIndex);
    if (distance !== null && (best === null || distance < best)) best = distance;
  }
  return best;
}

function matchIndexes(pattern, text) {
  const scanner = new RegExp(pattern.source, `${pattern.flags.replace("g", "")}g`);
  const found = [];
  let match;

  while ((match = scanner.exec(text)) !== null) {
    found.push(match.index);
    if (match.index === scanner.lastIndex) scanner.lastIndex += 1;
  }

  return found;
}

function detectUsage() {
  const site = currentSite();
  if (!site || !isUsagePage()) return { usage: {}, approximate: [] };

  const text = document.body?.innerText?.slice(0, 20_000) ?? "";
  if (site.key === "deepseek") {
    const balance = readDeepSeekBalance(text);
    return {
      usage: balance === null ? {} : { deepseekBalanceUSD: balance },
      approximate: []
    };
  }

  const lines = text.split(/\n+/).map((line) => line.trim()).filter(Boolean);
  const sink = createSink();

  for (let index = 0; index < lines.length; index += 1) {
    const found = readPercentage(lines, index, site);
    if (found) site.read(found, sink);
  }

  return { usage: sink.values, approximate: sink.approximate };
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

  const { usage, approximate } = detectUsage();
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
  send({ type: "USAGE_FOUND", usage, approximate });
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

// Usage screens are client-rendered. Their visible values often appear after
// document_idle, so re-scan after a quiet DOM update instead of relying on a
// single scan immediately after opening the tab.
function watchForUsageContent() {
  if (!document.body) return;

  const observer = new MutationObserver(() => {
    if (isUsagePage()) scheduleReport();
  });

  observer.observe(document.body, { childList: true, subtree: true, characterData: true });
}

/// Сама страница лимитов свои цифры не пересчитывает: у Claude рядом написано
/// «Last updated» и стоит кнопка обновления. Нажимаем её сами, иначе виджет
/// честно показывает свежесть чтения страницы, а на странице — цифры часовой
/// давности. Совпадение только по полной подписи кнопки.
function findRefreshControl() {
  const controls = document.querySelectorAll('button, [role="button"]');
  for (const control of controls) {
    if (control.disabled || control.getAttribute("aria-disabled") === "true") continue;
    const label = (
      control.getAttribute("aria-label") ||
      control.getAttribute("title") ||
      control.textContent ||
      ""
    ).replace(/\s+/g, " ").trim();

    if (label.length === 0 || label.length > REFRESH_LABEL_MAX) continue;
    if (!REFRESH_LABEL.test(label)) continue;
    if (REFRESH_FORBIDDEN.test(label)) continue;
    return control;
  }
  return null;
}

function clickRefreshControl() {
  if (!isUsagePage()) return false;
  const control = findRefreshControl();
  if (!control) return false;
  control.click();
  return true;
}

try {
  chrome.runtime.sendMessage({ type: "GET_CONSENT" }, (response) => {
    void chrome.runtime.lastError;
    if (response?.enabled) start();
  });
} catch {
  // Без живого контекста расширения делать нечего.
}

watchForUsageContent();

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "USAGE_ENABLED") start();

  // Пересканировать по команде фоновой части. Свои таймеры в фоновой вкладке
  // Chrome придушивает, а доставку сообщений — нет, поэтому отсчёт свежести
  // держится на этом, а не на setInterval внутри страницы.
  if (message?.type === "RESCAN") {
    lastUsage = "";
    reportUsage();
  }

  // Попросить страницу обновить свои цифры.
  if (message?.type === "REFRESH") {
    const clicked = clickRefreshControl();
    if (clicked) {
      lastUsage = "";
      window.setTimeout(reportUsage, 2500);
    }
    sendResponse({ clicked });
    return true;
  }

  // Что скрипт видит на странице. Нужно, когда сервис поменял вёрстку и
  // проценты перестали находиться: без этого причину можно только угадывать.
  if (message?.type === "DIAGNOSE") {
    sendResponse(collectDiagnostics());
    return true;
  }
});

function collectDiagnostics() {
  const site = currentSite();
  const text = document.body?.innerText?.slice(0, 20_000) ?? "";
  const lines = text.split(/\n+/).map((line) => line.trim()).filter(Boolean);
  const { usage, approximate } = detectUsage();

  // Только строки с процентом и пара строк вокруг — остальное не нужно и
  // незачем показывать: это чужая страница.
  const interesting = [];
  lines.forEach((line, index) => {
    if (!/\d\s*%/.test(line)) return;
    for (let offset = -3; offset <= 1; offset += 1) {
      const neighbour = lines[index + offset];
      if (neighbour && !interesting.includes(neighbour)) interesting.push(neighbour);
    }
  });

  return {
    host: location.hostname,
    path: location.pathname,
    hash: location.hash,
    site: site?.key ?? null,
    isUsagePage: isUsagePage(),
    consent: isEnabled,
    detected: usage,
    approximate,
    hasPercentOnPage: interesting.length > 0,
    hasRefreshControl: Boolean(site) && findRefreshControl() !== null,
    linesWithPercent: interesting.slice(0, 60)
  };
}

new MutationObserver(scheduleReport).observe(document.documentElement, {
  childList: true,
  subtree: true,
  characterData: true
});
// Периодический пересчёт, чтобы заметить разлогин или смену вёрстки даже на
// статичной странице.
window.setInterval(reportUsage, 30_000);
watchForPageChanges();
