<#
.SYNOPSIS
    Intègre (onboarde) des comptes à privilèges dans CyberArk en masse, depuis un fichier CSV.

.DESCRIPTION
    Le problème : une équipe demande de mettre 50 comptes admin dans CyberArk.
    À la main dans l'interface PVWA = 50 fois les mêmes clics, avec des erreurs de saisie.
    Ce script lit un CSV, VÉRIFIE chaque ligne, puis crée les comptes via l'API REST CyberArk.

    Sécurité avant tout :
      - Par défaut le script tourne en mode SIMULATION : il montre ce qu'il ferait, sans rien toucher.
        Il faut ajouter -Reel pour vraiment créer les comptes.
      - Aucun mot de passe dans le CSV. Le mot de passe est ensuite pris en charge par CyberArk
        (le CPM le change / le réconcilie selon la plateforme).
      - Mon identifiant CyberArk est demandé au lancement (Get-Credential), jamais écrit dans le code.
      - Je me déconnecte de l'API à la fin, même en cas d'erreur (bloc "finally").

    Les appels API utilisés (API REST PVWA, v10 et plus) :
      POST /PasswordVault/API/auth/Cyberark/Logon   -> se connecter, récupère un jeton (token)
      GET  /PasswordVault/API/Accounts?search=...   -> vérifier si le compte existe déjà
      POST /PasswordVault/API/Accounts              -> créer le compte
      POST /PasswordVault/API/Auth/Logoff           -> se déconnecter

.EXAMPLE
    .\Import-ComptesCyberArk.ps1
    Mode simulation avec les données de démonstration.

.EXAMPLE
    .\Import-ComptesCyberArk.ps1 -Reel
    Crée vraiment les comptes (demande l'identifiant CyberArk).
#>

[CmdletBinding()]
param(
    [string]$FichierComptes = '',
    [string]$FichierConfig  = '',
    [string]$DossierSortie  = '',
    [switch]$Reel,
    [System.Management.Automation.PSCredential]$Identifiant
)

$ErrorActionPreference = 'Stop'

# Dossier où se trouve ce script (calculé ici, car sous Windows PowerShell 5.1
# la variable $PSScriptRoot peut être vide dans le bloc param ci-dessus)
$ici = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $FichierComptes) { $FichierComptes = Join-Path $ici 'donnees\comptes_a_integrer.csv' }
if (-not $FichierConfig) { $FichierConfig = Join-Path $ici 'donnees\configuration.json' }
if (-not $DossierSortie) { $DossierSortie = Join-Path $ici '..\rapports' }
. (Join-Path $ici '..\commun\Rapport.ps1')

# ------------------------------------------------------------------
# Petites fonctions pour parler à l'API CyberArk
# ------------------------------------------------------------------
function Connect-PVWA {
    param([string]$Url, [System.Management.Automation.PSCredential]$Cred)
    $corps = @{
        username = $Cred.UserName
        password = $Cred.GetNetworkCredential().Password
    } | ConvertTo-Json
    # La réponse est directement le jeton de session
    return Invoke-RestMethod -Method Post -Uri "$Url/PasswordVault/API/auth/Cyberark/Logon" `
                             -Body $corps -ContentType 'application/json'
}

function Disconnect-PVWA {
    param([string]$Url, [string]$Jeton)
    Invoke-RestMethod -Method Post -Uri "$Url/PasswordVault/API/Auth/Logoff" `
                      -Headers @{ Authorization = $Jeton } | Out-Null
}

