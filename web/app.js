// =================== App Version ===================
const APP_VERSION = '1.7.1'; // Wishlist Kream link, history migration, image previews

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
    this.migratePriceHistory();
    if (!saved) this.save();
  },
  migratePriceHistory() {
    // 가격 히스토리가 모두 일주일 이전이면 날짜를 최근으로 시프트 (상대적 간격 유지)
    const now = Date.now();
    const weekAgo = now - 7 * 86400000;
    let migrated = false;
    this.products.forEach(p => {
      if (!p.priceHistory || p.priceHistory.length === 0) return;
      const times = p.priceHistory.map(r => new Date(r.date).getTime()).filter(t => !isNaN(t));
      if (times.length === 0) return;
      const latestTime = Math.max(...times);
      if (latestTime < weekAgo) {
        const shift = now - latestTime;
        p.priceHistory.forEach(r => {
          const t = new Date(r.date).getTime();
          if (!isNaN(t)) r.date = new Date(t + shift).toISOString();
        });
        migrated = true;
      }
    });
    if (migrated) saveJSON(STORAGE_KEYS.products, this.products);
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
  shoeSize: '',
  clothingSize: '',
  listeners: [],
  init() {
    const s = loadJSON(STORAGE_KEYS.settings, {});
    this.monthlyBudget = s.monthlyBudget ?? 0;
    this.notificationsEnabled = s.notificationsEnabled ?? true;
    this.notificationCooldownHours = Math.max(1, Math.min(72, s.notificationCooldownHours ?? 6));
    this.shoeSize = s.shoeSize ?? '';
    this.clothingSize = s.clothingSize ?? '';
  },
  save() {
    saveJSON(STORAGE_KEYS.settings, {
      monthlyBudget: this.monthlyBudget,
      notificationsEnabled: this.notificationsEnabled,
      notificationCooldownHours: this.notificationCooldownHours,
      shoeSize: this.shoeSize,
      clothingSize: this.clothingSize
    });
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
  proxies: [
    { name: 'corsproxy.io', build: u => `https://corsproxy.io/?${encodeURIComponent(u)}` },
    { name: 'allorigins', build: u => `https://api.allorigins.win/raw?url=${encodeURIComponent(u)}` },
    { name: 'codetabs', build: u => `https://api.codetabs.com/v1/proxy?quest=${encodeURIComponent(u)}` },
    { name: 'cors.sh', build: u => `https://proxy.cors.sh/${u}` },
    { name: 'cors.eu', build: u => `https://cors.eu.org/${u}` },
    { name: 'thingproxy', build: u => `https://thingproxy.freeboard.io/fetch/${u}` }
  ],
  isKreamURL(url) { try { return new URL(url).hostname.includes('kream.co.kr'); } catch { return false; } },
  async fetchWithTimeout(url, ms = 15000) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), ms);
    try {
      return await fetch(url, { cache: 'no-store', signal: controller.signal, headers: { 'Accept': 'text/html,application/xhtml+xml' } });
    } finally {
      clearTimeout(timer);
    }
  },
  async fetchProductInfo(urlString) {
    const url = urlString.trim();
    if (!url) throw new Error('URL이 비어 있습니다.');
    if (!this.isKreamURL(url)) throw new Error('Kream(kream.co.kr) 링크가 아닙니다.');
    let html = null;
    const errors = [];
    for (const proxy of this.proxies) {
      try {
        console.log(`[KreamService] Trying ${proxy.name}...`);
        const res = await this.fetchWithTimeout(proxy.build(url));
        if (!res.ok) {
          errors.push(`${proxy.name}: HTTP ${res.status}`);
          console.warn(`[KreamService] ${proxy.name} HTTP ${res.status}`);
          continue;
        }
        const text = await res.text();
        if (text && text.length > 500 && !text.toLowerCase().includes('error code: 520')) {
          html = text;
          console.log(`[KreamService] Success via ${proxy.name}`);
          break;
        } else {
          errors.push(`${proxy.name}: 빈 응답`);
        }
      } catch (e) {
        errors.push(`${proxy.name}: ${e.name === 'AbortError' ? '타임아웃' : (e.message || '오류')}`);
        console.warn(`[KreamService] ${proxy.name} failed:`, e);
      }
    }
    if (!html) {
      throw new Error('모든 프록시 서버에 연결 실패. 스크린샷 인식을 대신 사용해보세요.');
    }
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
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('sw.js').then(reg => {
        // 주기적으로 업데이트 체크
        setInterval(() => reg.update(), 60000);
        reg.addEventListener('updatefound', () => {
          const newWorker = reg.installing;
          if (!newWorker) return;
          newWorker.addEventListener('statechange', () => {
            if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
              console.log('[SW] New version available, reloading...');
              newWorker.postMessage({ type: 'SKIP_WAITING' });
              setTimeout(() => window.location.reload(), 500);
            }
          });
        });
        // 페이지 로드 시 즉시 업데이트 체크
        reg.update();
      }).catch(err => console.warn('[SW] Registration failed:', err));
      // controller 변경 시 리로드 (새 SW 활성화)
      let refreshing = false;
      navigator.serviceWorker.addEventListener('controllerchange', () => {
        if (refreshing) return;
        refreshing = true;
        window.location.reload();
      });
    }
  },
  switchTab(tab) {
    this.currentTab = tab;
    document.querySelectorAll('.tab-button').forEach(b => b.classList.toggle('active', b.dataset.tab === tab));
    this.render();
  },
  render() {
    const main = document.getElementById('main-content');
    const title = document.getElementById('nav-title');
    // 포커스/커서 위치 보존 (재렌더 시 입력 끊김 방지)
    const ae = document.activeElement;
    const activeId = ae && ae.id ? ae.id : null;
    const cursorPos = activeId && ae.selectionStart != null ? ae.selectionStart : null;
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
    if (activeId) {
      const el = document.getElementById(activeId);
      if (el && typeof el.focus === 'function') {
        el.focus();
        if (cursorPos != null && typeof el.setSelectionRange === 'function') {
          try { el.setSelectionRange(cursorPos, cursorPos); } catch {}
        }
      }
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
      const sizeLabel = p.size ? `사이즈 ${escapeHTML(p.size)}` : '';
      const kreamHref = p.kreamURL && p.kreamURL.trim()
        ? p.kreamURL
        : `https://kream.co.kr/search?keyword=${encodeURIComponent((p.brand || '') + ' ' + (p.name || '')).trim()}`;
      html += `<div class="wishlist-row" data-id="${p.id}"><div class="row-actions"><a class="row-btn kream-btn" href="${escapeAttr(kreamHref)}" target="_blank" rel="noopener" data-kream="1">크림</a><button class="row-btn edit-btn" data-edit="${p.id}">수정</button><button class="row-btn delete-btn" data-delete="${p.id}">삭제</button></div><div class="row-header"><div class="brand-line">${escapeHTML(p.brand)}</div></div><div class="name">${escapeHTML(p.name)}</div><div class="price-line"><span class="price">${fmtNumber(p.currentPrice)}원</span><span class="target">${sizeLabel ? sizeLabel + ' · ' : ''}목표 ${fmtNumber(p.targetPrice)}원</span></div>${cheaper ? `<div class="cheap-badge">↓ 정가 대비 ${fmtNumber(p.retailPrice - p.currentPrice)}원 저렴</div>` : ''}</div>`;
    });
    return html;
  },
  bindWishlistEvents() {
    const toggle = document.getElementById('cheap-toggle');
    if (toggle) toggle.addEventListener('change', e => { this.wishlistFilter = e.target.checked; this.render(); });
    document.querySelectorAll('.wishlist-row').forEach(row => {
      row.addEventListener('click', e => {
        if (e.target.closest('[data-delete]') || e.target.closest('[data-edit]') || e.target.closest('[data-kream]')) return;
        this.openDetail(row.dataset.id);
      });
    });
    document.querySelectorAll('[data-delete]').forEach(btn => {
      btn.addEventListener('click', e => { e.stopPropagation(); const id = btn.dataset.delete; if (confirm('이 상품을 삭제할까요?')) ProductStore.remove(id); });
    });
    document.querySelectorAll('[data-edit]').forEach(btn => {
      btn.addEventListener('click', e => { e.stopPropagation(); this.openEditModal(btn.dataset.edit); });
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
    return `<div class="settings-section"><div class="section-title">내 사이즈</div><div class="form-group"><input type="text" id="shoe-size-input" placeholder="신발 사이즈 (예: 270)" value="${escapeAttr(SettingsStore.shoeSize)}" inputmode="numeric"><input type="text" id="clothing-size-input" placeholder="옷 사이즈 (예: M, L, 100)" value="${escapeAttr(SettingsStore.clothingSize)}"></div><div class="form-footer">스크린샷에 여러 사이즈 가격이 있으면 내 사이즈 가격이 우선 입력됩니다.</div></div><div class="settings-section"><div class="section-title">월 예산 한도</div><div class="form-group"><input type="number" id="budget-input" placeholder="월 예산 (원)" value="${SettingsStore.monthlyBudget || ''}" inputmode="numeric"></div><div class="info-row"><span class="label">현재 설정</span><span class="value" style="color: var(--secondary-label)">${fmtNumber(SettingsStore.monthlyBudget)}원</span></div><div class="form-footer">한 달 동안 지출할 수 있는 최대 금액을 설정하세요.</div></div><div class="settings-section"><div class="section-title">알림</div><div class="filter-toggle"><div class="label-text">가격 알림 받기</div><label class="switch"><input type="checkbox" id="notif-toggle" ${SettingsStore.notificationsEnabled ? 'checked' : ''}><span class="slider"></span></label></div></div><div class="settings-section"><div class="section-title">알림 쿨타임</div><div class="form-group"><div class="stepper"><button class="stepper-btn" id="cooldown-dec">−</button><span class="stepper-label">쿨타임</span><span class="stepper-value"><span id="cooldown-val">${SettingsStore.notificationCooldownHours}</span>시간</span><button class="stepper-btn" id="cooldown-inc">+</button></div><div class="quick-buttons">${quickH.map(h => `<button data-hours="${h}" class="${SettingsStore.notificationCooldownHours === h ? 'selected' : ''}">${h}h</button>`).join('')}</div></div><div class="form-footer">동일한 상품에 대한 알림은 설정한 시간에 한 번만 전송됩니다. (${CooldownConfig.min}~${CooldownConfig.max}시간)</div></div><div class="settings-section"><div class="section-title">정보</div><div class="form-group"><div class="info-row"><span class="label">앱 이름</span><span class="value" style="color: var(--secondary-label)">KreamPrice</span></div><div class="info-row"><span class="label">버전</span><span class="value" style="color: var(--secondary-label)">${APP_VERSION}</span></div></div></div>`;
  },
  bindSettingsEvents() {
    const shoe = document.getElementById('shoe-size-input');
    if (shoe) {
      shoe.addEventListener('input', e => {
        SettingsStore.shoeSize = e.target.value.trim();
        SettingsStore.save();
      });
    }
    const clothing = document.getElementById('clothing-size-input');
    if (clothing) {
      clothing.addEventListener('input', e => {
        SettingsStore.clothingSize = e.target.value.trim();
        SettingsStore.save();
      });
    }
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
    // 최근 일주일 가격 히스토리만 필터링
    const weekAgo = Date.now() - 7 * 86400000;
    const weekHistory = (product.priceHistory || []).filter(r => new Date(r.date).getTime() >= weekAgo);
    const modal = document.getElementById('modal-content');
    modal.innerHTML = `<div class="modal-header"><button class="cancel" id="detail-close">닫기</button><h2>${escapeHTML(product.name)}</h2><button class="confirm" id="detail-edit">수정</button></div><div class="card header-card"><div class="brand">${escapeHTML(product.brand)}</div><div class="name">${escapeHTML(product.name)}</div><div class="size">사이즈 ${escapeHTML(product.size)}</div><hr><div class="info-row emphasized"><span class="label">현재가</span><span class="value">${fmtNumber(product.currentPrice)}원</span></div><div class="info-row"><span class="label">정가</span><span class="value">${fmtNumber(product.retailPrice)}원</span></div><div class="info-row"><span class="label">목표가</span><span class="value">${fmtNumber(product.targetPrice)}원</span></div>${lastNotif}${kreamBtn}</div><div class="card"><div class="calc-title">💳 결제 예상금액</div><div class="calc-line"><span class="label">상품가</span><span>${fmtNumber(product.currentPrice)}원</span></div><div class="calc-line"><span class="label">검수비 (1%)</span><span>${fmtNumber(inspection)}원</span></div><div class="calc-line"><span class="label">배송비</span><span>${fmtNumber(shipping)}원</span></div><div class="calc-total"><span class="label">총 결제금액</span><span class="value">${fmtNumber(total)}원</span></div></div><div class="card"><div class="calc-title">📈 최근 일주일 가격 변동</div>${weekHistory.length === 0 ? '<div class="chart-empty">최근 일주일 동안 기록된 가격 변동이 없습니다.</div>' : '<div class="chart-container"><canvas id="price-chart"></canvas></div>'}</div>`;
    document.getElementById('modal-backdrop').classList.remove('hidden');
    document.getElementById('detail-close').addEventListener('click', () => this.closeModal());
    document.getElementById('detail-edit').addEventListener('click', () => this.openEditModal(product.id));
    if (weekHistory.length > 0 && window.Chart) {
      const ctx = document.getElementById('price-chart').getContext('2d');
      if (this.currentChart) this.currentChart.destroy();
      this.currentChart = new Chart(ctx, {
        type: 'line',
        data: {
          labels: weekHistory.map(r => fmtDate(r.date)),
          datasets: [{ data: weekHistory.map(r => r.price), borderColor: '#007AFF', backgroundColor: 'rgba(0,122,255,0.1)', tension: 0.4, pointRadius: 4, pointBackgroundColor: '#007AFF', fill: true }]
        },
        options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { display: false } }, scales: { y: { position: 'left', ticks: { callback: v => fmtNumber(v) + '원' } } } }
      });
    }
  },
  openAddModal() {
    const modal = document.getElementById('modal-content');
    const defaultSize = SettingsStore.shoeSize || '';
    modal.innerHTML = `<div class="modal-header"><button class="cancel" id="add-cancel">취소</button><h2>상품 추가</h2><button class="confirm" id="add-save" disabled>저장</button></div><div class="settings-section"><div class="section-title">스크린샷 인식 (최대 3장)</div><div class="form-group"><label for="p-image" style="display:flex;align-items:center;gap:8px;padding:12px;border:1px solid var(--separator);border-radius:8px;cursor:pointer;background:var(--tertiary-background)"><span style="font-size:18px">📸</span><span>Kream 캡처 이미지 선택 (최대 3장)</span></label><input type="file" id="p-image" accept="image/*" multiple style="display:none"></div><div id="image-preview-grid" class="image-preview-grid"></div><div id="image-status"></div><div class="form-footer">여러 장의 스크린샷을 한 번에 선택하면 종합해서 정보를 자동 입력합니다. 첨부 후 사진을 보고 아래 입력란을 직접 수정할 수 있습니다.</div></div><div class="settings-section"><div class="section-title">Kream 링크</div><div class="form-group"><div class="url-input-row"><span class="icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg></span><input type="url" id="kream-url" placeholder="https://kream.co.kr/products/…" autocomplete="off"><button class="fetch-btn" id="fetch-btn"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M5 12h14"/></svg></button></div></div><div id="fetch-status"></div><div class="form-footer">크림 상품 페이지 URL을 붙여넣으면 자동으로 정보를 채웁니다.</div></div><div class="settings-section"><div class="section-title">상품 정보</div><div class="form-group"><input type="text" id="p-brand" placeholder="브랜드 (예: Nike)"><input type="text" id="p-name" placeholder="상품명"><input type="text" id="p-size" placeholder="사이즈 (예: 270)" value="${escapeAttr(defaultSize)}"></div></div><div class="settings-section"><div class="section-title">가격</div><div class="form-group"><input type="number" id="p-current" placeholder="현재가" inputmode="numeric"><input type="number" id="p-target" placeholder="목표가" inputmode="numeric"><input type="number" id="p-retail" placeholder="정가" inputmode="numeric"></div></div>`;
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
    const previewGrid = document.getElementById('image-preview-grid');
    const renderPreviews = (files) => {
      previewGrid.innerHTML = '';
      Array.from(files).slice(0, 3).forEach((file, idx) => {
        const wrapper = document.createElement('div');
        wrapper.className = 'image-preview-item';
        const img = document.createElement('img');
        img.src = URL.createObjectURL(file);
        img.alt = `캡처 ${idx + 1}`;
        img.onload = () => URL.revokeObjectURL(img.src);
        const label = document.createElement('span');
        label.className = 'image-preview-label';
        label.textContent = `${idx + 1}`;
        wrapper.appendChild(img);
        wrapper.appendChild(label);
        previewGrid.appendChild(wrapper);
      });
    };
    const recognizeImages = async (files) => {
      if (!files || files.length === 0) {
        previewGrid.innerHTML = '';
        return;
      }
      renderPreviews(files);
      const list = Array.from(files).slice(0, 3); // 최대 3장
      const total = list.length;
      const parsed = [];
      const fullText = [];
      for (let i = 0; i < total; i++) {
        const file = list[i];
        imageStatus.innerHTML = `<div class="status-error"><span class="spinner"></span> ${i + 1}/${total} 번째 이미지 인식 중…</div>`;
        try {
          const processedBlob = await this.preprocessImage(file);
          const { data: { text } } = await Tesseract.recognize(processedBlob, 'kor+eng', {
            logger: m => { if (m.status === 'recognizing text') console.log(`[OCR ${i + 1}/${total}] ${Math.round(m.progress * 100)}%`); }
          });
          console.log(`[OCR ${i + 1}/${total} Result]`, text);
          if (text && text.trim().length >= 5) {
            fullText.push(text);
            parsed.push(this.parseKreamScreenshot(text));
          }
        } catch (e) {
          console.error(`[OCR ${i + 1}/${total} Error]`, e);
        }
      }
      if (parsed.length === 0) {
        imageStatus.innerHTML = '<div class="status-error">⚠ 모든 이미지에서 인식 실패. 더 명확한 스크린샷을 시도해주세요.</div>';
        return;
      }
      // 여러 이미지의 결과를 종합 + 내 사이즈 가격 우선 추출
      const merged = this.mergeOCRResults(parsed, fullText.join('\n'), SettingsStore.shoeSize);
      const filled = [];
      if (merged.brand) { document.getElementById('p-brand').value = merged.brand; filled.push('브랜드'); }
      if (merged.name) { document.getElementById('p-name').value = merged.name; filled.push('상품명'); }
      if (merged.currentPrice > 0) { document.getElementById('p-current').value = merged.currentPrice; filled.push('현재가'); }
      if (merged.retailPrice > 0) { document.getElementById('p-retail').value = merged.retailPrice; filled.push('정가'); }
      if (merged.size) { document.getElementById('p-size').value = merged.size; filled.push('사이즈'); }
      const statusMsg = filled.length ? `✓ ${total}장 인식됨: ${filled.join(', ')}` : '⚠ 일부 정보를 찾지 못했습니다.';
      imageStatus.innerHTML = `<div class="${filled.length ? 'status-success' : 'status-error'}">${statusMsg}<br><span style="font-size:0.85em;opacity:0.7">정확하지 않으면 직접 수정하세요</span></div>`;
      updateCanSave();
    };
    imageInput.addEventListener('change', (e) => recognizeImages(e.target.files));
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
  openEditModal(id) {
    const product = ProductStore.products.find(p => p.id === id);
    if (!product) return;
    const modal = document.getElementById('modal-content');
    modal.innerHTML = `<div class="modal-header"><button class="cancel" id="edit-cancel">취소</button><h2>상품 수정</h2><button class="confirm" id="edit-save">저장</button></div><div class="settings-section"><div class="section-title">상품 정보</div><div class="form-group"><input type="text" id="e-brand" placeholder="브랜드" value="${escapeAttr(product.brand)}"><input type="text" id="e-name" placeholder="상품명" value="${escapeAttr(product.name)}"><input type="text" id="e-size" placeholder="사이즈 (예: 270)" value="${escapeAttr(product.size)}" inputmode="numeric"></div><div class="form-footer">내 사이즈에 해당하는 가격을 아래에 입력하세요.</div></div><div class="settings-section"><div class="section-title">가격</div><div class="form-group"><input type="number" id="e-current" placeholder="내 사이즈 현재가" value="${product.currentPrice || ''}" inputmode="numeric"><input type="number" id="e-target" placeholder="목표가" value="${product.targetPrice || ''}" inputmode="numeric"><input type="number" id="e-retail" placeholder="정가" value="${product.retailPrice || ''}" inputmode="numeric"></div></div><div class="settings-section"><div class="section-title">Kream 링크</div><div class="form-group"><input type="url" id="e-url" placeholder="https://kream.co.kr/products/…" value="${escapeAttr(product.kreamURL || '')}"></div></div>`;
    document.getElementById('modal-backdrop').classList.remove('hidden');
    document.getElementById('edit-cancel').addEventListener('click', () => this.closeModal());
    document.getElementById('edit-save').addEventListener('click', () => {
      const newCurrent = parseInt(document.getElementById('e-current').value, 10) || 0;
      const newTarget = parseInt(document.getElementById('e-target').value, 10) || newCurrent;
      const newRetail = parseInt(document.getElementById('e-retail').value, 10) || newCurrent;
      const newName = document.getElementById('e-name').value.trim();
      const newBrand = document.getElementById('e-brand').value.trim();
      if (!newBrand || !newName || newCurrent <= 0) {
        alert('브랜드, 상품명, 현재가는 필수입니다.');
        return;
      }
      // 가격이 바뀌면 가격 히스토리에 추가
      const history = Array.isArray(product.priceHistory) ? [...product.priceHistory] : [];
      const lastPrice = history.length ? history[history.length - 1].price : null;
      if (lastPrice !== newCurrent) {
        history.push({ id: uuid(), date: new Date().toISOString(), price: newCurrent });
      }
      const updated = {
        ...product,
        brand: newBrand,
        name: newName,
        size: document.getElementById('e-size').value.trim(),
        kreamURL: document.getElementById('e-url').value.trim(),
        currentPrice: newCurrent,
        targetPrice: newTarget,
        retailPrice: newRetail,
        priceHistory: history
      };
      ProductStore.update(updated);
      this.closeModal();
    });
  },
  async preprocessImage(file) {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => {
        try {
          const canvas = document.createElement('canvas');
          const ctx = canvas.getContext('2d');
          // 상단 6% (상태바), 하단 8% (버튼바) 제거
          const cropTop = Math.floor(img.height * 0.06);
          const cropBottom = Math.floor(img.height * 0.08);
          const newHeight = img.height - cropTop - cropBottom;
          // 해상도 2배로 증가 (OCR 정확도 향상)
          const scale = Math.min(2, 2000 / img.width);
          canvas.width = Math.floor(img.width * scale);
          canvas.height = Math.floor(newHeight * scale);
          ctx.imageSmoothingEnabled = true;
          ctx.imageSmoothingQuality = 'high';
          ctx.drawImage(img, 0, cropTop, img.width, newHeight, 0, 0, canvas.width, canvas.height);
          canvas.toBlob(blob => blob ? resolve(blob) : reject(new Error('이미지 변환 실패')), 'image/png');
        } catch (e) { reject(e); }
      };
      img.onerror = () => reject(new Error('이미지 로드 실패'));
      img.src = URL.createObjectURL(file);
    });
  },
  mergeOCRResults(parsedList, combinedText, mySize) {
    // 여러 캡처 결과를 종합 (필드별로 가장 신뢰도 높은 값 채택)
    const merged = { brand: '', name: '', currentPrice: 0, retailPrice: 0, size: '' };
    // brand: 가장 많이 등장한 값
    const brandCounts = {};
    parsedList.forEach(p => { if (p.brand) brandCounts[p.brand] = (brandCounts[p.brand] || 0) + 1; });
    merged.brand = Object.keys(brandCounts).sort((a, b) => brandCounts[b] - brandCounts[a])[0] || '';
    // name: 가장 길고 의미있는 이름 (정보량이 많은 것)
    const names = parsedList.map(p => p.name).filter(Boolean);
    merged.name = names.sort((a, b) => b.length - a.length)[0] || '';
    // size: 첫 번째 발견된 값 또는 사용자 설정 사이즈
    const sizes = parsedList.map(p => p.size).filter(Boolean);
    merged.size = sizes[0] || mySize || '';
    // 가격: 모든 가격을 모아 빈도/맥락으로 결정
    const allCurrent = parsedList.map(p => p.currentPrice).filter(p => p > 0);
    const allRetail = parsedList.map(p => p.retailPrice).filter(p => p > 0);
    // 정가: 모든 OCR이 동의하는 값 (보통 정가는 변하지 않음)
    if (allRetail.length) {
      const counts = {};
      allRetail.forEach(p => counts[p] = (counts[p] || 0) + 1);
      merged.retailPrice = parseInt(Object.keys(counts).sort((a, b) => counts[b] - counts[a])[0], 10) || 0;
    }
    // 현재가: 내 사이즈 기준 가격을 우선 추출
    if (mySize) {
      const sizePrice = this.findPriceForSize(combinedText, mySize);
      if (sizePrice > 0) merged.currentPrice = sizePrice;
    }
    if (merged.currentPrice === 0 && allCurrent.length) {
      const counts = {};
      allCurrent.forEach(p => counts[p] = (counts[p] || 0) + 1);
      merged.currentPrice = parseInt(Object.keys(counts).sort((a, b) => counts[b] - counts[a])[0], 10) || 0;
    }
    return merged;
  },
  findPriceForSize(text, size) {
    // 사이즈 옆이나 가까운 위치의 가격 패턴 찾기
    if (!size) return 0;
    const sizeStr = String(size).trim();
    const escaped = sizeStr.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    // 패턴 1: "270 ... 123,000원" (사이즈와 가격이 한 줄 또는 인접)
    const patterns = [
      new RegExp(`${escaped}\\s*[^\\d]{0,10}(\\d{1,3}(?:,\\d{3})+)`, 'i'),
      new RegExp(`(\\d{1,3}(?:,\\d{3})+)\\s*[^\\d]{0,10}${escaped}`, 'i'),
      new RegExp(`${escaped}[^\\n]{0,40}?(\\d{1,3}(?:,\\d{3})+)`, 'i')
    ];
    for (const re of patterns) {
      const m = text.match(re);
      if (m) {
        const val = parseInt(m[1].replace(/,/g, ''), 10);
        if (val >= 10000 && val <= 100000000) return val;
      }
    }
    return 0;
  },
  parseKreamScreenshot(text) {
    const result = { brand: '', name: '', currentPrice: 0, retailPrice: 0, size: '' };

    // 1. 상태 표시줄 및 불필요한 텍스트 필터링
    const noiseRe = [
      /^\d{1,2}:\d{2}/,      // 시간 (03:17)
      /^\d{1,3}%$/,           // 배터리 퍼센트
      /^[·•\-_]+$/,           // 특수문자만
      /github\.io/i,          // URL
      /https?:/i,             // URL
      /^[a-z]{1,2}$/i,        // 한두 글자만
      /^\d+$/,                // 숫자만
      /취소|저장|상품|추가|스크린샷|인식/,  // UI 텍스트
      /^[^\w가-힣]+$/         // 문자 없음
    ];
    const lines = text.split('\n')
      .map(l => l.trim())
      .filter(l => l.length >= 2)
      .filter(l => !noiseRe.some(re => re.test(l)));

    // 2. 가격 추출: "발매가 XXX,XXX원" 키워드 우선
    const retailKeywords = [/발매가\s*([\d,]+)\s*원?/, /정가\s*([\d,]+)\s*원?/];
    for (const re of retailKeywords) {
      const m = text.match(re);
      if (m) {
        const val = parseInt(m[1].replace(/,/g, ''), 10);
        if (val >= 10000) { result.retailPrice = val; break; }
      }
    }

    // 3. "즉시 구매가" 또는 "구매가" 키워드
    const currentKeywords = [/즉시\s*구매가\s*([\d,]+)/, /구매가\s*([\d,]+)/];
    for (const re of currentKeywords) {
      const m = text.match(re);
      if (m) {
        const val = parseInt(m[1].replace(/,/g, ''), 10);
        if (val >= 10000) { result.currentPrice = val; break; }
      }
    }

    // 4. 모든 가격 추출 (콤마 있는 숫자 패턴)
    const priceRegex = /(\d{1,3}(?:,\d{3})+)/g;
    const allPrices = [];
    let m;
    while ((m = priceRegex.exec(text)) !== null) {
      const val = parseInt(m[1].replace(/,/g, ''), 10);
      if (val >= 10000 && val <= 100000000) allPrices.push(val);
    }
    const uniquePrices = [...new Set(allPrices)].sort((a, b) => a - b);

    // 현재가가 없으면 가장 많이 등장하는 가격 또는 첫 번째 가격
    if (result.currentPrice === 0 && uniquePrices.length > 0) {
      const counts = {};
      allPrices.forEach(p => counts[p] = (counts[p] || 0) + 1);
      const mostCommon = Object.keys(counts)
        .filter(k => parseInt(k) !== result.retailPrice)
        .sort((a, b) => counts[b] - counts[a])[0];
      result.currentPrice = mostCommon ? parseInt(mostCommon) : uniquePrices[uniquePrices.length - 1];
    }

    // 정가가 없으면 가장 작은 가격 (보통 발매가가 가장 낮음)
    if (result.retailPrice === 0 && uniquePrices.length >= 2) {
      result.retailPrice = uniquePrices[0];
    }

    // 5. 브랜드 및 상품명 추출
    // 알려진 브랜드 목록
    const knownBrands = {
      'stussy': 'Stussy', '스투시': 'Stussy',
      'nike': 'Nike', '나이키': 'Nike',
      'adidas': 'adidas', '아디다스': 'adidas',
      'new balance': 'New Balance', '뉴발란스': 'New Balance',
      'jordan': 'Jordan', '조던': 'Jordan',
      'supreme': 'Supreme', '슈프림': 'Supreme',
      'the north face': 'The North Face', '노스페이스': 'The North Face',
      'palace': 'Palace', '팔라스': 'Palace',
      'carhartt': 'Carhartt', '칼하트': 'Carhartt',
      'converse': 'Converse', '컨버스': 'Converse',
      'puma': 'Puma', '푸마': 'Puma',
      'asics': 'Asics', '아식스': 'Asics',
      'reebok': 'Reebok', '리복': 'Reebok',
      'vans': 'Vans', '반스': 'Vans'
    };
    const lowerText = text.toLowerCase();
    for (const [key, value] of Object.entries(knownBrands)) {
      if (lowerText.includes(key)) {
        result.brand = value;
        break;
      }
    }

    // 6. 상품명: 영문 상품명 패턴 (대문자로 시작하는 여러 단어)
    const englishNameMatch = text.match(/[A-Z][a-zA-Z]{2,}(?:\s+[A-Z][a-zA-Z]*){1,6}/);
    if (englishNameMatch) {
      result.name = englishNameMatch[0].trim();
    }

    // 7. 영문 상품명 없으면 한글 상품명 시도 (브랜드 뒤의 긴 문장)
    if (!result.name) {
      for (const line of lines.slice(0, 10)) {
        // 3자 이상, 50자 이하, 가격/숫자/UI 텍스트 아닌 것
        if (line.length >= 5 && line.length <= 80 &&
            !line.match(/원|₩|\$|%/) &&
            !line.match(/발매가|구매가|거래|리뷰|트렌딩/)) {
          result.name = line;
          break;
        }
      }
    }

    // 8. 브랜드 없으면 상품명에서 첫 단어 추출
    if (!result.brand && result.name) {
      const firstWord = result.name.split(/\s+/)[0];
      if (firstWord && firstWord.length >= 2) result.brand = firstWord;
    }

    // 9. 사이즈 추출
    const sizePatterns = [
      /사이즈[:\s]*(\d+\.?\d*)/,
      /Size[:\s]*(\d+\.?\d*)/i,
      /옵션[:\s]*(\d+)/
    ];
    for (const pattern of sizePatterns) {
      const match = text.match(pattern);
      if (match) { result.size = match[1]; break; }
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
