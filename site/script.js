/* ═══════════════════════════════════════════════
   time.md — Scroll reveal & micro-interactions
   ═══════════════════════════════════════════════ */

// Scroll reveal with IntersectionObserver
const revealElements = document.querySelectorAll(
  '.feature-card, .step-card, .privacy-card, .usecase-card, .interface-point, .interface-showcase, .portal-panel, .checkout-card, .portal-step'
);

const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        observer.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.15, rootMargin: '0px 0px -40px 0px' }
);

revealElements.forEach((el) => observer.observe(el));

// Nav background on scroll
const nav = document.querySelector('.nav');
let lastScroll = 0;

window.addEventListener('scroll', () => {
  const y = window.scrollY;

  if (y > 100) {
    nav.style.borderBottomColor = 'rgba(0,0,0,0.18)';
  } else {
    nav.style.borderBottomColor = '';
  }

  lastScroll = y;
}, { passive: true });

// Smooth scroll for anchor links
document.querySelectorAll('a[href^="#"]').forEach((link) => {
  link.addEventListener('click', (e) => {
    const href = link.getAttribute('href');
    if (!href || href === '#') return;

    const target = document.querySelector(href);
    if (target) {
      e.preventDefault();
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  });
});

// Stripe Checkout portal
(() => {
  const checkoutButtons = document.querySelectorAll('[data-checkout-button]');
  const statusElements = document.querySelectorAll('[data-checkout-status]');
  if (checkoutButtons.length === 0) return;

  const setStatus = (message, tone = 'neutral') => {
    statusElements.forEach((el) => {
      el.textContent = message;
      el.dataset.tone = tone;
    });
  };

  const setLoading = (isLoading) => {
    checkoutButtons.forEach((button) => {
      if (!button.dataset.originalHtml) {
        button.dataset.originalHtml = button.innerHTML;
      }

      button.disabled = isLoading;
      button.setAttribute('aria-busy', isLoading ? 'true' : 'false');
      button.innerHTML = isLoading
        ? '<span class="checkout-spinner" aria-hidden="true"></span>OPENING STRIPE…'
        : button.dataset.originalHtml;
    });
  };

  const startCheckout = async (event) => {
    event.preventDefault();
    setLoading(true);
    setStatus('Creating secure Stripe Checkout session…');

    try {
      const response = await fetch('/api/create-checkout-session', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ source: 'time.md marketing portal' }),
      });
      const payload = await response.json().catch(() => ({}));

      if (!response.ok || !payload.url) {
        throw new Error(payload.error || 'Checkout session could not be created.');
      }

      window.location.assign(payload.url);
    } catch (error) {
      setLoading(false);
      setStatus(`${error.message} Email cody@isolated.tech if this persists.`, 'error');
    }
  };

  checkoutButtons.forEach((button) => {
    button.addEventListener('click', startCheckout);
  });
})();

// Hero slideshow
(() => {
  const slides = document.querySelectorAll('.hero-slide');
  const dots = document.querySelectorAll('.hero-dot-btn');
  const titleEl = document.querySelector('[data-slide-title]');
  if (slides.length === 0) return;

  let current = 0;
  const interval = 4500;
  let timer = null;

  const show = (i) => {
    current = (i + slides.length) % slides.length;
    slides.forEach((s, idx) => s.classList.toggle('is-active', idx === current));
    dots.forEach((d, idx) => d.classList.toggle('is-active', idx === current));
    if (titleEl) titleEl.textContent = slides[current].dataset.title || '';
  };

  const next = () => show(current + 1);

  const start = () => {
    stop();
    timer = setInterval(next, interval);
  };
  const stop = () => {
    if (timer) { clearInterval(timer); timer = null; }
  };

  dots.forEach((dot) => {
    dot.addEventListener('click', () => {
      show(parseInt(dot.dataset.slide, 10));
      start();
    });
  });

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) stop(); else start();
  });

  start();
})();