function Test-CompteExiste {
    param([string]$Url, [string]$Jeton, [string]$Coffre, [string]$Adresse, [string]$Utilisateur)
    $recherche = [uri]::EscapeDataString("$Utilisateur $Adresse")
    $filtre    = [uri]::EscapeDataString("safeName eq $Coffre")
    $reponse = Invoke-RestMethod -Method Get -Headers @{ Authorization = $Jeton } `
        -Uri "$Url/PasswordVault/API/Accounts?search=$recherche&filter=$filtre"
    # La recherche est "large" : je revérifie l'égalité exacte moi-même
    $exact = @($reponse.value | Where-Object { $_.userName -eq $Utilisateur -and $_.address -eq $Adresse })
    return ($exact.Count -gt 0)
}

function New-CorpsCompte {
    # Construit le "colis" JSON que l'API attend pour créer un compte
    param($Ligne, [bool]$GestionAuto)
    return @{
        safeName   = $Ligne.Coffre
        platformId = $Ligne.Plateforme
        address    = $Ligne.Adresse
        userName   = $Ligne.Utilisateur
        secretType = 'password'
        secretManagement = @{ automaticManagementEnabled = $GestionAuto }
    }
}

# ------------------------------------------------------------------
# ÉTAPE 1 : Lire la configuration et le CSV
# ------------------------------------------------------------------
$mode = if ($Reel) { 'RÉEL' } else { 'SIMULATION' }
Write-Etape "Mode : $mode" $(if ($Reel) { 'alerte' } else { 'info' })

$config = Get-Content $FichierConfig -Raw -Encoding UTF8 | ConvertFrom-Json
$lignes = Import-Csv $FichierComptes -Delimiter ';' -Encoding UTF8
Write-Etape "$($lignes.Count) ligne(s) à traiter"

# ------------------------------------------------------------------
# ÉTAPE 2 : Valider chaque ligne AVANT de toucher à CyberArk
# Règle d'or : on ne pousse jamais des données non vérifiées dans un coffre.
# ------------------------------------------------------------------
$dejaVus = @{}
$numero  = 1
$aTraiter = @()
$journal  = @()

foreach ($l in $lignes) {
    $numero++   # ligne 1 = l'en-tête du CSV, donc la 1re donnée est la ligne 2
    $erreurs = @()

    foreach ($champ in @('Coffre','Plateforme','Adresse','Utilisateur')) {
        if ([string]::IsNullOrWhiteSpace($l.$champ)) { $erreurs += "$champ vide" }
    }
    if ($l.Coffre -and $l.Coffre -cnotmatch $config.RegleNomCoffre) {
        $erreurs += "nom de coffre hors convention"
    }
    if ($l.Plateforme -and $config.PlateformesAutorisees -notcontains $l.Plateforme) {
        $erreurs += "plateforme non autorisée"
    }
    $cle = "$($l.Coffre)|$($l.Adresse)|$($l.Utilisateur)".ToLower()
    if ($dejaVus.ContainsKey($cle)) { $erreurs += "doublon de la ligne $($dejaVus[$cle])" }
    else { $dejaVus[$cle] = $numero }

    $entree = [PSCustomObject]@{
        Ligne       = $numero
        Coffre      = $l.Coffre
        Plateforme  = $l.Plateforme
        Adresse     = $l.Adresse
        Utilisateur = $l.Utilisateur
        Resultat    = ''
        Detail      = ''
    }

    if ($erreurs.Count -gt 0) {
        $entree.Resultat = 'Rejeté'
        $entree.Detail   = $erreurs -join ' ; '
        Write-Etape "Ligne $numero rejetée : $($entree.Detail)" 'alerte'
        $journal += $entree
    } else {
        $aTraiter += @{ Source = $l; Entree = $entree }
    }
}
Write-Etape "$($aTraiter.Count) ligne(s) valide(s), $($journal.Count) rejetée(s)" 'ok'

# ------------------------------------------------------------------
# ÉTAPE 3 : Créer les comptes (ou simuler)
# ------------------------------------------------------------------
if (-not $Reel) {
    foreach ($item in $aTraiter) {
        $corps = New-CorpsCompte -Ligne $item.Source -GestionAuto $config.GestionAutomatique
        Write-Etape "[Simulation] POST /API/Accounts -> $($corps | ConvertTo-Json -Compress)"
        $item.Entree.Resultat = 'Simulé'
        $item.Entree.Detail   = 'Serait créé (relancer avec -Reel)'
        $journal += $item.Entree
    }
}
else {
    # PowerShell 5.1 : forcer TLS 1.2, sinon la connexion HTTPS au PVWA peut échouer
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (-not $Identifiant) { $Identifiant = Get-Credential -Message 'Identifiant CyberArk' }

    $jeton = Connect-PVWA -Url $config.PvwaUrl -Cred $Identifiant
    Write-Etape 'Connecté au PVWA' 'ok'
    try {
        foreach ($item in $aTraiter) {
            $s = $item.Source
            try {
                if (Test-CompteExiste -Url $config.PvwaUrl -Jeton $jeton -Coffre $s.Coffre -Adresse $s.Adresse -Utilisateur $s.Utilisateur) {
                    $item.Entree.Resultat = 'Ignoré'
                    $item.Entree.Detail   = 'Existe déjà dans le coffre'
                } else {
                    $corps = New-CorpsCompte -Ligne $s -GestionAuto $config.GestionAutomatique | ConvertTo-Json -Depth 5
                    $cree = Invoke-RestMethod -Method Post -Uri "$($config.PvwaUrl)/PasswordVault/API/Accounts" `
                        -Headers @{ Authorization = $jeton } -Body $corps -ContentType 'application/json'
                    $item.Entree.Resultat = 'Créé'
                    $item.Entree.Detail   = "ID $($cree.id)"
                }
                Write-Etape "Ligne $($item.Entree.Ligne) : $($item.Entree.Resultat)" 'ok'
            }
            catch {
                # Une erreur sur UN compte ne doit pas arrêter tous les autres
                # CyberArk renvoie la raison de l'erreur dans le corps de la réponse (ErrorCode / ErrorMessage)
                $erreur  = $_      # je garde l'erreur de côté ($_ change de sens dans un autre catch)
                $message = $erreur.Exception.Message
                if ($erreur.ErrorDetails -and $erreur.ErrorDetails.Message) {
                    try {
                        $detailApi = $erreur.ErrorDetails.Message | ConvertFrom-Json
                        $message = "$($detailApi.ErrorCode) - $($detailApi.ErrorMessage)"
                    } catch { $message = $erreur.ErrorDetails.Message }
                }
                $item.Entree.Resultat = 'Erreur'
                $item.Entree.Detail   = $message
                Write-Etape "Ligne $($item.Entree.Ligne) : $message" 'erreur'
            }
            $journal += $item.Entree
        }
    }
    finally {
        # Toujours se déconnecter, même si tout a planté au milieu
        Disconnect-PVWA -Url $config.PvwaUrl -Jeton $jeton
        Write-Etape 'Déconnecté du PVWA'
    }
}

