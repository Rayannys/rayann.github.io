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

// Formulaire de contact : envoi sans quitter la page, avec un message clair
const form = document.getElementById('form-contact');
if (form) {
    const statut = form.querySelector('.form__status');
    const bouton = form.querySelector('button[type="submit"]');

    const afficher = (texte, type) => {
        statut.textContent = texte;
        statut.className = 'form__status' + (type ? ' is-' + type : '');
    };

    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        if (form._honey.value) return; // robot détecté

        bouton.disabled = true;
        afficher('Envoi en cours...');

        const donnees = Object.fromEntries(new FormData(form));
        delete donnees._next;

        try {
            const reponse = await fetch(form.action.replace('formsubmit.co/', 'formsubmit.co/ajax/'), {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
                body: JSON.stringify(donnees)
            });
            const resultat = await reponse.json().catch(() => ({}));

            if (reponse.ok && String(resultat.success) === 'true') {
                form.reset();
                afficher('Message envoyé. Je vous réponds par e-mail dès que possible.', 'ok');
            } else if (/activat/i.test(resultat.message || '')) {
                afficher("Le formulaire n'est pas encore activé. Contactez-moi sur LinkedIn en attendant.", 'error');
            } else {
                afficher("Le message n'est pas parti : " + (resultat.message || 'erreur ' + reponse.status) + '. Vous pouvez aussi me joindre sur LinkedIn.', 'error');
            }
        } catch (erreur) {
            afficher("Le message n'est pas parti (connexion impossible au service d'envoi). Réessayez ou contactez-moi sur LinkedIn.", 'error');
        } finally {
            bouton.disabled = false;
        }
    });
}
