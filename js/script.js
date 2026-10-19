// Menu mobile : ouvrir / fermer
const bouton = document.querySelector('.topbar__toggle');
const menu = document.getElementById('menu');

bouton.addEventListener('click', () => {
    const ouvert = bouton.getAttribute('aria-expanded') === 'true';
    bouton.setAttribute('aria-expanded', String(!ouvert));
    bouton.setAttribute('aria-label', ouvert ? 'Ouvrir le menu' : 'Fermer le menu');
    menu.classList.toggle('is-open', !ouvert);
});

// Fermer le menu quand on clique sur un lien
menu.querySelectorAll('a').forEach(lien => {
    lien.addEventListener('click', () => {
        bouton.setAttribute('aria-expanded', 'false');
        bouton.setAttribute('aria-label', 'Ouvrir le menu');
        menu.classList.remove('is-open');
    });
});

// Surligner dans le menu la section affichée à l'écran
const liens = [...menu.querySelectorAll('a[href^="#"]')];
const sections = liens
    .map(l => document.querySelector(l.getAttribute('href')))
    .filter(Boolean);

const observer = new IntersectionObserver(entries => {
    entries.forEach(e => {
        if (e.isIntersecting) {
            liens.forEach(l => l.classList.toggle('is-active', l.getAttribute('href') === '#' + e.target.id));
        }
    });
}, { rootMargin: '-45% 0px -50% 0px' });
sections.forEach(s => observer.observe(s));

// Année dans le pied de page
document.getElementById('annee').textContent = new Date().getFullYear();
