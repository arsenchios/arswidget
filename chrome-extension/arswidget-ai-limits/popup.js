const METRICS = [
  { key: "claudeFiveHourRemaining", title: "Claude, 5 часов", provider: "Claude" },
  { key: "claudeWeeklyRemaining", title: "Claude, неделя", provider: "Claude" },
  { key: "codexWeeklyRemaining", title: "Codex, неделя", provider: "Codex" },
  { key: "chatgptRemaining", title: "ChatGPT", provider: "ChatGPT" },
  { key: "deepseekBalanceUSD", title: "DeepSeek balance", provider: "DeepSeek", format: "usd" },
  { key: "geminiRemaining", title: "Gemini", provider: "Gemini" },
  { key: "perplexityRemaining", title: "Perplexity", provider: "Perplexity" },
  { key: "cursorRemaining", title: "Cursor", provider: "Cursor" },
  { key: "grokRemaining", title: "Grok", provider: "Grok" }
];

// Сервис = одна строка состояния. `site` совпадает с ключом в content.js,
// `keys` — значения, которые с этого сайта приходят.
const SERVICES = [
  {
    site: "claude",
    name: "Claude",
    keys: ["claudeFiveHourRemaining", "claudeWeeklyRemaining"],
    url: "https://claude.ai/new#settings/usage",
    where: "Settings → Usage"
  },
  {
    site: "openai",
    name: "Codex и ChatGPT",
    keys: ["codexWeeklyRemaining", "chatgptRemaining"],
    url: "https://chatgpt.com/codex/cloud/settings/analytics",
    where: "Codex → Settings → Analytics"
  },
  {
    site: "deepseek",
    name: "DeepSeek",
    keys: ["deepseekBalanceUSD"],
    url: "https://platform.deepseek.com/usage",
    where: "остаток API-баланса"
  },
  {
    site: "gemini",
    name: "Gemini",
    keys: ["geminiRemaining"],
    url: "https://aistudio.google.com/",
    where: "AI Studio"
  },
  {
    site: "perplexity",
    name: "Perplexity",
    keys: ["perplexityRemaining"],
    url: "https://www.perplexity.ai/settings/account",
    where: "настройки аккаунта"
  },
  {
    site: "cursor",
    name: "Cursor",
    keys: ["cursorRemaining"],
    url: "https://cursor.com/dashboard",
    where: "Dashboard"
  },
  {
    site: "grok",
    name: "Grok",
    keys: ["grokRemaining"],
    url: "https://grok.com/settings",
    where: "настройки"
  }
];

const STALE_AFTER_MS = 15 * 60 * 1000;

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
  const freshness = document.querySelector("#freshness");
  const stale = document.querySelector("#stale");
  const rows = METRICS.filter(({ key }) => Number.isFinite(arsWidgetUsage[key]));
  const approximate = new Set(arsWidgetUsage.approximateKeys ?? []);

  document.querySelector("#consent").hidden = arsWidgetUsageConsent;
  document.querySelector("#disable").hidden = !arsWidgetUsageConsent;

  status.textContent = !arsWidgetUsageConsent
    ? "Сначала подтверди показ лимитов."
    : arsWidgetBridgeStatus.connected
    ? "ArsWidget подключён — цифры уходят в виджет."
    : "ArsWidget не отвечает. Запусти приложение на этом Mac.";
  status.className = arsWidgetUsageConsent && arsWidgetBridgeStatus.connected ? "ok" : "warn";

  limits.replaceChildren(...rows.map((metric) => {
    const { key, title } = metric;
    const row = document.createElement("div");
    row.className = "limit";

    const name = document.createElement("span");
    name.textContent = approximate.has(key) ? `${title} · приблизительно` : title;

    const value = document.createElement("strong");
    value.textContent = formatValue(arsWidgetUsage[key], metric.format);
    if (approximate.has(key)) value.classList.add("approx");

    row.append(name, value);
    return row;
  }));
  // Without this the last known rows stayed on screen after the data was gone.
  limits.hidden = rows.length === 0;

  const text = rows.length ? ageText(arsWidgetUsage.updatedAt) : "";
  freshness.textContent = text;
  freshness.hidden = !text;

  // Прямая подсказка вместо молчания: цифры есть, но им уже много времени.
  const isStale = rows.length > 0
    && Number.isFinite(arsWidgetUsage.updatedAt)
    && Date.now() - arsWidgetUsage.updatedAt > STALE_AFTER_MS;
  stale.textContent = isStale
    ? "Страницы лимитов давно не читались. Открой их и нажми «Обновить сейчас»."
    : "";
  stale.hidden = !isStale;

  await renderState(arsWidgetUsage, approximate);
}

/// Состояние по каждому сервису: открыта ли вкладка, та ли это страница, есть
/// ли на ней проценты и что из них прочитано. Без этого «не работает» выглядит
/// одинаково во всех случаях, а причины у них разные.
async function renderState(usage, approximate) {
  const container = document.querySelector("#state");
  const reports = await collectReports();

  container.replaceChildren(...SERVICES.map((service) => {
    const report = reports.get(service.site);
    const values = service.keys
      .filter((key) => Number.isFinite(usage[key]))
      .map((key) => {
        const metric = METRICS.find((candidate) => candidate.key === key);
        const shown = formatValue(usage[key], metric?.format);
        return approximate.has(key) ? `${shown}?` : shown;
      });

    const row = document.createElement("div");
    row.className = "service";

    const name = document.createElement("span");
    name.className = "service-name";
    name.textContent = service.name;

    const note = document.createElement("span");
    const state = describeService(service, report, values);
    note.className = `service-note ${state.tone}`;
    note.textContent = state.text;

    const open = document.createElement("button");
    open.className = "link";
    open.textContent = report ? "показать" : "открыть";
    open.addEventListener("click", () => {
      if (report?.tabId !== undefined) {
        chrome.tabs.update(report.tabId, { active: true });
        window.close();
        return;
      }
      chrome.tabs.create({ url: service.url });
    });

    const head = document.createElement("div");
    head.className = "service-head";
    head.append(name, open);
    row.append(head, note);
    return row;
  }));
}

