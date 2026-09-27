/* Стопка — контент-скрипт для youtube.com
   Вешает кнопку «+» на каждое превью видео и пишет выбранное в chrome.storage.local */

(() => {
  const KEY = 'items';
  const MARK = 'data-stopka-ready';
  let savedIds = new Set();

  /* ---------- storage ---------- */

  const read = () =>
    new Promise((resolve) => {
      chrome.storage.local.get(KEY, (res) => resolve(res[KEY] || []));
    });

  /* Возвращает текст ошибки или null: без проверки lastError отказ
     хранилища выглядит как успешная запись, и кнопка врёт. */
  const write = (items) =>
    new Promise((resolve) =>
      chrome.storage.local.set({ [KEY]: items }, () => {
        const e = chrome.runtime.lastError;
        resolve(e ? e.message || String(e) : null);
      })
    );

  /* Правки идут по очереди: два быстрых нажатия подряд читали один и тот же
     массив и вторая запись затирала первую. */
  let queue = Promise.resolve();

  function toggle(entry) {
    const step = queue.then(async () => {
      const items = await read();
      const i = items.findIndex((x) => x.id === entry.id);
      if (i >= 0) {
        items.splice(i, 1);
      } else {
        items.unshift(entry);
      }
      const ошибка = await write(items);
      if (ошибка) return null; // не сохранилось — кнопку не перерисовываем
      return i < 0; // true = добавили
    });
    queue = step.catch(() => {});
    return step;
  }

  /* ---------- разбор страницы ---------- */

  function videoIdFrom(href) {
    if (!href) return null;
    let u;
    try {
      u = new URL(href, location.origin);
    } catch {
      return null;
    }
    if (u.hostname.endsWith('youtu.be')) return u.pathname.slice(1) || null;
    if (u.pathname === '/watch') return u.searchParams.get('v');
    const m = u.pathname.match(/^\/(shorts|live|embed)\/([\w-]{6,})/);
    return m ? m[2] : null;
  }

  const CARD_SELECTOR = [
    'ytd-rich-item-renderer',
    'ytd-video-renderer',
    'ytd-compact-video-renderer',
    'ytd-grid-video-renderer',
    'ytd-playlist-video-renderer',
    'ytd-playlist-panel-video-renderer',
    'ytd-reel-item-renderer',
    'yt-lockup-view-model',
    'ytm-shorts-lockup-view-model',
    'ytm-shorts-lockup-view-model-v2'
  ].join(',');

  const TITLE_SELECTOR = [
    '#video-title',
    'a#video-title-link',
    'h3 a[title]',
    'a.ytLockupMetadataViewModelTitle',
    '.yt-lockup-metadata-view-model__title',
    '.yt-lockup-metadata-view-model-wiz__title',
    '.shortsLockupViewModelHostMetadataTitle',
    'h3 span'
  ].join(',');

  const CHANNEL_SELECTOR = [
    'ytd-channel-name a',
    '#channel-name a',
    '.ytContentMetadataViewModelMetadataRow a',
    '.yt-content-metadata-view-model__metadata-row a',
    '.yt-content-metadata-view-model-wiz__metadata-row a'
  ].join(',');

  /* В сайдбаре рекомендаций канал — просто текст первой строки метаданных,
     ссылки там нет, поэтому нужен запасной вариант. */
  const CHANNEL_TEXT_SELECTOR = [
    '.ytContentMetadataViewModelMetadataRow',
    '.yt-content-metadata-view-model__metadata-row'
  ].join(',');

  function clean(text) {
    return (text || '').replace(/\s+/g, ' ').trim();
  }

  function entryFromAnchor(a, id) {
    const card = a.closest(CARD_SELECTOR) || a.parentElement;
    const titleEl = card && card.querySelector(TITLE_SELECTOR);
    const chanEl =
      (card && card.querySelector(CHANNEL_SELECTOR)) ||
      (card && card.querySelector(CHANNEL_TEXT_SELECTOR));
    const title =
      clean(titleEl && (titleEl.getAttribute('title') || titleEl.textContent)) ||
      clean(a.getAttribute('aria-label')) ||
      'Видео без названия';
    return {
      id,
      url: `https://www.youtube.com/watch?v=${id}`,
      title,
      channel: clean(chanEl && chanEl.textContent),
      thumb: `https://i.ytimg.com/vi/${id}/mqdefault.jpg`,
      addedAt: Date.now()
    };
  }

  /* ---------- кнопка ---------- */

  function makeButton(id, getEntry) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'stopka-btn';
    btn.setAttribute('data-id', id);
    btn.innerHTML =
      '<svg viewBox="0 0 20 20" aria-hidden="true"><path class="stopka-plus" d="M10 4.5v11M4.5 10h11"/>' +
      '<path class="stopka-check" d="M4.8 10.4l3.4 3.4 7-7.6"/></svg>';
    paint(btn, savedIds.has(id));

    const stop = (e) => {
      e.preventDefault();
      e.stopPropagation();
    };
    btn.addEventListener('pointerdown', stop);
    btn.addEventListener('mousedown', stop);
    btn.addEventListener('click', async (e) => {
      stop(e);
      const added = await toggle(getEntry());
      if (added === null) return;
      paint(btn, added);
      btn.classList.remove('is-pop');
      void btn.offsetWidth;
      btn.classList.add('is-pop');
    });
    return btn;
  }

  function paint(btn, saved) {
    btn.classList.toggle('is-saved', !!saved);
    btn.title = saved ? 'Убрать из стопки' : 'Отложить в стопку';
    btn.setAttribute('aria-label', btn.title);
  }

  function repaintAll() {
    document.querySelectorAll('.stopka-btn').forEach((btn) => {
      paint(btn, savedIds.has(btn.getAttribute('data-id')));
    });
  }

  /* ---------- обход превью ---------- */

  const ANCHOR_SELECTOR = [
    'a#thumbnail',
    'a.ytLockupViewModelContentImage',
    'a.yt-lockup-view-model__content-image',
    'a.yt-lockup-view-model-wiz__content-image',
    'a.shortsLockupViewModelHostEndpoint',
    'a.reel-item-endpoint'
  ].join(',');

  /* У шортсов ссылка на заголовок носит тот же класс, что и ссылка-превью,
     поэтому берём только те, внутри которых действительно лежит картинка. */
  const THUMB_IMAGE_SELECTOR = [
    'img',
    'yt-image',
    'ytd-thumbnail',
    '.ytCoreImageHost',
    '.ytThumbnailViewModelImage'
  ].join(',');

  function scan() {
    document.querySelectorAll(ANCHOR_SELECTOR).forEach((a) => {
      if (a.hasAttribute(MARK)) return;
      const id = videoIdFrom(a.getAttribute('href'));
      if (!id) return;
      if (!a.querySelector(THUMB_IMAGE_SELECTOR)) return; // ссылка на заголовок, не превью
      if (a.clientWidth && a.clientWidth < 80) return; // мелкие служебные превью

      a.setAttribute(MARK, '1');
      if (getComputedStyle(a).position === 'static') a.style.position = 'relative';
      a.appendChild(makeButton(id, () => entryFromAnchor(a, id)));
    });
    scanWatch();
  }

  /* ---------- кнопка на самой странице видео ---------- */

  const WATCH_TITLE_SELECTOR = [
    'ytd-watch-metadata h1',
    '#above-the-fold #title h1',
    'h1.ytd-watch-metadata'
  ].join(',');

  function watchEntry(id) {
    const titleEl =
      document.querySelector('ytd-watch-metadata h1 yt-formatted-string') ||
      document.querySelector(WATCH_TITLE_SELECTOR);
    const chanEl = document.querySelector(
      'ytd-watch-metadata #owner ytd-channel-name a, #owner #channel-name a'
    );
    return {
      id,
      url: `https://www.youtube.com/watch?v=${id}`,
      title:
        clean(titleEl && (titleEl.getAttribute('title') || titleEl.textContent)) ||
        clean(document.title.replace(/ - YouTube$/, '')) ||
        'Видео без названия',
      channel: clean(chanEl && chanEl.textContent),
      thumb: `https://i.ytimg.com/vi/${id}/mqdefault.jpg`,
      addedAt: Date.now()
    };
  }

  function scanWatch() {
    const id = location.pathname === '/watch' ? videoIdFrom(location.href) : null;
    const box = id && document.querySelector(WATCH_TITLE_SELECTOR);
    const old = document.querySelector('.stopka-btn-watch');
    if (!box) {
      if (old) old.remove();
      return;
    }
    if (old && old.getAttribute('data-id') === id && old.parentElement === box) return;
    if (old) old.remove();
    const btn = makeButton(id, () => watchEntry(id));
    btn.classList.add('stopka-btn-watch');
    box.appendChild(btn);
  }

  let timer = null;
  function scheduleScan() {
    clearTimeout(timer);
    timer = setTimeout(scan, 250);
  }

  /* ---------- запуск ---------- */

  read().then((items) => {
    savedIds = new Set(items.map((x) => x.id));
    scan();
    repaintAll();
  });

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== 'local' || !changes[KEY]) return;
    savedIds = new Set((changes[KEY].newValue || []).map((x) => x.id));
    repaintAll();
  });

  new MutationObserver(scheduleScan).observe(document.documentElement, {
    childList: true,
    subtree: true
  });
  window.addEventListener('yt-navigate-finish', scheduleScan);

})();
