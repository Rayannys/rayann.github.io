<#
.SYNOPSIS
    Rapport de conformité des comptes à privilèges stockés dans CyberArk.

.DESCRIPTION
    Le problème : mettre un compte dans CyberArk ne suffit pas. Il faut que CyberArk
    CHANGE son mot de passe régulièrement (rotation). Si la rotation est désactivée
    ou échoue, le compte est "dans le coffre" mais pas vraiment protégé.
    Les auditeurs (ISO 27001, ACPR pour l'assurance...) demandent souvent ces chiffres.

    Ce script récupère tous les comptes et vérifie 3 règles :
      1. La gestion automatique (CPM) est activée, sinon : y a-t-il une justification ?
      2. Le mot de passe a été changé il y a moins de X jours (90 par défaut)
      3. Le dernier changement de mot de passe n'a pas échoué

    Il calcule un taux de conformité global et par coffre (KPI), puis produit
    un rapport HTML et un CSV.

    Deux façons de récupérer les comptes :
      - Depuis un fichier JSON (export de démonstration) -> par défaut
      - En direct depuis l'API : GET /PasswordVault/API/Accounts (paramètre -Reel)

.EXAMPLE
    .\Get-RapportConformitePAM.ps1 -DateReference '2026-10-19'

.EXAMPLE
    .\Get-RapportConformitePAM.ps1 -Reel -PvwaUrl 'https://pvwa.mondomaine.local' -JoursRotation 30
#>

[CmdletBinding()]
param(
    [string]$FichierExport  = "$PSScriptRoot\donnees\export_comptes.json",
    [string]$DossierSortie  = "$PSScriptRoot\..\rapports",
    [int]$JoursRotation     = 90,
    [datetime]$DateReference = (Get-Date),
    [switch]$Reel,
    [string]$PvwaUrl,
    [System.Management.Automation.PSCredential]$Identifiant
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\commun\Rapport.ps1"

# CyberArk donne les dates en "epoch" = nombre de secondes depuis le 01/01/1970.
# Cette fonction les convertit en vraie date lisible.
function ConvertFrom-Epoch([long]$Secondes) {
    return [DateTimeOffset]::FromUnixTimeSeconds($Secondes).LocalDateTime
}

# ------------------------------------------------------------------
# ÉTAPE 1 : Récupérer les comptes
# ------------------------------------------------------------------
if ($Reel) {
    if (-not $PvwaUrl) { throw 'Avec -Reel, il faut indiquer -PvwaUrl' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (-not $Identifiant) { $Identifiant = Get-Credential -Message 'Identifiant CyberArk' }

    $corps = @{ username = $Identifiant.UserName; password = $Identifiant.GetNetworkCredential().Password } | ConvertTo-Json
    $jeton = Invoke-RestMethod -Method Post -Uri "$PvwaUrl/PasswordVault/API/auth/Cyberark/Logon" -Body $corps -ContentType 'application/json'
    try {
        # L'API renvoie les comptes par "pages". Tant qu'il y a un lien "nextLink", on demande la page suivante.
        $comptes = @()
        $url = "$PvwaUrl/PasswordVault/API/Accounts?limit=1000"
        while ($url) {
            $page = Invoke-RestMethod -Method Get -Uri $url -Headers @{ Authorization = $jeton }
            $comptes += $page.value
            $url = if ($page.nextLink) { "$PvwaUrl/PasswordVault/$($page.nextLink)" } else { $null }
        }
    }
    finally {
        Invoke-RestMethod -Method Post -Uri "$PvwaUrl/PasswordVault/API/Auth/Logoff" -Headers @{ Authorization = $jeton } | Out-Null
    }
    $source = "API PVWA ($PvwaUrl)"
}
else {
    $comptes = (Get-Content $FichierExport -Raw -Encoding UTF8 | ConvertFrom-Json).value
    $source = 'Export JSON de démonstration'
}
Write-Etape "$($comptes.Count) compte(s) récupéré(s) depuis : $source" 'ok'

# ------------------------------------------------------------------
# ÉTAPE 2 : Appliquer les 3 règles à chaque compte
# ------------------------------------------------------------------
$resultats = foreach ($c in $comptes) {
    $sm = $c.secretManagement
    $dernierChangement = if ($sm.lastModifiedTime) { ConvertFrom-Epoch $sm.lastModifiedTime } else { $null }
    $age = if ($dernierChangement) { [int]($DateReference - $dernierChangement).TotalDays } else { $null }

    $problemes = @()
    if (-not $sm.automaticManagementEnabled) {
        $raison = if ($sm.manualManagementReason) { $sm.manualManagementReason } else { 'AUCUNE JUSTIFICATION' }
        $problemes += "Rotation désactivée ($raison)"
    }
    if ($null -eq $age -or $age -gt $JoursRotation) { $problemes += "Mot de passe trop ancien" }
    if ($sm.status -eq 'failure')                    { $problemes += "Dernier changement en échec" }

    # Chaque compte devient une ligne de résultat
    [PSCustomObject]@{
        Coffre               = $c.safeName
        Plateforme           = $c.platformId
        Compte               = "$($c.userName)@$($c.address)"
        'Rotation auto'      = if ($sm.automaticManagementEnabled) { 'Oui' } else { 'Non' }
        'Dernier changement' = if ($dernierChangement) { $dernierChangement.ToString('dd/MM/yyyy') } else { 'Jamais' }
        'Âge (jours)'        = $age
        Statut               = $sm.status
        Conforme             = ($problemes.Count -eq 0)
        Problèmes            = $problemes -join ' ; '
    }
}

# ------------------------------------------------------------------
# ÉTAPE 3 : Calculer les indicateurs (KPI)
# ------------------------------------------------------------------
$total       = @($resultats).Count
$conformes   = @($resultats | Where-Object Conforme).Count
$taux        = if ($total) { [math]::Round(100 * $conformes / $total) } else { 100 }
$sansRotation= @($resultats | Where-Object { $_.'Rotation auto' -eq 'Non' }).Count
$tropAnciens = @($resultats | Where-Object { $_.Problèmes -like '*trop ancien*' }).Count
$echecs      = @($resultats | Where-Object { $_.Statut -eq 'failure' }).Count

# Taux de conformité par coffre (Group-Object = regrouper par valeur, comme un tableau croisé dynamique)
$parCoffre = $resultats | Group-Object Coffre | ForEach-Object {
    $ok = @($_.Group | Where-Object Conforme).Count
    [PSCustomObject]@{
        Coffre       = $_.Name
        Comptes      = $_.Count
        Conformes    = $ok
        'Taux (%)'   = [math]::Round(100 * $ok / $_.Count)
    }
} | Sort-Object 'Taux (%)'

$niveauTaux = if ($taux -ge 90) { 'ok' } elseif ($taux -ge 70) { 'alerte' } else { 'critique' }
Write-Etape "Taux de conformité : $taux % ($conformes / $total)" $niveauTaux

# ------------------------------------------------------------------
# ÉTAPE 4 : Rapports
# ------------------------------------------------------------------
if (-not (Test-Path $DossierSortie)) { New-Item -ItemType Directory -Path $DossierSortie -Force | Out-Null }
$resultats | Export-Csv (Join-Path $DossierSortie 'conformite-pam.csv') -Delimiter ';' -NoTypeInformation -Encoding UTF8

New-RapportHtml `
    -Titre 'Conformité des comptes à privilèges - CyberArk' `
    -SousTitre "Source : $source - règle de rotation : $JoursRotation jours - au $($DateReference.ToString('dd/MM/yyyy'))" `
    -CheminSortie (Join-Path $DossierSortie 'conformite-pam.html') `
    -Indicateurs @(
        @{ Libelle = 'Taux de conformité';        Valeur = "$taux %";     Niveau = $niveauTaux }
        @{ Libelle = 'Comptes analysés';          Valeur = $total;        Niveau = 'ok' }
        @{ Libelle = 'Rotation désactivée';       Valeur = $sansRotation; Niveau = $(if ($sansRotation) {'alerte'} else {'ok'}) }
        @{ Libelle = "Mot de passe > $JoursRotation j"; Valeur = $tropAnciens; Niveau = $(if ($tropAnciens) {'critique'} else {'ok'}) }
        @{ Libelle = 'Changements en échec';      Valeur = $echecs;       Niveau = $(if ($echecs) {'critique'} else {'ok'}) }
    ) `
    -Sections @(
        @{ Titre = 'Comptes non conformes'; Lignes = @($resultats | Where-Object { -not $_.Conforme } | Sort-Object 'Âge (jours)' -Descending)
           Explication = 'À traiter en priorité : demander au propriétaire du coffre de corriger ou de justifier.'
           Colonnes = @('Coffre','Compte','Rotation auto','Dernier changement','Âge (jours)','Problèmes') }
        @{ Titre = 'Conformité par coffre'; Lignes = $parCoffre
           Explication = 'Les coffres les moins conformes en premier.'
           Colonnes = @('Coffre','Comptes','Conformes','Taux (%)') }
    )

Write-Etape "Rapport créé : $(Join-Path $DossierSortie 'conformite-pam.html')" 'ok'
