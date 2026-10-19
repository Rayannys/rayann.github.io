<#
    Rapport.ps1 - Fonctions partagées par tous mes scripts.

    En simple : au lieu de recopier le même code HTML dans chaque script,
    je le mets ici une seule fois. Les autres scripts le "chargent" avec :
        . "$PSScriptRoot\..\commun\Rapport.ps1"
    (le point au début = "dot-sourcing" = importer les fonctions de ce fichier)
#>

function ConvertTo-HtmlSur {
    # Protège le texte avant de le mettre dans du HTML (évite qu'un nom
    # comme "<script>" casse ou pirate le rapport).
    param([AllowNull()][object]$Texte)
    if ($null -eq $Texte) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Texte)
}

function New-TableauHtml {
    # Transforme une liste d'objets PowerShell en tableau HTML.
    param(
        [object[]]$Lignes,
        [string[]]$Colonnes
    )
    if (-not $Lignes -or $Lignes.Count -eq 0) {
        return '<p class="vide">Aucune anomalie. &#10003;</p>'
    }
    $html = '<table><thead><tr>'
    foreach ($c in $Colonnes) { $html += '<th>' + (ConvertTo-HtmlSur $c) + '</th>' }
    $html += '</tr></thead><tbody>'
    foreach ($l in $Lignes) {
        $html += '<tr>'
        foreach ($c in $Colonnes) { $html += '<td>' + (ConvertTo-HtmlSur $l.$c) + '</td>' }
        $html += '</tr>'
    }
    $html += '</tbody></table>'
    return $html
}

function New-RapportHtml {
    <#
        Construit une page HTML complète.
        -Indicateurs : liste de @{ Libelle = '...'; Valeur = 12; Niveau = 'ok'|'alerte'|'critique' }
        -Sections    : liste de @{ Titre = '...'; Explication = '...'; Lignes = $objets; Colonnes = @('A','B') }
    #>
    param(
        [Parameter(Mandatory)][string]$Titre,
        [Parameter(Mandatory)][string]$CheminSortie,
        [string]$SousTitre = '',
        [object[]]$Indicateurs = @(),
        [object[]]$Sections = @()
    )

    $date = (Get-Date).ToString('dd/MM/yyyy HH:mm')

    $htmlIndicateurs = ''
    foreach ($i in $Indicateurs) {
        $niveau = if ($i.Niveau) { $i.Niveau } else { 'ok' }
        $htmlIndicateurs += "<div class='kpi $niveau'><div class='valeur'>$(ConvertTo-HtmlSur $i.Valeur)</div><div class='libelle'>$(ConvertTo-HtmlSur $i.Libelle)</div></div>"
    }

    $htmlSections = ''
    foreach ($s in $Sections) {
        $nb = @($s.Lignes).Count
        $htmlSections += "<section><h2>$(ConvertTo-HtmlSur $s.Titre) <span class='nb'>$nb</span></h2>"
        if ($s.Explication) { $htmlSections += "<p class='explication'>$(ConvertTo-HtmlSur $s.Explication)</p>" }
        $htmlSections += "<div class='scroll'>" + (New-TableauHtml -Lignes @($s.Lignes) -Colonnes $s.Colonnes) + '</div></section>'
    }

    $page = @"
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$(ConvertTo-HtmlSur $Titre)</title>
<style>
  :root { --fond:#0f172a; --carte:#1e293b; --texte:#e2e8f0; --gris:#94a3b8; --bleu:#3b82f6; --vert:#22c55e; --orange:#f59e0b; --rouge:#ef4444; }
  * { box-sizing: border-box; }
  body { margin:0; font-family: 'Segoe UI', Arial, sans-serif; background:var(--fond); color:var(--texte); padding:24px 16px; }
  .page { max-width:1100px; margin:0 auto; }
  h1 { margin:0 0 4px; font-size:1.6rem; }
  .meta { color:var(--gris); margin:0 0 24px; font-size:.9rem; }
  .bandeau { background:rgba(245,158,11,.1); border:1px solid rgba(245,158,11,.4); color:#fcd34d; padding:10px 14px; border-radius:8px; margin-bottom:24px; font-size:.9rem; }
  .kpis { display:grid; grid-template-columns:repeat(auto-fit,minmax(160px,1fr)); gap:12px; margin-bottom:28px; }
  .kpi { background:var(--carte); border-radius:10px; padding:16px; border-left:4px solid var(--vert); }
  .kpi.alerte { border-left-color:var(--orange); } .kpi.critique { border-left-color:var(--rouge); }
  .kpi .valeur { font-size:1.8rem; font-weight:700; } .kpi .libelle { color:var(--gris); font-size:.85rem; }
  section { background:var(--carte); border-radius:10px; padding:18px; margin-bottom:18px; }
  h2 { font-size:1.1rem; margin:0 0 6px; } .nb { background:var(--bleu); border-radius:20px; padding:1px 10px; font-size:.8rem; margin-left:6px; }
  .explication { color:var(--gris); font-size:.9rem; margin:0 0 12px; }
  .scroll { overflow-x:auto; }
  table { border-collapse:collapse; width:100%; font-size:.88rem; }
  th, td { text-align:left; padding:8px 10px; border-bottom:1px solid rgba(255,255,255,.08); white-space:nowrap; }
  td:last-child { white-space:normal; min-width:260px; }
  th { color:var(--gris); font-weight:600; }
  .vide { color:var(--vert); margin:0; }
  footer { color:var(--gris); font-size:.8rem; margin-top:24px; }
  a { color:var(--bleu); }
</style>
</head>
<body><div class="page">
<h1>$(ConvertTo-HtmlSur $Titre)</h1>
<p class="meta">$(ConvertTo-HtmlSur $SousTitre) &middot; Généré automatiquement le $date</p>
<div class="bandeau">Données 100 % fictives &mdash; rapport de démonstration généré par un script PowerShell.</div>
<div class="kpis">$htmlIndicateurs</div>
$htmlSections
<footer>Rayann Ilkay &middot; <a href="https://github.com/Rayannys/rayann.github.io/tree/main/automatisation">Voir le code sur GitHub</a></footer>
</div></body>
</html>
"@

    # Crée le dossier de sortie s'il n'existe pas, puis écrit le fichier en UTF-8
    $dossier = Split-Path -Parent $CheminSortie
    if ($dossier -and -not (Test-Path $dossier)) { New-Item -ItemType Directory -Path $dossier -Force | Out-Null }
    [System.IO.File]::WriteAllText($CheminSortie, $page, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-Etape {
    # Affiche un message coloré dans la console pour suivre ce que fait le script.
    param([string]$Message, [ValidateSet('info','ok','alerte','critique','erreur')][string]$Type = 'info')
    $couleur = @{ info = 'Cyan'; ok = 'Green'; alerte = 'Yellow'; critique = 'Red'; erreur = 'Red' }[$Type]
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message) -ForegroundColor $couleur
}
