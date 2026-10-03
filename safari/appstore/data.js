// Вымышленные видео для скриншотов. Превью рисуются SVG, без чужих картинок.
// LANG задаёт shoot.py (en | ru).
const VIDEOS_BY_LANG = {
  en: [
    { title: 'How to cook perfect rice: three ways', channel: 'Slow Kitchen', views: '214K views', dur: '12:48' },
    { title: 'Altai Mountains in 7 days: route and budget', channel: 'Backpack & Map', views: '96K views', dur: '24:10' },
    { title: 'Watercolor basics for beginners', channel: 'Quiet Studio', views: '58K views', dur: '18:32' },
    { title: 'Why cats sleep so much', channel: 'Science Made Simple', views: '1.2M views', dur: '9:05' },
    { title: 'A home server from an old laptop', channel: 'Hardware at Home', views: '340K views', dur: '31:17' },
    { title: 'Morning stretch in 15 minutes', channel: 'Calm Rhythm', views: '77K views', dur: '15:00' },
  ],
  ru: [
    { title: 'Как сварить идеальный рис: три способа', channel: 'Кухня без спешки', views: '214 тыс. просмотров', dur: '12:48' },
    { title: 'Горы Алтая за 7 дней: маршрут и бюджет', channel: 'Рюкзак и карта', views: '96 тыс. просмотров', dur: '24:10' },
    { title: 'Основы акварели для начинающих', channel: 'Тихая мастерская', views: '58 тыс. просмотров', dur: '18:32' },
    { title: 'Почему кошки столько спят', channel: 'Наука просто', views: '1,2 млн просмотров', dur: '9:05' },
    { title: 'Домашний сервер из старого ноутбука', channel: 'Железо дома', views: '340 тыс. просмотров', dur: '31:17' },
    { title: 'Утренняя растяжка за 15 минут', channel: 'Спокойный ритм', views: '77 тыс. просмотров', dur: '15:00' },
  ],
};
const VIDEOS = VIDEOS_BY_LANG[LANG];

const PALETTES = [
  ['#f4a259', '#bc4b51', '#fff3d6'], ['#2a9d8f', '#264653', '#e9f5db'], ['#8ecae6', '#219ebc', '#ffffff'],
  ['#c9ada7', '#4a4e69', '#f2e9e4'], ['#90be6d', '#277da1', '#f9f7f3'], ['#ffb4a2', '#6d597a', '#fff1e6'],
];
const SHAPES = [
  (c) => `<circle cx="160" cy="95" r="48" fill="${c}"/><rect x="60" y="140" width="200" height="14" rx="7" fill="${c}" opacity=".6"/>`,
  (c) => `<path d="M0 180 L90 70 L150 140 L210 50 L320 180 Z" fill="${c}" opacity=".85"/><circle cx="250" cy="45" r="18" fill="${c}"/>`,
  (c) => `<path d="M40 150 C 100 40, 220 40, 280 150" stroke="${c}" stroke-width="14" fill="none" stroke-linecap="round"/><circle cx="160" cy="70" r="12" fill="${c}"/>`,
  (c) => `<ellipse cx="160" cy="118" rx="80" ry="40" fill="${c}"/><circle cx="110" cy="78" r="22" fill="${c}"/><circle cx="210" cy="78" r="22" fill="${c}"/>`,
  (c) => `<rect x="80" y="50" width="160" height="90" rx="8" fill="none" stroke="${c}" stroke-width="10"/><rect x="60" y="148" width="200" height="12" rx="6" fill="${c}"/>`,
  (c) => `<circle cx="160" cy="90" r="56" fill="none" stroke="${c}" stroke-width="12"/><circle cx="160" cy="90" r="18" fill="${c}"/>`,
];

function thumb(i) {
  const [a, b, c] = PALETTES[i % PALETTES.length];
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 180">` +
    `<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient></defs>` +
    `<rect width="320" height="180" fill="url(#g)"/>${SHAPES[i % SHAPES.length](c)}</svg>`;
  return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
}

// Записи для попапа — в формате chrome.storage.local, как пишет content.js.
const SAVED = [0, 1, 3, 4].map((i, k) => ({
  id: 'demo' + i, url: 'https://www.youtube.com/watch?v=demo' + i,
  title: VIDEOS[i].title, channel: VIDEOS[i].channel, thumb: thumb(i),
  addedAt: Date.UTC(2026, 9, 3 - k),
}));
