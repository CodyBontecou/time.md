/* ═══════════════════════════════════════════════
   TIMEPRINT — Scroll reveal & micro-interactions
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

// Animate mock bars on showcase visibility
const showcase = document.querySelector('.interface-showcase');
const mockBars = document.querySelectorAll('.mock-bar');

const showcaseObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        mockBars.forEach((bar, i) => {
          bar.style.animationDelay = `${i * 0.06}s`;
          bar.style.animationPlayState = 'running';
        });
        showcaseObserver.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.3 }
);

if (showcase) {
  // Pause bar animations initially
  mockBars.forEach((bar) => {
    bar.style.animationPlayState = 'paused';
  });
  showcaseObserver.observe(showcase);
}
