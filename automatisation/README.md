# Automatisation IAM / PAM - PowerShell & CyberArk

Trois scripts que j'ai écrits pour automatiser des tâches répétitives de gestion des identités (IAM) et des comptes à privilèges (PAM).
Ils tournent **automatiquement** dans GitHub Actions à chaque modification, et les rapports sont publiés en ligne.

> Toutes les données sont **fictives** (aucune donnée d'entreprise). Les scripts sont faits pour être réutilisés sur de vraies données.

| # | Projet | Ce que ça automatise | Rapport en ligne |
|---|--------|----------------------|------------------|
| 1 | [Revue des accès](01-revue-des-acces) | Croise l'export RH et Active Directory : partants encore actifs, comptes orphelins, comptes dormants, droits d'admin hors DSI | [revue-acces.html](https://rayannys.github.io/rayann.github.io/automatisation/rapports/revue-acces.html) |
| 2 | [Onboarding CyberArk](02-cyberark-onboarding) | Intègre des comptes à privilèges en masse via l'API REST CyberArk, avec contrôles avant envoi et mode simulation | [onboarding-cyberark.html](https://rayannys.github.io/rayann.github.io/automatisation/rapports/onboarding-cyberark.html) |
| 3 | [Conformité CyberArk](03-cyberark-conformite) | Vérifie la rotation des mots de passe (CPM) et calcule un taux de conformité global et par coffre | [conformite-pam.html](https://rayannys.github.io/rayann.github.io/automatisation/rapports/conformite-pam.html) |

## Lancer les scripts

Il faut seulement PowerShell (Windows PowerShell 5.1 ou PowerShell 7).

```powershell
# Autoriser les scripts pour cette fenêtre uniquement
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\automatisation\01-revue-des-acces\Invoke-RevueAcces.ps1
.\automatisation\02-cyberark-onboarding\Import-ComptesCyberArk.ps1        # simulation : rien n'est créé
.\automatisation\03-cyberark-conformite\Get-RapportConformitePAM.ps1
```

Les rapports (HTML + CSV pour Excel) arrivent dans `automatisation/rapports/`.
Chaque script a une aide intégrée : `Get-Help .\Invoke-RevueAcces.ps1 -Full`

## Choix de sécurité

- **Simulation par défaut** pour tout ce qui modifie CyberArk : il faut ajouter `-Reel` pour agir pour de vrai.
- **Aucun mot de passe dans le code ni dans les CSV** : l'identifiant est demandé au lancement (`Get-Credential`).
- **Déconnexion de l'API garantie** (`try / finally`), même si le script plante.
- **Contrôle des données avant envoi** : convention de nommage des coffres, plateformes autorisées, doublons, champs vides.
- **Traçabilité** : chaque exécution produit un journal CSV (utile pour un audit).

## Organisation

```
automatisation/
├── commun/Rapport.ps1          fonctions partagées (rapport HTML, messages)
├── 01-revue-des-acces/         script + données RH/AD fictives
├── 02-cyberark-onboarding/     script + CSV de demandes + configuration
├── 03-cyberark-conformite/     script + export JSON fictif au format de l'API
└── rapports/                   rapports générés automatiquement
.github/workflows/automatisation.yml   pipeline GitHub Actions
```

Technos : PowerShell, API REST CyberArk PVWA, JSON, CSV, GitHub Actions, PSScriptAnalyzer.
