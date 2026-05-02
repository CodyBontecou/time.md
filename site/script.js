/* ═══════════════════════════════════════════════
   time.md — Scroll reveal & micro-interactions
   ═══════════════════════════════════════════════ */

// Scroll reveal with IntersectionObserver
const revealElements = document.querySelectorAll(
  '.feature-card, .step-card, .privacy-card, .usecase-card, .interface-point, .interface-showcase'
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
    const target = document.querySelector(link.getAttribute('href'));
    if (target) {
      e.preventDefault();
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  });
});

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