function describeService(service, report, values) {
  if (!report) {
    return values.length
      ? { tone: "muted", text: `вкладка закрыта, последнее: ${values.join(" / ")}` }
      : { tone: "muted", text: `вкладка не открыта — ${service.where}` };
  }
  if (!report.isUsagePage) {
    return { tone: "warn", text: `сайт открыт, но не на странице лимитов — ${service.where}` };
  }
  if (!report.consent) {
    return { tone: "warn", text: "показ лимитов выключен" };
  }
  if (Object.keys(report.detected ?? {}).length > 0) {
    const shown = values.length ? values.join(" / ") : "читаю";
    return { tone: "ok", text: `страницу вижу, читаю: ${shown}` };
  }
  if (report.hasPercentOnPage) {
    return {
      tone: "bad",
      text: "страницу вижу, проценты на ней есть, но распознать их не получилось — нажми «Что видит расширение»"
    };
  }
  return {
    tone: "bad",
    text: "страницу вижу, но процентов на ней нет — проверь, что ты вошёл в аккаунт, и обнови страницу"
  };
}

/// Опрашивает открытые вкладки поддерживаемых сайтов.
async function collectReports() {
  const found = new Map();
  let tabs = [];
  try {
    const matches = chrome.runtime.getManifest().content_scripts[0].matches;
    tabs = await chrome.tabs.query({ url: matches });
  } catch {
    return found;
  }

  await Promise.all(tabs.map(async (tab) => {
    if (typeof tab.id !== "number") return;
    try {
      const report = await chrome.tabs.sendMessage(tab.id, { type: "DIAGNOSE" });
      if (!report?.site) return;
      const previous = found.get(report.site);
      // Вкладок одного сайта может быть несколько: показываем ту, где
      // действительно что-то прочитано.
      const better = !previous
        || (Object.keys(report.detected ?? {}).length > Object.keys(previous.detected ?? {}).length)
        || (report.isUsagePage && !previous.isUsagePage);
      if (better) found.set(report.site, { ...report, tabId: tab.id });
    } catch {
      // Скрипт в эту вкладку не внедрён — её открыли до установки расширения.
    }
  }));

  return found;
}

function formatValue(value, format = "percent") {
  return format === "usd" ? `$${value.toFixed(2)}` : `${Math.round(value)}%`;
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

document.querySelector("#refresh").addEventListener("click", () => {
  chrome.runtime.sendMessage({ type: "REFRESH_NOW" }).catch(() => {});
  window.setTimeout(render, 1200);
});

// Values can land while the popup is open.
chrome.storage.onChanged.addListener((_changes, area) => {
  if (area === "local") render();
});

render();

// ─── Диагностика ─────────────────────────────────────────────────────────────
// Когда сервис меняет вёрстку, проценты перестают находиться, и снаружи это
// выглядит как «расширение не работает». Эта кнопка показывает, что скрипт
// реально видит на открытой странице, — чтобы чинить по факту, а не наугад.

const diagnosis = document.querySelector("#diagnosis");
const copyDiagnosis = document.querySelector("#copyDiagnosis");

function describe(report) {
  if (!report) {
    return "На этой вкладке расширение не работает.\n\n" +
      "Открой страницу лимитов из списка выше и нажми ещё раз.";
  }
  const lines = [
    `сайт:        ${report.site ?? "не поддерживается"}`,
    `адрес:       ${report.host}${report.path}${report.hash}`,
    `страница лимитов: ${report.isUsagePage ? "да" : "НЕТ"}`,
    `показ включён:    ${report.consent ? "да" : "НЕТ"}`,
    `кнопка обновления: ${report.hasRefreshControl ? "нашлась" : "не нашлась"}`,
    `распознано:  ${JSON.stringify(report.detected)}`,
    `приблизительно: ${JSON.stringify(report.approximate ?? [])}`,
    "",
    "строки с процентами на странице:"
  ];
  if (report.linesWithPercent.length === 0) {
    lines.push("  (процентов на странице не найдено)");
  } else {
    for (const line of report.linesWithPercent) lines.push("  " + line);
  }
  return lines.join("\n");
}

document.querySelector("#diagnose").addEventListener("click", async () => {
  diagnosis.hidden = false;
  copyDiagnosis.hidden = false;
  diagnosis.value = "Смотрю…";

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab || typeof tab.id !== "number") {
    diagnosis.value = describe(null);
    return;
  }
  try {
    const report = await chrome.tabs.sendMessage(tab.id, { type: "DIAGNOSE" });
    diagnosis.value = describe(report);
  } catch {
    // Скрипт в эту вкладку не внедрён — значит, адрес не из списка,
    // либо вкладку открыли до установки расширения.
    diagnosis.value = describe(null) +
      "\n\nЕсли адрес правильный — перезагрузи вкладку: скрипт внедряется при загрузке.";
  }
});

copyDiagnosis.addEventListener("click", async () => {
  await navigator.clipboard.writeText(diagnosis.value);
  copyDiagnosis.textContent = "Скопировано";
  window.setTimeout(() => { copyDiagnosis.textContent = "Скопировать"; }, 1500);
});
