// Проверка распознавания процентов в content.js.
// Запуск без зависимостей: node chrome-extension/tests/detection.test.js
//
// Тесты лежат вне папки расширения, чтобы не попадать в ZIP для Chrome Web Store.
//
// Страницы лимитов меняют вёрстку, поэтому здесь зафиксированы реальные
// раскладки текста. Если распознавание сломается, тест покажет это до релиза.

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const CONTENT_SCRIPT = path.join(__dirname, "..", "arswidget-ai-limits", "content.js");

/// Прогоняет content.js в песочнице с поддельной страницей и возвращает то,
/// что скрипт отправил бы в фоновую часть расширения.
function detect(hostname, pathname, bodyText) {
  const sent = [];
  const sandbox = {
    location: { hostname, pathname, hash: "", href: "" },
    document: { body: { innerText: bodyText }, documentElement: {} },
    window: { setTimeout: () => 0, setInterval: () => 0 },
    MutationObserver: class { observe() {} },
    chrome: {
      runtime: {
        lastError: null,
        sendMessage: (message, callback) => {
          if (message.type === "GET_CONSENT") {
            callback({ enabled: true });
            return undefined;
          }
          sent.push(message);
          return Promise.resolve({ ok: true });
        },
        onMessage: { addListener: () => {} }
      }
    }
  };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(CONTENT_SCRIPT, "utf8"), sandbox);
  // start() ставит скан через setTimeout, здесь вызываем скан напрямую.
  vm.runInContext("reportUsage()", sandbox);
  return sent[0]?.usage ?? {};
}

const cases = [
  {
    name: "Claude: подписи в одну строку со значением",
    host: "claude.ai",
    path: "/settings/usage",
    body: "5-hour limit · 12% remaining\nWeekly limit · 88% remaining",
    expect: { claudeFiveHourRemaining: 12, claudeWeeklyRemaining: 88 }
  },
  {
    name: "Claude: значения блоками",
    host: "claude.ai",
    path: "/settings/usage",
    body: "Usage\nCurrent session\n5-hour limit\n42% used\nResets at 14:00\nWeekly limit\nWeekly usage\n77% used",
    expect: { claudeFiveHourRemaining: 58, claudeWeeklyRemaining: 23 }
  },
  {
    name: "Claude: недельный лимит назван, но число ещё не отрисовано",
    host: "claude.ai",
    path: "/settings/usage",
    body: "Usage\n5-hour limit\n18% used\nWeekly limit\nResets Monday",
    expect: { claudeFiveHourRemaining: 82 }
  },
  {
    name: "Claude: обе подписи над одним числом — берём ближнюю",
    host: "claude.ai",
    path: "/settings/usage",
    body: "Weekly limit\n5-hour limit\n34% used",
    expect: { claudeFiveHourRemaining: 66 }
  },
  {
    // DeepSeek перевели с процентов на остаток оплаченного баланса:
    // проценты плана он не показывает, показывает деньги.
    name: "DeepSeek: остаток баланса в долларах",
    host: "platform.deepseek.com",
    path: "/usage",
    body: "API Usage\nTopped-up Balance\n$ 12.35\nGranted Balance\n$ 0.00",
    expect: { deepseekBalanceUSD: 12.35 }
  },
  {
    name: "DeepSeek: без подписи баланса ничего не берём",
    host: "platform.deepseek.com",
    path: "/usage",
    body: "API Usage\nSome other number\n$ 99.00",
    expect: {}
  },
  {
    name: "DeepSeek: проценты на странице больше не читаются",
    host: "platform.deepseek.com",
    path: "/usage",
    body: "Quota\n64%\nremaining this month",
    expect: {}
  },
  {
    name: "Codex: название сервиса двумя строками выше",
    host: "chatgpt.com",
    path: "/settings/Account",
    body: "Account\nCodex\nWeekly limit\n23% used",
    expect: { codexWeeklyRemaining: 77 }
  },
  {
    name: "Gemini",
    host: "aistudio.google.com",
    path: "/",
    body: "Quota\nremaining\n40%",
    expect: { geminiRemaining: 40 }
  },
  {
    name: "Не залогинен — процентов нет",
    host: "claude.ai",
    path: "/settings/usage",
    body: "Log in to continue",
    expect: {}
  },
  {
    name: "Процент без слова-признака не берём",
    host: "claude.ai",
    path: "/settings/usage",
    body: "Plan\n50%",
    expect: {}
  },
  {
    name: "Значение вне 0-100 игнорируется",
    host: "claude.ai",
    path: "/settings/usage",
    body: "5-hour limit\n420% used",
    expect: {}
  },
  {
    name: "Страница не про лимиты — ничего не читаем",
    host: "claude.ai",
    path: "/chat/123",
    body: "5-hour limit\n42% used",
    expect: {}
  },
  {
    name: "ChatGPT и Codex на одной странице не путаются",
    host: "chatgpt.com",
    path: "/settings/Account",
    body: "Account\nCodex\nWeekly limit\n23% used\nChatGPT\nMonthly limit\n60% used",
    expect: { codexWeeklyRemaining: 77, chatgptRemaining: 40 }
  },
  {
    name: "Perplexity",
    host: "www.perplexity.ai",
    path: "/settings/account",
    body: "Pro searches\nremaining\n35%",
    expect: { perplexityRemaining: 35 }
  },
  {
    name: "Cursor",
    host: "cursor.com",
    path: "/dashboard",
    body: "Premium requests\n72% used",
    expect: { cursorRemaining: 28 }
  },
  {
    name: "Grok",
    host: "grok.com",
    path: "/settings",
    body: "Usage\n45% remaining",
    expect: { grokRemaining: 45 }
  },
  {
    name: "Неизвестный сайт игнорируется целиком",
    host: "example.com",
    path: "/settings",
    body: "Weekly limit\n50% used",
    expect: {}
  }
];

