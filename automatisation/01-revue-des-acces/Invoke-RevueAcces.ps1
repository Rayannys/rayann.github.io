<#
.SYNOPSIS
    Revue des accès automatique : compare la liste RH avec les comptes Active Directory.

.DESCRIPTION
    Le problème : en entreprise, quand quelqu'un part, son compte reste parfois actif.
    C'est une faille (un ancien salarié ou un pirate peut s'en servir).
    Faire ce contrôle à la main dans Excel prend des heures. Ce script le fait en quelques secondes.

    Il détecte 4 types d'anomalies :
      1. Partants encore actifs   : la RH dit "parti", mais le compte AD est toujours activé
      2. Comptes orphelins        : un compte AD qui ne correspond à personne dans la RH
      3. Comptes dormants         : compte actif mais pas utilisé depuis X jours
      4. Privilèges suspects      : quelqu'un hors DSI dans un groupe d'administration

    Résultat : un rapport HTML lisible + un CSV par anomalie (pour Excel).

.PARAMETER FichierRH
    Export RH (CSV séparé par des points-virgules).

.PARAMETER FichierAD
    Export des comptes AD. En vrai, on l'obtiendrait avec :
    Get-ADUser -Filter * -Properties EmployeeID, LastLogonDate, MemberOf

.PARAMETER JoursDormant
    Au-delà de ce nombre de jours sans connexion, le compte est "dormant". 90 par défaut.

.PARAMETER DateReference
    Date du contrôle. Par défaut : aujourd'hui. Utile pour rejouer un contrôle passé.

.EXAMPLE
    .\Invoke-RevueAcces.ps1
    Lance la revue avec les données de démonstration.

.EXAMPLE
    .\Invoke-RevueAcces.ps1 -JoursDormant 60 -DateReference '2026-10-19'
#>

[CmdletBinding()]
param(
    [string]$FichierRH     = '',
    [string]$FichierAD     = '',
    [string]$DossierSortie = '',
    [int]$JoursDormant     = 90,
    [datetime]$DateReference = (Get-Date),
    [string[]]$ServicesAutorisesAdmin = @('DSI'),
    [string]$MotifGroupeAdmin = 'Admin',       # tout groupe contenant "Admin" est considéré sensible
    [string[]]$PrefixesComptesService = @('svc_'),
    [switch]$EchecSiAnomalie   # si activé : le script renvoie le code 1 quand il trouve des anomalies
)

# Arrêter le script à la première erreur (plus sûr que de continuer avec des données fausses)
$ErrorActionPreference = 'Stop'

# Dossier où se trouve ce script (calculé ici, car sous Windows PowerShell 5.1
# la variable $PSScriptRoot peut être vide dans le bloc param ci-dessus)
$ici = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $FichierRH) { $FichierRH = Join-Path $ici 'donnees\rh.csv' }
if (-not $FichierAD) { $FichierAD = Join-Path $ici 'donnees\comptes_ad.csv' }
if (-not $DossierSortie) { $DossierSortie = Join-Path $ici '..\rapports' }

# Charger mes fonctions communes (rapport HTML, messages colorés)
. (Join-Path $ici '..\commun\Rapport.ps1')

# ------------------------------------------------------------------
# ÉTAPE 1 : Lire les fichiers
# ------------------------------------------------------------------
Write-Etape "Lecture des fichiers..."
foreach ($f in @($FichierRH, $FichierAD)) {
    if (-not (Test-Path $f)) { throw "Fichier introuvable : $f" }
}
$rh = Import-Csv -Path $FichierRH -Delimiter ';' -Encoding UTF8
$ad = Import-Csv -Path $FichierAD -Delimiter ';' -Encoding UTF8
Write-Etape "$($rh.Count) personnes côté RH, $($ad.Count) comptes côté AD" 'ok'

# ------------------------------------------------------------------
# ÉTAPE 2 : Ranger la RH dans un "dictionnaire" (hashtable)
# Une hashtable = un carnet d'adresses : je donne le matricule, j'obtiens la personne
# instantanément, au lieu de parcourir toute la liste à chaque fois.
# ------------------------------------------------------------------
$rhParMatricule = @{}
foreach ($personne in $rh) { $rhParMatricule[$personne.Matricule] = $personne }

# Listes vides qui vont recevoir les anomalies
$partantsActifs = @()
$orphelins      = @()
$dormants       = @()
$privileges     = @()

