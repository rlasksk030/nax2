// =================== App Version ===================
const APP_VERSION = '1.3.1'; // Improved OCR parsing with better pattern matching

// =================== Storage ===================
const STORAGE_KEYS = { products: 'kreamprice.products', settings: 'kreamprice.settings' };

function loadJSON(key, fallback) {
  try { const raw = localStorage.getItem(key); return raw ? JSON.parse(raw) : fallback; }
  catch { return fallback; }
}
function saveJSON(key, value) { localStorage.setItem(key, JSON.stringify(value)); }

// =================== Utilities ===================
function uuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = Math.random() * 16 | 0, v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}
function fmtNumber(n) { return (n ?? 0).toLocaleString('ko-KR'); }
function fmtDate(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  return d.toLocaleDateString('ko-KR', { year: 'numeric', month: 'short', day: 'numeric' });
}
function fmtDateTime(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  return d.toLocaleString('ko-KR', { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}
function escapeHTML(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}
function escapeAttr(s) { return escapeHTML(s); }

// =================== Models ===================
function createProduct({ id = uuid(), name, brand, imageURL = '', kreamURL = '', currentPrice, targetPrice, size = '', retailPrice, lastNotifiedAt = null, priceHistory = [] }) {
  return { id, name, brand, imageURL, kreamURL, currentPrice, targetPrice, size, retailPrice, lastNotifiedAt, priceHistory };
}

// =================== ProductStore ===================
const ProductStore = {
  products: [],
  listeners: [],
  init() {
    const saved = loadJSON(STORAGE_KEYS.products, null);
    this.products = (saved && Array.isArray(saved) && saved.length > 0) ? saved : this.getSamples();
    if (!saved) this.save();
  },
  save() { saveJSON(STORAGE_KEYS.products, this.products); this.listeners.forEach(fn => fn()); },
  subscribe(fn) { this.listeners.push(fn); return () => { this.listeners = this.listeners.filter(l => l !== fn); }; },
  add(product) { this.products.push(product); this.save(); },
  remove(id) { this.products = this.products.filter(p => p.id !== id); this.save(); },
  update(product) { const idx = this.products.findIndex(p => p.id === product.id); if (idx >= 0) { this.products[idx] = product; this.save(); } },
  getSamples() {
    const today = Date.now(), day = 86400000;
    const history = (base, variances) => variances.map((v, i) => ({ id: uuid(), date: new Date(today - (variances.length - 1 - i) * 2 * day).toISOString(), price: base + v }));
    return [
      createProduct({ name: "Air Force 1 '07", brand: 'Nike', currentPrice: 133000, targetPrice: 125000, size: '270', retailPrice: 139000, priceHistory: history(135000, [0, -2000, 1500, -3500, 2500, -1000, 500, -2000]) }),
      createProduct({ name: 'Samba OG', brand: 'adidas', currentPrice: 158000, targetPrice: 140000, size: '265', retailPrice: 149000, priceHistory: history(160000, [0, 3000, -1000, 2500, -2500, 500, -2000, -2000]) }),
      createProduct({ name: 'Dunk Low Panda', brand: 'Nike', currentPrice: 145000, targetPrice: 130000, size: '275', retailPrice: 129000, priceHistory: history(150000, [0, -1000, -2000, 1500, -500, -1000, -500, -5000]) })
    ];
  }
};

// =================== SettingsStore ===================
const SettingsStore = {
  monthlyBudget: 0,
  notificationsEnabled: true,
  notificationCooldownHours: 6,
  listeners: [],
  init() {
    const s = loadJSON(STORAGE_KEYS.settings, {});
    this.monthlyBudget = s.monthlyBudget ?? 0;
    this.notificationsEnabled = s.notificationsEnabled ?? true;
    this.notificationCooldownHours = Math.max(1, Math.min(72, s.notificationCooldownHours ?? 6));
  },
  save() {
    saveJSON(STORAGE_KEYS.settings, { monthlyBudget: this.monthlyBudget, notificationsEnabled: this.notificationsEnabled, notificationCooldownHours: this.notificationCooldownHours });
    this.listeners.forEach(fn => fn());
  },
  subscribe(fn) { this.listeners.push(fn); return () => { this.listeners = this.listeners.filter(l => l !== fn); }; }
};

const CooldownConfig = { min: 1, max: 72 };

// =================== NotificationService ===================
const NotificationService = {
  async requestPermission() {
    if (!('Notification' in window)) return 'unsupported';
    if (Notification.permission === 'default') return await Notification.requestPermission();
    return Notification.permission;
  },
  tryNotify(product) {
    if (!SettingsStore.notificationsEnabled) return null;
    if (!('Notification' in window) || Notification.permission !== 'granted') return null;
    const cooldownMs = SettingsStore.notificationCooldownHours * 60 * 60 * 1000;
    if (product.lastNotifiedAt && (Date.now() - new Date(product.lastNotifiedAt).getTime()) < cooldownMs) return null;
    new Notification('목표가 도달!', { body: `${product.brand} ${product.name}: ${fmtNumber(product.currentPrice)}원`, tag: product.id });
    return new Date().toISOString();
  }
};

// =================== KreamService ===================
const KreamService = {
  proxies: [ u => `https://api.allorigins.win/raw?url=${encodeURIComponent(u)}`, u => `https://corsproxy.io/?${encodeURIComponent(u)}` ],
  isKreamURL(url) { try { return new URL(url).hostname.includes('kream.co.kr'); } catch { return false; } },
  async fetchProductInfo(urlString) {
    const url = urlString.trim();
    if (!url) throw new Error('URL이 비어 있습니다.');
    if (!this.isKreamURL(url)) throw new Error('Kream(kream.co.kr) 링크가 아닙니다.');
    let html = null, lastError = null;
    for (const proxyFn of this.proxies) {
      try {
        const res = await fetch(proxyFn(url), { cache: 'no-store' });
        if (!res.ok) { lastError = new Error(`HTTP ${res.status}`); continue; }
        html = await res.text();
        if (html && html.length > 500) break;
      } catch (e) { lastError = e; }
    }
    if (!html) throw lastError ?? new Error('페이지를 가져오지 못했습니다.');
    const info = this.parseHTML(html);
    if (!info.brand && !info.name && !info.currentPrice) throw new Error('상품 정보를 찾지 못했습니다.');
    return info;
  },
  parseHTML(html) {
    const info = { brand: null, name: null, currentPrice: null, retailPrice: null, imageURL: null };
    const ogImage = this.metaContent(html, 'og:image', 'property');
    if (ogImage) info.imageURL = ogImage;
    const rawTitle = this.metaContent(html, 'og:title', 'property') ?? this.metaContent(html, 'title', 'name') ?? this.titleTag(html);
    if (rawTitle) {
      const { brand, name } = this.splitTitle(rawTitle);
      info.brand = brand;
      info.name = name;
    }
    const ld = this.extractJSONLD(html);
    if (ld) {
      if (!info.brand && ld.brand) info.brand = ld.brand;
      if (!info.name && ld.name) info.name = ld.name;
      if (ld.price) info.currentPrice = ld.price;
    }
    if (!info.currentPrice) {
      info.currentPrice = this.regexPrice(html, [/"releasePrice"\s*:\s*"?(\d+)/, /"price"\s*:\s*"?(\d+)/, /즉시\s*구매가[^0-9]*([\d,]+)\s*원/, /즉시[^0-9]{0,10}([\d,]+)\s*원/]);
    }
    info.retailPrice = this.regexPrice(html, [/"originalPrice"\s*:\s*"?(\d+)/, /"retailPrice"\s*:\s*"?(\d+)/, /발매가[^0-9]*([\d,]+)\s*원/, /정가[^0-9]*([\d,]+)\s*원/]);
    return info;
  },
  metaContent(html, key, attr) {
    const esc = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const m = html.match(new RegExp(`<meta[^>]*${attr}=["']${esc}["'][^>]*content=["']([^"']+)["']`, 'i')) || html.match(new RegExp(`<meta[^>]*content=["']([^"']+)["'][^>]*${attr}=["']${esc}["']`, 'i'));
    return m ? m[1] : null;
  },
  titleTag(html) { const m = html.match(/<title[^>]*>([^<]+)<\/title>/i); return m ? m[1] : null; },
  extractJSONLD(html) {
    const re = /<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
    let match;
    while ((match = re.exec(html))) {
      try {
        const parsed = JSON.parse(match[1].trim());
        const found = this.findProductNode(parsed);
        if (found) return found;
      } catch {}
    }
    return null;
  },
  findProductNode(obj) {
    if (Array.isArray(obj)) { for (const item of obj) { const found = this.findProductNode(item); if (found) return found; } return null; }
    if (!obj || typeof obj !== 'object') return null;
    if (obj['@graph']) { const found = this.findProductNode(obj['@graph']); if (found) return found; }
    const type = Array.isArray(obj['@type']) ? obj['@type'][0] : obj['@type'];
    if (typeof type === 'string' && type.toLowerCase().includes('product')) {
      const result = { name: null, brand: null, price: null };
      result.name = obj.name ?? null;
      if (typeof obj.brand === 'string') result.brand = obj.brand;
      else if (obj.brand && typeof obj.brand === 'object') result.brand = obj.brand.name ?? null;
      let offers = obj.offers;
      if (Array.isArray(offers)) offers = offers[0];
      if (offers && offers.price != null) { const digits = String(offers.price).replace(/[^\d]/g, ''); if (digits) result.price = parseInt(digits, 10); }
      return result;
    }
    return null;
  },
  regexPrice(text, patterns) {
    for (const re of patterns) {
      const m = text.match(re);
      if (m) {
        const digits = m[1].replace(/[^\d]/g, '');
        const v = parseInt(digits, 10);
        if (!isNaN(v) && v > 1000) return v;
      }
    }
    return null;
  },
  splitTitle(title) {
    const suffixes = ['| KREAM', '| 크림', '- KREAM', '- 크림'];
    let cleaned = title;
    for (const s of suffixes) {
      const i = cleaned.toLowerCase().indexOf(s.toLowerCase());
      if (i >= 0) cleaned = cleaned.slice(0, i);
    }
    cleaned = cleaned.trim();
    if (!cleaned) return { brand: null, name: null };
    const spaceIdx = cleaned.indexOf(' ');
    return spaceIdx > 0 ? { brand: cleaned.slice(0, spaceIdx), name: cleaned.slice(spaceIdx + 1) } : { brand: null, name: cleaned };
  }
};

// =================== App ===================
const App = {
  currentTab: 'wishlist',
  wishlistFilter: false,
  currentChart: null,
  init() {
    ProductStore.init();
    SettingsStore.init();
    ProductStore.subscribe(() => this.render());
    SettingsStore.subscribe(() => this.render());
    document.querySelectorAll('.tab-button').forEach(btn => btn.addEventListener('click', () => {
      const tab = btn.dataset.tab;
      if (tab === 'add') { this.openAddModal(); return; }
      this.switchTab(tab);
    }));
    document.getElementById('modal-backdrop').addEventListener('click', e => { if (e.target.id === 'modal-backdrop') this.closeModal(); });
    this.render();
    if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
  },
  switchTab(tab) {
    this.currentTab = tab;
    document.querySelectorAll('.tab-button').forEach(b => b.classList.toggle('active', b.dataset.tab === tab));
    this.render();
  },
  render() {
    const main = document.getElementById('main-content');
    const title = document.getElementById('nav-title');
    switch (this.currentTab) {
      case 'wishlist':
        title.textContent = '위시리스트';
        main.innerHTML = this.renderWishlist();
        this.bindWishlistEvents();
        break;
      case 'compare':
        title.textContent = '가격 비교';
        main.innerHTML = this.renderCompare();
        break;
      case 'settings':
        title.textContent = '설정';
        main.innerHTML = this.renderSettings();
        this.bindSettingsEvents();
        break;
    }
  },
  renderWishlist() {
    const products = this.wishlistFilter ? ProductStore.products.filter(p => p.currentPrice < p.retailPrice) : ProductStore.products;
    let html = `<div class="filter-toggle"><div><div class="label-text">크더싼</div><div class="sub-text">정가보다 현재가가 저렴한 상품만 보기</div></div><label class="switch"><input type="checkbox" id="cheap-toggle" ${this.wishlistFilter ? 'checked' : ''}><span class="slider"></span></label></div>`;
    if (products.length === 0) {
      html += `<div class="empty-state"><div class="icon">♡</div><div class="text">${this.wishlistFilter ? '크더싼 상품이 없습니다.' : '저장된 상품이 없습니다.'}</div></div>`;
      return html;
    }
    products.forEach(p => {
      const cheaper = p.currentPrice < p.retailPrice;
      html += `<div class="wishlist-row" data-id="${p.id}"><button class="delete-btn" data-delete="${p.id}">삭제</button><div class="row-header"><div>${escapeHTML(p.brand)}</div><div>사이즈 ${escapeHTML(p.size)}</div></div><div class="name">${escapeHTML(p.name)}</div><div class="price-line"><span class="price">${fmtNumber(p.currentPrice)}원</span><span class="target">목표 ${fmtNumber(p.targetPrice)}원</span></div>${cheaper ? `<div class="cheap-badge">↓ 정가 대비 ${fmtNumber(p.retailPrice - p.currentPrice)}원 저렴</div>` : ''}</div>`;
    });
    return html;
  },
  bindWishlistEvents() {
    const toggle = document.getElementById('cheap-toggle');
    if (toggle) toggle.addEventListener('change', e => { this.wishlistFilter = e.target.checked; this.render(); });
    document.querySelectorAll('.wishlist-row').forEach(row => {
      row.addEventListener('click', e => { if (!e.target.dataset.delete) this.openDetail(row.dataset.id); });
    });
    document.querySelectorAll('[data-delete]').forEach(btn => {
      btn.addEventListener('click', e => { e.stopPropagation(); const id = btn.dataset.delete; if (confirm('이 상품을 삭제할까요?')) ProductStore.remove(id); });
    });
  },
  renderCompare() {
    if (ProductStore.products.length === 0) return `<div class="empty-state"><div class="icon">⇅</div><div class="text">비교할 상품이 없습니다.</div></div>`;
    return ProductStore.products.map(p => {
      const diff = p.retailPrice - p.currentPrice;
      const pct = p.retailPrice > 0 ? (diff / p.retailPrice * 100).toFixed(1) : '0.0';
      const diffClass = diff > 0 ? 'diff-positive' : 'diff-negative';
      const kreamBtn = p.kreamURL ? `<div class="kream-link-container"><a class="kream-link-btn" href="${escapeAttr(p.kreamURL)}" target="_blank" rel="noopener"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 17l10-10M17 7v10H7"/></svg> 크림에서 보기</a></div>` : '';
      return `<div class="compare-row"><div class="brand-text">${escapeHTML(p.brand)}</div><div class="name-text">${escapeHTML(p.name)}</div><div class="info-row"><span class="label">현재가</span><span class="value">${fmtNumber(p.currentPrice)}원</span></div><div class="info-row"><span class="label">정가</span><span class="value" style="color: var(--secondary-label)">${fmtNumber(p.retailPrice)}원</span></div><div class="info-row"><span class="label">차액</span><span class="value ${diffClass}">${fmtNumber(diff)}원 (${pct}%)</span></div>${kreamBtn}</div>`;
    }).join('');
  },
  renderSettings() {
    const quickH = [1, 3, 6, 12, 24];
    return `<div class="settings-section"><div class="section-title">월 예산 한도</div><div class="form-group"><input type="number" id="budget-input" placeholder="월 예산 (원)" value="${SettingsStore.monthlyBudget || ''}" inputmode="numeric"></div><div class="info-row"><span class="label">현재 설정</span><span class="value" style="color: var(--secondary-label)">${fmtNumber(SettingsStore.monthlyBudget)}원</span></div><div class="form-footer">한 달 동안 지출할 수 있는 최대 금액을 설정하세요.</div></div><div class="settings-section"><div class="section-title">알림</div><div class="filter-toggle"><div class="label-text">가격 알림 받기</div><label class="switch"><input type="checkbox" id="notif-toggle" ${SettingsStore.notificationsEnabled ? 'checked' : ''}><span class="slider"></span></label></div></div><div class="settings-section"><div class="section-title">알림 쿨타임</div><div class="form-group"><div class="stepper"><button class="stepper-btn" id="cooldown-dec">−</button><span class="stepper-label">쿨타임</span><span class="stepper-value"><span id="cooldown-val">${SettingsStore.notificationCooldownHours}</span>시간</span><button class="stepper-btn" id="cooldown-inc">+</button></div><div class="quick-buttons">${quickH.map(h => `<button data-hours="${h}" class="${SettingsStore.notificationCooldownHours === h ? 'selected' : ''}">${h}h</button>`).join('')}</div></div><div class="form-footer">동일한 상품에 대한 알림은 설정한 시간에 한 번만 전송됩니다. (${CooldownConfig.min}~${CooldownConfig.max}시간)</div></div><div class="settings-section"><div class="section-title">정보</div><div class="form-group"><div class="info-row"><span class="label">앱 이름</span><span class="value" style="color: var(--secondary-label)">KreamPrice</span></div><div class="info-row"><span class="label">버전</span><span class="value" style="color: var(--secondary-label)">1.0.0</span></div></div></div>`;
  },
  bindSettingsEvents() {
    const budget = document.getElementById('budget-input');
    if (budget) {
      budget.addEventListener('input', e => {
        const digits = e.target.value.replace(/[^\d]/g, '');
        e.target.value = digits;
        SettingsStore.monthlyBudget = parseInt(digits, 10) || 0;
        SettingsStore.save();
      });
    }
    const notif = document.getElementById('notif-toggle');
    if (notif) {
      notif.addEventListener('change', async e => {
        if (e.target.checked) {
          const perm = await NotificationService.requestPermission();
          if (perm !== 'granted') {
            alert('브라우저에서 알림 권한을 허용해주세요.');
            e.target.checked = false;
            SettingsStore.notificationsEnabled = false;
            SettingsStore.save();
            return;
          }
        }
        SettingsStore.notificationsEnabled = e.target.checked;
        SettingsStore.save();
      });
    }
    const dec = document.getElementById('cooldown-dec');
    const inc = document.getElementById('cooldown-inc');
    if (dec) dec.addEventListener('click', () => this.changeCooldown(-1));
    if (inc) inc.addEventListener('click', () => this.changeCooldown(1));
    document.querySelectorAll('[data-hours]').forEach(btn => {
      btn.addEventListener('click', () => {
        SettingsStore.notificationCooldownHours = parseInt(btn.dataset.hours, 10);
        SettingsStore.save();
      });
    });
  },
  changeCooldown(delta) {
    let v = SettingsStore.notificationCooldownHours + delta;
    v = Math.max(CooldownConfig.min, Math.min(CooldownConfig.max, v));
    SettingsStore.notificationCooldownHours = v;
    SettingsStore.save();
  },
  openDetail(id) {
    const product = ProductStore.products.find(p => p.id === id);
    if (!product) return;
    const inspection = Math.round(product.currentPrice * 0.01);
    const shipping = 3000;
    const total = product.currentPrice + inspection + shipping;
    const kreamBtn = product.kreamURL ? `<a class="kream-link-btn full-width" href="${escapeAttr(product.kreamURL)}" target="_blank" rel="noopener"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 17l10-10M17 7v10H7"/></svg> 크림에서 보기</a>` : '';
    const lastNotif = product.lastNotifiedAt ? `<div class="header-card last-notif">마지막 알림: ${fmtDateTime(product.lastNotifiedAt)}</div>` : '';
    const modal = document.getElementById('modal-content');
    modal.innerHTML = `<div class="modal-header"><button class="cancel" id="detail-close">닫기</button><h2>${escapeHTML(product.name)}</h2><span></span></div><div class="card header-card"><div class="brand">${escapeHTML(product.brand)}</div><div class="name">${escapeHTML(product.name)}</div><div class="size">사이즈 ${escapeHTML(product.size)}</div><hr><div class="info-row emphasized"><span class="label">현재가</span><span class="value">${fmtNumber(product.currentPrice)}원</span></div><div class="info-row"><span class="label">정가</span><span class="value">${fmtNumber(product.retailPrice)}원</span></div><div class="info-row"><span class="label">목표가</span><span class="value">${fmtNumber(product.targetPrice)}원</span></div>${lastNotif}${kreamBtn}</div><div class="card"><div class="calc-title">💳 결제 예상금액</div><div class="calc-line"><span class="label">상품가</span><span>${fmtNumber(product.currentPrice)}원</span></div><div class="calc-line"><span class="label">검수비 (1%)</span><span>${fmtNumber(inspection)}원</span></div><div class="calc-line"><span class="label">배송비</span><span>${fmtNumber(shipping)}원</span></div><div class="calc-total"><span class="label">총 결제금액</span><span class="value">${fmtNumber(total)}원</span></div></div><div class="card"><div class="calc-title">📈 가격 변동</div>${product.priceHistory.length === 0 ? '<div class="chart-empty">기록된 가격 데이터가 없습니다.</div>' : '<div class="chart-container"><canvas id="price-chart"></canvas></div>'}</div>`;
    document.getElementById('modal-backdrop').classList.remove('hidden');
    document.getElementById('detail-close').addEventListener('click', () => this.closeModal());
    if (product.priceHistory.length > 0 && window.Chart) {
      const ctx = document.getElementById('price-chart').getContext('2d');
      if (this.currentChart) this.currentChart.destroy();
      this.currentChart = new Chart(ctx, {
        type: 'line',
        data: {
          labels: product.priceHistory.map(r => fmtDate(r.date)),
          datasets: [{ data: product.priceHistory.map(r => r.price), borderColor: '#007AFF', backgroundColor: 'rgba(0,122,255,0.1)', tension: 0.4, pointRadius: 4, pointBackgroundColor: '#007AFF', fill: true }]
        },
        options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { display: false } }, scales: { y: { position: 'left', ticks: { callback: v => fmtNumber(v) + '원' } } } }
      });
    }
  },
  openAddModal() {
    const modal = document.getElementById('modal-content');
    modal.innerHTML = `<div class="modal-header"><button class="cancel" id="add-cancel">취소</button><h2>상품 추가</h2><button class="confirm" id="add-save" disabled>저장</button></div><div class="settings-section"><div class="section-title">스크린샷 인식</div><div class="form-group"><label for="p-image" style="display:flex;align-items:center;gap:8px;padding:12px;border:1px solid var(--separator);border-radius:8px;cursor:pointer;background:var(--tertiary-background)"><span style="font-size:18px">📸</span><span>Kream 캡처 이미지 선택</span></label><input type="file" id="p-image" accept="image/*" style="display:none"></div><div id="image-status"></div><div class="form-footer">Kream 앱 스크린샷을 업로드하면 자동으로 정보가 입력됩니다.</div></div><div class="settings-section"><div class="section-title">Kream 링크</div><div class="form-group"><div class="url-input-row"><span class="icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg></span><input type="url" id="kream-url" placeholder="https://kream.co.kr/products/…" autocomplete="off"><button class="fetch-btn" id="fetch-btn"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M5 12h14"/></svg></button></div></div><div id="fetch-status"></div><div class="form-footer">크림 상품 페이지 URL을 붙여넣으면 자동으로 정보를 채웁니다.</div></div><div class="settings-section"><div class="section-title">상품 정보</div><div class="form-group"><input type="text" id="p-brand" placeholder="브랜드 (예: Nike)"><input type="text" id="p-name" placeholder="상품명"><input type="text" id="p-size" placeholder="사이즈 (예: 270)"></div></div><div class="settings-section"><div class="section-title">가격</div><div class="form-group"><input type="number" id="p-current" placeholder="현재가" inputmode="numeric"><input type="number" id="p-target" placeholder="목표가" inputmode="numeric"><input type="number" id="p-retail" placeholder="정가" inputmode="numeric"></div></div>`;
    document.getElementById('modal-backdrop').classList.remove('hidden');
    const saveBtn = document.getElementById('add-save');
    const updateCanSave = () => {
      const brand = document.getElementById('p-brand').value.trim();
      const name = document.getElementById('p-name').value.trim();
      const current = parseInt(document.getElementById('p-current').value, 10) || 0;
      saveBtn.disabled = !(brand && name && current > 0);
    };
    ['p-brand', 'p-name', 'p-current'].forEach(id => document.getElementById(id).addEventListener('input', updateCanSave));
    document.getElementById('add-cancel').addEventListener('click', () => this.closeModal());
    const imageInput = document.getElementById('p-image');
    const imageStatus = document.getElementById('image-status');
    const recognizeImage = async (file) => {
      if (!file) return;
      imageStatus.innerHTML = '<div class="status-error"><span class="spinner"></span> 이미지 인식 중… (첫 실행 시 모델 다운로드)</div>';
      try {
        const { data: { text } } = await Tesseract.recognize(file, 'kor');
        console.log('[OCR Result]', text);
        if (!text || text.trim().length < 5) {
          imageStatus.innerHTML = '<div class="status-error">⚠ 인식된 텍스트가 너무 짧습니다. 더 명확한 스크린샷을 시도해주세요.</div>';
          return;
        }
        const info = this.parseKreamScreenshot(text);
        const filled = [];
        if (info.brand) { document.getElementById('p-brand').value = info.brand; filled.push('브랜드'); }
        if (info.name) { document.getElementById('p-name').value = info.name; filled.push('상품명'); }
        if (info.currentPrice > 0) { document.getElementById('p-current').value = info.currentPrice; filled.push('현재가'); }
        if (info.retailPrice > 0) { document.getElementById('p-retail').value = info.retailPrice; filled.push('정가'); }
        if (info.size) { document.getElementById('p-size').value = info.size; filled.push('사이즈'); }
        let statusMsg = filled.length ? `✓ 인식됨: ${filled.join(', ')}` : '⚠ 일부 정보를 찾지 못했습니다.';
        imageStatus.innerHTML = `<div class="${filled.length ? 'status-success' : 'status-error'}">${statusMsg}<br><span style="font-size:0.85em;opacity:0.7">인식된 텍스트로 값을 수정할 수 있습니다</span></div>`;
        updateCanSave();
      } catch (e) {
        const errMsg = e.message || '인식 실패';
        imageStatus.innerHTML = `<div class="status-error">⚠ ${errMsg}<br><span style="font-size:0.85em">다시 시도하거나 URL을 직접 입력하세요</span></div>`;
        console.error('[OCR Error]', e);
      }
    };
    imageInput.addEventListener('change', (e) => recognizeImage(e.target.files?.[0]));
    const urlInput = document.getElementById('kream-url');
    let lastFetched = '';
    const fetchStatus = document.getElementById('fetch-status');
    const doFetch = async (force) => {
      const url = urlInput.value.trim();
      if (!url) return;
      if (!force && url === lastFetched) return;
      lastFetched = url;
      fetchStatus.innerHTML = '<div class="status-error"><span class="spinner"></span> 가져오는 중…</div>';
      try {
        const info = await KreamService.fetchProductInfo(url);
        const filled = [];
        if (info.brand) { document.getElementById('p-brand').value = info.brand; filled.push('브랜드'); }
        if (info.name) { document.getElementById('p-name').value = info.name; filled.push('상품명'); }
        if (info.currentPrice > 0) {
          document.getElementById('p-current').value = info.currentPrice;
          filled.push('현재가');
          const tgt = document.getElementById('p-target');
          if (!tgt.value) tgt.value = Math.round(info.currentPrice * 0.95);
        }
        if (info.retailPrice > 0) {
          document.getElementById('p-retail').value = info.retailPrice;
          filled.push('정가');
        }
        fetchStatus.innerHTML = filled.length ? `<div class="status-success">✓ 자동 입력: ${filled.join(', ')}</div>` : '<div class="status-error">⚠ 상품 정보를 찾지 못했습니다.</div>';
        updateCanSave();
      } catch (e) {
        fetchStatus.innerHTML = `<div class="status-error">⚠ ${e.message || '가져오기 실패'}</div>`;
      }
    };
    urlInput.addEventListener('input', () => {
      const v = urlInput.value.trim().toLowerCase();
      if (v.startsWith('http') && v.includes('kream.co.kr/products/') && v !== lastFetched) doFetch(false);
    });
    document.getElementById('fetch-btn').addEventListener('click', () => doFetch(true));
    saveBtn.addEventListener('click', () => {
      const current = parseInt(document.getElementById('p-current').value, 10) || 0;
      const target = parseInt(document.getElementById('p-target').value, 10) || current;
      const retail = parseInt(document.getElementById('p-retail').value, 10) || current;
      const product = createProduct({
        name: document.getElementById('p-name').value.trim(),
        brand: document.getElementById('p-brand').value.trim(),
        size: document.getElementById('p-size').value.trim(),
        kreamURL: urlInput.value.trim(),
        currentPrice: current,
        targetPrice: target,
        retailPrice: retail,
        priceHistory: [{ id: uuid(), date: new Date().toISOString(), price: current }]
      });
      ProductStore.add(product);
      this.closeModal();
    });
  },
  parseKreamScreenshot(text) {
    const result = { brand: '', name: '', currentPrice: 0, retailPrice: 0, size: '' };
    const lines = text.split('\n').filter(l => l.trim().length > 0);

    // 브랜드와 상품명 추출 (처음 2-3줄에서)
    if (lines.length >= 2) {
      const firstLine = lines[0]?.trim() || '';
      const secondLine = lines[1]?.trim() || '';

      // 첫 번째 줄이 브랜드인지 상품명인지 판단 (보통 브랜드는 짧음)
      if (firstLine.length < 20 && !firstLine.match(/\d/)) {
        result.brand = firstLine;
        result.name = secondLine;
      } else {
        result.name = firstLine;
        if (lines.length >= 3) result.brand = secondLine;
      }
    }

    // 가격 추출 - 여러 패턴 시도
    // 1) "즉시 구매가 XXX원" 또는 "XXX,XXX원" 패턴
    const currentMatch = text.match(/즉시\s*구매가\s*[\d,]+|구매가\s*[\d,]+|[\d,]{3,}/);
    if (currentMatch) {
      const numStr = currentMatch[0].replace(/\D/g, '');
      result.currentPrice = parseInt(numStr, 10) || 0;
    }

    // 2) 모든 가격 찾기
    const allPrices = text.match(/[\d,]{3,}/g) || [];
    const priceValues = allPrices.map(p => parseInt(p.replace(/,/g, ''), 10)).filter(p => p > 1000 && p < 10000000);

    if (priceValues.length >= 2) {
      // 가장 작은 가격을 현재가, 가장 큰 가격을 정가로
      if (result.currentPrice === 0) result.currentPrice = Math.min(...priceValues);
      result.retailPrice = Math.max(...priceValues);
    } else if (priceValues.length === 1 && result.currentPrice === 0) {
      result.currentPrice = priceValues[0];
    }

    // 발매가 찾기 (있으면 정가로 설정)
    const retailMatch = text.match(/발매가\s*[\d,]+/);
    if (retailMatch) {
      const numStr = retailMatch[0].replace(/\D/g, '');
      result.retailPrice = parseInt(numStr, 10) || result.retailPrice;
    }

    // 사이즈 추출 (여러 패턴)
    const sizePatterns = [
      /사이즈[:\s]*(\d+\.?\d*)/,
      /Size[:\s]*(\d+\.?\d*)/,
      /(?:^|\s)(\d{2,3})(?:\s|$)/m
    ];
    for (const pattern of sizePatterns) {
      const match = text.match(pattern);
      if (match) {
        result.size = match[1];
        break;
      }
    }

    return result;
  },
  closeModal() {
    document.getElementById('modal-backdrop').classList.add('hidden');
    document.getElementById('modal-content').innerHTML = '';
    if (this.currentChart) { this.currentChart.destroy(); this.currentChart = null; }
  }
};

document.addEventListener('DOMContentLoaded', () => App.init());