# ------------------------------------------------------------------
# ÉTAPE 4 : Journal (preuve de ce qui a été fait = traçabilité / audit)
# ------------------------------------------------------------------
$journal = $journal | Sort-Object Ligne
if (-not (Test-Path $DossierSortie)) { New-Item -ItemType Directory -Path $DossierSortie -Force | Out-Null }
$journal | Export-Csv (Join-Path $DossierSortie 'onboarding-cyberark_journal.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8

$nbRejet = @($journal | Where-Object Resultat -eq 'Rejeté').Count
$nbOk    = @($journal | Where-Object { $_.Resultat -in 'Créé','Simulé' }).Count
$nbErr   = @($journal | Where-Object Resultat -eq 'Erreur').Count

New-RapportHtml `
    -Titre 'Onboarding de comptes à privilèges - CyberArk' `
    -SousTitre "Mode $mode - $($lignes.Count) demande(s)" `
    -CheminSortie (Join-Path $DossierSortie 'onboarding-cyberark.html') `
    -Indicateurs @(
        @{ Libelle = 'Demandes reçues';                 Valeur = $lignes.Count; Niveau = 'ok' }
        @{ Libelle = $(if ($Reel) {'Comptes créés'} else {'Prêts à créer'}); Valeur = $nbOk; Niveau = 'ok' }
        @{ Libelle = 'Rejetées par les contrôles';      Valeur = $nbRejet; Niveau = $(if ($nbRejet) {'alerte'} else {'ok'}) }
        @{ Libelle = 'Erreurs API';                     Valeur = $nbErr;   Niveau = $(if ($nbErr) {'critique'} else {'ok'}) }
    ) `
    -Sections @(
        @{ Titre = 'Lignes rejetées'; Lignes = @($journal | Where-Object Resultat -eq 'Rejeté')
           Explication = 'Ces demandes ne respectent pas les règles (convention de nommage des coffres, plateformes autorisées, champs obligatoires, doublons). Elles ne sont jamais envoyées à CyberArk.'
           Colonnes = @('Ligne','Coffre','Plateforme','Adresse','Utilisateur','Detail') }
        @{ Titre = 'Journal complet'; Lignes = $journal
           Explication = 'Trace de chaque demande et de ce qui a été fait.'
           Colonnes = @('Ligne','Coffre','Plateforme','Adresse','Utilisateur','Resultat','Detail') }
    )

Write-Etape "Rapport créé : $(Join-Path $DossierSortie 'onboarding-cyberark.html')" 'ok'