# ------------------------------------------------------------------
# ÉTAPE 3 : Passer chaque compte AD au contrôle
# ------------------------------------------------------------------
Write-Etape "Contrôle des comptes..."
foreach ($compte in $ad) {

    $estActif  = ($compte.Actif -eq 'Oui')
    $groupes   = $compte.Groupes -split '\|'          # "GG_A|GG_B" devient @('GG_A','GG_B')
    $personne  = $rhParMatricule[$compte.Matricule]   # $null si le matricule est inconnu

    # Les comptes de service (svc_...) n'ont pas de matricule : c'est normal, on les ignore ici
    $estCompteService = $false
    foreach ($p in $PrefixesComptesService) { if ($compte.Login.StartsWith($p)) { $estCompteService = $true } }
    if ($estCompteService) { continue }

    # Nombre de jours depuis la dernière connexion
    $jours = $null
    if ($compte.DerniereConnexion) {
        $jours = [int]($DateReference - [datetime]$compte.DerniereConnexion).TotalDays
    }

    # --- Contrôle 1 : partant encore actif ---
    if ($personne -and $personne.Statut -eq 'Parti' -and $estActif) {
        $partantsActifs += [PSCustomObject]@{
            Login         = $compte.Login
            Nom           = "$($personne.Prenom) $($personne.Nom)"
            Service       = $personne.Service
            'Date sortie' = $personne.DateSortie
            'Jours depuis sortie' = [int]($DateReference - [datetime]$personne.DateSortie).TotalDays
            Action        = 'Désactiver le compte'
        }
    }

    # --- Contrôle 2 : compte orphelin (aucune personne RH derrière) ---
    if (-not $personne) {
        $orphelins += [PSCustomObject]@{
            Login       = $compte.Login
            Matricule   = if ($compte.Matricule) { $compte.Matricule } else { '(vide)' }
            Actif       = $compte.Actif
            Groupes     = $groupes -join ', '
            Action      = 'Identifier le propriétaire ou supprimer'
        }
    }

    # --- Contrôle 3 : compte dormant ---
    if ($estActif -and $null -ne $jours -and $jours -gt $JoursDormant) {
        $dormants += [PSCustomObject]@{
            Login                  = $compte.Login
            'Dernière connexion'   = $compte.DerniereConnexion
            'Jours sans connexion' = $jours
            Action                 = 'Vérifier avec le manager, puis désactiver'
        }
    }

    # --- Contrôle 4 : droits d'admin hors DSI ---
    $groupesAdmin = $groupes | Where-Object { $_ -match $MotifGroupeAdmin }
    $service = if ($personne) { $personne.Service } else { 'Inconnu' }
    if ($groupesAdmin -and ($ServicesAutorisesAdmin -notcontains $service)) {
        $privileges += [PSCustomObject]@{
            Login            = $compte.Login
            Service          = $service
            'Groupe sensible'= $groupesAdmin -join ', '
            Action           = 'Retirer du groupe ou justifier'
        }
    }
}

# ------------------------------------------------------------------
# ÉTAPE 4 : Afficher le bilan et produire les rapports
# ------------------------------------------------------------------
$total = $partantsActifs.Count + $orphelins.Count + $dormants.Count + $privileges.Count
$niveauGlobal = if ($total -eq 0) { 'ok' } else { 'alerte' }
Write-Etape "Bilan : $total anomalie(s)" $niveauGlobal

if (-not (Test-Path $DossierSortie)) { New-Item -ItemType Directory -Path $DossierSortie -Force | Out-Null }

# Un CSV par contrôle (ouvrable dans Excel : séparateur ";")
$exports = @{
    'revue-acces_partants-actifs.csv' = $partantsActifs
    'revue-acces_orphelins.csv'       = $orphelins
    'revue-acces_dormants.csv'        = $dormants
    'revue-acces_privileges.csv'      = $privileges
}
foreach ($nom in $exports.Keys) {
    $exports[$nom] | Export-Csv -Path (Join-Path $DossierSortie $nom) -Delimiter ';' -NoTypeInformation -Encoding UTF8
}

function Get-Niveau([int]$n, [string]$siProbleme) { if ($n -eq 0) { 'ok' } else { $siProbleme } }

New-RapportHtml `
    -Titre 'Revue des accès - RH vs Active Directory' `
    -SousTitre "Contrôle au $($DateReference.ToString('dd/MM/yyyy')) - seuil dormant : $JoursDormant jours" `
    -CheminSortie (Join-Path $DossierSortie 'revue-acces.html') `
    -Indicateurs @(
        @{ Libelle = 'Comptes analysés';       Valeur = $ad.Count;             Niveau = 'ok' }
        @{ Libelle = 'Partants encore actifs'; Valeur = $partantsActifs.Count; Niveau = (Get-Niveau $partantsActifs.Count 'critique') }
        @{ Libelle = 'Comptes orphelins';      Valeur = $orphelins.Count;      Niveau = (Get-Niveau $orphelins.Count 'critique') }
        @{ Libelle = 'Comptes dormants';       Valeur = $dormants.Count;       Niveau = (Get-Niveau $dormants.Count 'alerte') }
        @{ Libelle = 'Privilèges hors DSI';    Valeur = $privileges.Count;     Niveau = (Get-Niveau $privileges.Count 'critique') }
    ) `
    -Sections @(
        @{ Titre = 'Partants encore actifs'; Lignes = $partantsActifs
           Explication = 'La RH indique un départ, mais le compte fonctionne toujours. Risque : accès d''un ancien salarié.'
           Colonnes = @('Login','Nom','Service','Date sortie','Jours depuis sortie','Action') }
        @{ Titre = 'Comptes orphelins'; Lignes = $orphelins
           Explication = 'Comptes sans personne identifiée dans la RH (matricule vide ou inconnu).'
           Colonnes = @('Login','Matricule','Actif','Groupes','Action') }
        @{ Titre = 'Comptes dormants'; Lignes = $dormants
           Explication = "Comptes actifs sans connexion depuis plus de $JoursDormant jours."
           Colonnes = @('Login','Dernière connexion','Jours sans connexion','Action') }
        @{ Titre = 'Privilèges hors DSI'; Lignes = $privileges
           Explication = 'Personnes hors DSI présentes dans un groupe d''administration.'
           Colonnes = @('Login','Service','Groupe sensible','Action') }
    )

Write-Etape "Rapport créé : $(Join-Path $DossierSortie 'revue-acces.html')" 'ok'

# Code de sortie : utile quand un autre outil (tâche planifiée, pipeline) lance le script
if ($EchecSiAnomalie -and $total -gt 0) { exit 1 }
