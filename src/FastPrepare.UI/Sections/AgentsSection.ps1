<#
    Section 12 — Agent RMM et antivirus par lien (itération 16).
    Le technicien colle le lien fourni par la console de l'éditeur ; l'installateur est reconnu
    au fil de la saisie (FastPrepare.Core, Resolve-LinkInstaller) et la commande prévue est
    affichée. Champ vide : rien à installer.
#>

Register-UiSection -Id 'agents' -Number 12 -Page 'installations' -Column Right -XamlFile 'Sections\Agents.xaml' -Initialize {
    param($Section, $Context)
    $onChange = {
        Invoke-UiAction -Name 'liens RMM et antivirus' -Action {
            Update-AgentsView
            Update-UiState
        }
    }
    $Section.Controls.TxtRmmUrl.Add_TextChanged($onChange)
    $Section.Controls.TxtAvUrl.Add_TextChanged($onChange)
    Update-AgentsView
} -GetSelection {
    param($Section, $Selection)
    $Selection.Agents.RmmUrl = ([string]$Section.Controls.TxtRmmUrl.Text).Trim()
    $Selection.Agents.AntivirusUrl = ([string]$Section.Controls.TxtAvUrl.Text).Trim()
} -Validate {
    param($Section)
    foreach ($field in (Get-AgentsField -Section $Section)) {
        if (-not $field.Url) { continue }
        $installer = Resolve-LinkInstaller -Kind $field.Kind -Url $field.Url
        if ($installer.Error) { return ('Grisé : {0} — {1}' -f $field.Label, $installer.Error) }
    }
    return $null
} -ExportProfile {
    param($Section, $CompanyProfile)
    $CompanyProfile.Agents.RmmUrl = ([string]$Section.Controls.TxtRmmUrl.Text).Trim()
    $CompanyProfile.Agents.AntivirusUrl = ([string]$Section.Controls.TxtAvUrl.Text).Trim()
} -ImportProfile {
    param($Section, $CompanyProfile)
    $Section.Controls.TxtRmmUrl.Text = [string]$CompanyProfile.Agents.RmmUrl
    $Section.Controls.TxtAvUrl.Text = [string]$CompanyProfile.Agents.AntivirusUrl
    Update-AgentsView
}

function Get-AgentsField {
    <# Les deux champs de la section : genre d'installateur, lien saisi, zone de consigne. #>
    param($Section)
    $c = $Section.Controls
    [pscustomobject]@{ Kind = 'Rmm'; Label = 'lien de l''agent RMM'; Url = ([string]$c.TxtRmmUrl.Text).Trim(); Hint = $c.TxtRmmHint; Empty = 'Vide : aucun agent RMM installé par l''outil.' }
    [pscustomobject]@{ Kind = 'Antivirus'; Label = 'lien de l''antivirus'; Url = ([string]$c.TxtAvUrl.Text).Trim(); Hint = $c.TxtAvHint; Empty = 'Vide : aucun antivirus installé par l''outil.' }
}

function Update-AgentsView {
    <# Sous chaque champ : la commande prévue, ou le motif du refus en rouge. #>
    $section = Get-UiSection -Id 'agents'
    foreach ($field in (Get-AgentsField -Section $section)) {
        if (-not $field.Url) {
            $field.Hint.Text = $field.Empty
            $field.Hint.Foreground = Get-ThemeResource -Key 'TextSecondaryBrush'
            continue
        }
        $installer = Resolve-LinkInstaller -Kind $field.Kind -Url $field.Url
        if ($installer.Error) {
            $field.Hint.Text = 'À corriger : {0}' -f $installer.Error
            $field.Hint.Foreground = Get-ThemeResource -Key 'ErrorBrush'
        } else {
            $run = if ($installer.Runner -eq 'msiexec') { 'msiexec /i {0}' -f $installer.FileName } else { $installer.FileName }
            if ($installer.Arguments) { $run += ' ' + $installer.Arguments }
            $field.Hint.Text = '{0} reconnu : {1}' -f $installer.Product, $run
            $field.Hint.Foreground = Get-ThemeResource -Key 'SuccessBrush'
        }
    }
}
