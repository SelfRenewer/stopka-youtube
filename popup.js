/* Стопка — попап */

const KEY = 'items';
const $ = (id) => document.getElementById(id);
const listEl = $('list');
const emptyEl = $('empty');
const countEl = $('count');
const toastEl = $('toast');
const filterEl = $('filter');
const filterWrap = $('filter-wrap');

let items = [];
let query = '';

/* ---------- storage ---------- */

const read = () =>
  new Promise((r) => chrome.storage.local.get(KEY, (res) => r((res && res[KEY]) || [])));

/* Возвращает текст ошибки хранилища или null. Без проверки lastError
   неудачная запись выглядит как успешная: колбэк зовётся в обоих случаях. */
const write = (v) =>
  new Promise((r) =>
    chrome.storage.local.set({ [KEY]: v }, () => {
      const e = chrome.runtime.lastError;
      r(e ? e.message || String(e) : null);
    })
  );

const drop = () =>
  new Promise((r) =>
    chrome.storage.local.remove(KEY, () => {
      const e = chrome.runtime.lastError;
      r(e ? e.message || String(e) : null);
    })
  );

/* ---------- вспомогательное ---------- */

function when(ts) {
  const d = new Date(ts);
  return d.toLocaleDateString('ru-RU', { day: '2-digit', month: 'short' });
}

let toastTimer;
function toast(text) {
  toastEl.textContent = text;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (toastEl.textContent = ''), 2200);
}

/* ---------- рендер ---------- */

function render() {
  const visible = query
    ? items.filter((x) =>
        (x.title + ' ' + (x.channel || '')).toLowerCase().includes(query)
      )
    : items;

  countEl.textContent = `${items.length} видео`;
  filterWrap.hidden = items.length < 7;
  emptyEl.hidden = items.length > 0;

  listEl.textContent = '';
  visible.forEach((item, i) => {
    const li = document.createElement('li');
    li.className = 'row';

    const idx = document.createElement('span');
    idx.className = 'idx';
    idx.textContent = String(i + 1).padStart(2, '0');

    const img = document.createElement('img');
    img.className = 'thumb';
    img.src = item.thumb;
    img.alt = '';
    img.loading = 'lazy';

    const meta = document.createElement('div');
    meta.className = 'meta';

    const a = document.createElement('a');
    a.className = 'title';
    a.href = item.url;
    a.target = '_blank';
    a.rel = 'noreferrer';
    a.textContent = item.title;

    const sub = document.createElement('div');
    sub.className = 'sub';
    sub.textContent = [item.channel, when(item.addedAt)].filter(Boolean).join(' · ');

    meta.append(a, sub);

    const del = document.createElement('button');
    del.className = 'del';
    del.type = 'button';
    del.textContent = '×';
    del.title = 'Убрать из стопки';
    del.setAttribute('aria-label', `Убрать «${item.title}»`);
    del.addEventListener('click', async () => {
      const было = items;
      items = items.filter((x) => x.id !== item.id);
      const ошибка = await write(items);
      render();
      if (ошибка) {
        items = было;
        render();
        toast('Хранилище отказало: ' + ошибка);
        return;
      }
      toast('Убрано');
    });

    li.append(idx, img, meta, del);
    listEl.append(li);
  });

  if (query && visible.length === 0) {
    const li = document.createElement('li');
    li.className = 'empty';
    li.textContent = 'Ничего не нашлось';
    listEl.append(li);
  }
}

/* ---------- действия ---------- */

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    const ta = document.createElement('textarea');
    ta.value = text;
    document.body.append(ta);
    ta.select();
    const ok = document.execCommand('copy');
    ta.remove();
    return ok;
  }
}

$('copy').addEventListener('click', async () => {
  if (!items.length) return toast('Список пуст');
  const ok = await copyText(items.map((x) => x.url).join('\n'));
  toast(ok ? `Скопировано ссылок: ${items.length}` : 'Не удалось скопировать');
});

/* Подтверждение в два нажатия, а не через confirm():
   в попапе расширения Safari системный диалог не показывается. */
const clearBtn = $('clear');
const CLEAR_LABEL = clearBtn.textContent;
let clearArmed = null;

function disarmClear() {
  clearTimeout(clearArmed);
  clearArmed = null;
  clearBtn.textContent = CLEAR_LABEL;
  clearBtn.classList.remove('is-armed');
}

clearBtn.addEventListener('click', async () => {
  if (!items.length) return;
  if (!clearArmed) {
    clearBtn.textContent = 'Точно очистить?';
    clearBtn.classList.add('is-armed');
    clearArmed = setTimeout(disarmClear, 4000);
    return;
  }
  disarmClear();
  const было = items;
  items = [];
  const ошибка = await write(items);
  render();

  /* В Safari запись пустого списка не всегда доходит до хранилища.
     Перечитываем; если не помогло — сносим ключ целиком. */
  let осталось = await read();
  if (осталось.length) {
    await drop();
    осталось = await read();
  }

  if (осталось.length) {
    items = было;
    render();
    toast(ошибка ? 'Хранилище отказало: ' + ошибка : 'Очистить не вышло, попробуй ещё раз');
    return;
  }
  toast('Стопка пуста');
});

document.addEventListener('click', (e) => {
  if (clearArmed && e.target !== clearBtn) disarmClear();
});

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && clearArmed) disarmClear();
});

filterEl.addEventListener('input', () => {
  query = filterEl.value.trim().toLowerCase();
  render();
});

/* ---------- старт ---------- */

(async () => {
  items = await read();
  render();
})();

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && changes[KEY]) {
    items = changes[KEY].newValue || [];
    render();
  }
});
