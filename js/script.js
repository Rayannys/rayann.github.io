// ==================== HEADER SCROLL EFFECT ====================
document.addEventListener("DOMContentLoaded", function () {
    const header = document.querySelector("header");
    
    window.addEventListener("scroll", function () {
        if (window.scrollY > 50) {
            header.classList.add("scrolled");
        } else {
            header.classList.remove("scrolled");
        }
    });
});

// ==================== BURGER MENU ====================
const burger = document.querySelector('.burger');
const navLinks = document.querySelector('.nav-links');
const navItems = document.querySelectorAll('.nav-links li');

burger.addEventListener('click', () => {
    navLinks.classList.toggle('active');
    burger.classList.toggle('active');
    
    if (!navLinks.classList.contains('active')) {
        navItems.forEach(item => {
            item.style.animation = 'none';
        });
    } else {
        navItems.forEach((item, index) => {
            item.style.animation = `slideIn 0.5s forwards ${index * 0.1}s`;
        });
    }
});

// Fermer le menu burger quand on clique sur un lien
navItems.forEach(item => {
    item.addEventListener('click', () => {
        navLinks.classList.remove('active');
        burger.classList.remove('active');
    });
});

// ==================== SMOOTH SCROLLING ====================
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            const headerOffset = 80;
            const elementPosition = target.getBoundingClientRect().top;
            const offsetPosition = elementPosition + window.pageYOffset - headerOffset;

            window.scrollTo({
                top: offsetPosition,
                behavior: 'smooth'
            });
        }
    });
});

// ==================== ACTIVE MENU ITEM ON SCROLL ====================
const sections = document.querySelectorAll('section[id]');
const menuLinks = document.querySelectorAll('.nav-links a');

function highlightMenu() {
    let current = '';
    const scrollY = window.pageYOffset;

    sections.forEach(section => {
        const sectionHeight = section.offsetHeight;
        const sectionTop = section.offsetTop - 100;
        const sectionId = section.getAttribute('id');

        if (scrollY >= sectionTop && scrollY < sectionTop + sectionHeight) {
            current = sectionId;
        }
    });

    menuLinks.forEach(link => {
        link.classList.remove('clicked');
        if (link.getAttribute('href') === `#${current}`) {
            link.classList.add('clicked');
        }
    });
}

window.addEventListener('scroll', highlightMenu);

// ==================== SCROLL ANIMATIONS ====================
const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -100px 0px'
};

const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.style.opacity = '1';
            entry.target.style.transform = 'translateY(0)';
        }
    });
}, observerOptions);

// Observer les cartes de projets, expériences, formations, certifications, compétences
document.querySelectorAll('.project-card, .experience-card, .formation-card, .certification-card, .veille-card, .competence-category').forEach(card => {
    card.style.opacity = '0';
    card.style.transform = 'translateY(30px)';
    card.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
    observer.observe(card);
});

// Observer la section about
const aboutSection = document.querySelector('.main-content');
if (aboutSection) {
    aboutSection.style.opacity = '0';
    aboutSection.style.transform = 'translateY(30px)';
    aboutSection.style.transition = 'opacity 0.8s ease, transform 0.8s ease';
    observer.observe(aboutSection);
}

// Observer la section contact
const contactSection = document.querySelector('.contact');
if (contactSection) {
    contactSection.style.opacity = '0';
    contactSection.style.transform = 'translateY(30px)';
    contactSection.style.transition = 'opacity 0.8s ease, transform 0.8s ease';
    observer.observe(contactSection);
}

// ==================== PARALLAX EFFECT ON HERO ====================
window.addEventListener('scroll', () => {
    const scrolled = window.pageYOffset;
    const hero = document.querySelector('#accueil');
    if (hero) {
        hero.style.transform = `translateY(${scrolled * 0.5}px)`;
    }
});

// ==================== SHOW MORE BUTTON (if exists) ====================
const showMoreBtn = document.getElementById("show-more-btn");
if (showMoreBtn) {
    showMoreBtn.addEventListener("click", function() {
        const hiddenProjects = document.querySelectorAll(".project-card.hidden");
        
        if (hiddenProjects.length > 0) {
            hiddenProjects.forEach(project => {
                project.classList.remove("hidden");
                project.style.opacity = '0';
                project.style.transform = 'translateY(30px)';
                setTimeout(() => {
                    project.style.transition = 'opacity 0.6s ease, transform 0.6s ease';
                    project.style.opacity = '1';
                    project.style.transform = 'translateY(0)';
                }, 100);
            });
            showMoreBtn.textContent = "Voir moins";
        } else {
            const allProjects = document.querySelectorAll(".project-card");
            for (let i = 3; i < allProjects.length; i++) {
                allProjects[i].classList.add("hidden");
            }
            showMoreBtn.textContent = "Voir plus";
        }
    });
}

// ==================== TYPING EFFECT (optional enhancement) ====================
function typeWriter(element, text, speed = 50) {
    let i = 0;
    element.innerHTML = '';
    function type() {
        if (i < text.length) {
            element.innerHTML += text.charAt(i);
            i++;
            setTimeout(type, speed);
        }
    }
    type();
}

// ==================== CURSOR EFFECT (optional) ====================
document.addEventListener('mousemove', (e) => {
    const cursor = document.querySelector('.custom-cursor');
    if (cursor) {
        cursor.style.left = e.clientX + 'px';
        cursor.style.top = e.clientY + 'px';
    }
});

// ==================== ADD ANIMATION KEYFRAMES ====================
const style = document.createElement('style');
style.textContent = `
    @keyframes slideIn {
        from {
            opacity: 0;
            transform: translateX(20px);
        }
        to {
            opacity: 1;
            transform: translateX(0);
        }
    }
`;
document.head.appendChild(style);