/// Claude и ChatGPT — одностраничные приложения: переход на страницу лимитов
/// внутри сайта не перезагружает документ. Расширение обязано это заметить,
/// иначе оно молчит у всех, кто пришёл на Usage кликом, а не по прямой ссылке.
function checkSinglePageNavigation() {
  const sent = [];
  let urlWatcher = null;
  const location = { hostname: "claude.ai", pathname: "/chats", hash: "", href: "https://claude.ai/chats" };
  const timers = [];
  const sandbox = {
    location,
    document: { body: { innerText: "新 chat" }, documentElement: {} },
    window: {
      setTimeout: (fn) => { timers.push(fn); return 0; },
      setInterval: (fn, ms) => { if (ms === 1000) urlWatcher = fn; return 0; }
    },
    MutationObserver: class { observe() {} },
    chrome: {
      runtime: {
        lastError: null,
        sendMessage: (message, callback) => {
          if (message.type === "GET_CONSENT") { callback({ enabled: true }); return undefined; }
          sent.push(message);
          return Promise.resolve({ ok: true });
        },
        onMessage: { addListener: () => {} }
      }
    }
  };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(CONTENT_SCRIPT, "utf8"), sandbox);

  // The user clicks through to Usage inside the app: URL and content change,
  // but no document ever loads.
  location.pathname = "/settings/usage";
  location.href = "https://claude.ai/settings/usage";
  sandbox.document.body.innerText = "5-hour limit · 18% remaining";
  if (typeof urlWatcher !== "function") return { ok: false, detail: "нет наблюдателя за сменой адреса" };
  urlWatcher();
  vm.runInContext("reportUsage()", sandbox);

  const usage = sent.find((m) => m.type === "USAGE_FOUND")?.usage;
  return {
    ok: JSON.stringify(usage) === JSON.stringify({ claudeFiveHourRemaining: 18 }),
    detail: JSON.stringify(usage)
  };
}

let failed = 0;
for (const testCase of cases) {
  const actual = detect(testCase.host, testCase.path, testCase.body);
  const ok = JSON.stringify(actual) === JSON.stringify(testCase.expect);
  if (!ok) {
    failed += 1;
    console.error(`FAIL  ${testCase.name}`);
    console.error(`      ожидалось ${JSON.stringify(testCase.expect)}`);
    console.error(`      получено  ${JSON.stringify(actual)}`);
  } else {
    console.log(`ok    ${testCase.name}`);
  }
}

const spa = checkSinglePageNavigation();
const total = cases.length + 1;
if (spa.ok) {
  console.log("ok    Переход на страницу лимитов внутри сайта, без перезагрузки");
} else {
  failed += 1;
  console.error("FAIL  Переход на страницу лимитов внутри сайта, без перезагрузки");
  console.error(`      получено  ${spa.detail}`);
}

if (failed > 0) {
  console.error(`\nПровалено проверок: ${failed} из ${total}.`);
  process.exit(1);
}
console.log(`\nВсе ${total} проверок прошли.`);
