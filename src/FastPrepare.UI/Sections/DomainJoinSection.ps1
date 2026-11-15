<#
    Section 15 — Jonction au domaine Active Directory (itération 18).
    Domaine, compte autorisé à joindre et mot de passe ; domaine vide = pas de jonction.
    « Tester » vérifie, sans rien modifier, que le domaine répond et que le compte est accepté
    (FastPrepare.Application, Test-DomainJoinSetting). La jonction est la dernière action du plan.
    Le mot de passe n'est jamais lu en clair : seule PasswordBox.SecurePassword est utilisée (DEC15).
#>

Register-UiSection -Id 'domain-join' -Number 15 -Page 'comptes' -Column Right -XamlFile 'Sections\DomainJoin.xaml' -Initialize {
    param($Section, $Context)
    $c = $Section.Controls
    $Section.State.TestRunning = $false
    $Section.State.TestPassword = $null
    $Section.State.DefaultHint = 'Domaine vide : pas de jonction. La jonction est faite en dernier et devient effective au redémarrage final, à faire à la main. Mot de passe saisi à chaque préparation, jamais enregistré.'
    $c.TxtDomainHint.Text = $Section.State.DefaultHint

    $onChange = {
        Invoke-UiAction -Name 'jonction au domaine' -Action {
            # Une saisie modifiée rend le dernier résultat de test caduc.
            $section = Get-UiSection -Id 'domain-join'
            if (-not $section.State.TestRunning) { $section.Controls.PnlDomainTest.Children.Clear() }
            Update-DomainJoinView
            Update-UiState
        }
    }
    $c.TxtDomainName.Add_TextChanged($onChange)
    $c.TxtDomainAccount.Add_TextChanged($onChange)
    $c.PwdDomain.Add_PasswordChanged($onChange)
    $c.BtnDomainTest.Add_Click({ Invoke-UiAction -Name 'test du domaine' -Action { Start-DomainJoinFormTest } })
    Update-DomainJoinView
} -GetSelection {
    param($Section, $Selection)
    $c = $Section.Controls
    $domain = ([string]$c.TxtDomainName.Text).Trim()
    if (-not $domain) { return }
    $Selection.DomainJoin.Domain = $domain
    $Selection.DomainJoin.Account = ([string]$c.TxtDomainAccount.Text).Trim()
    $password = $c.PwdDomain.SecurePassword    # copie : libérée par Clear-SelectionSecret
    $password.MakeReadOnly()
    $Selection.DomainJoin.Password = $password
} -Validate {
    param($Section)
    $problem = Get-DomainJoinFormError -Section $Section
    if ($problem) { return "Grisé : jonction au domaine — $problem" }
    return $null
} -Dispose {
    param($Section)
    if ($Section.State.TestPassword) { $Section.State.TestPassword.Dispose() }
} -ExportProfile {
    param($Section, $CompanyProfile)
    $CompanyProfile.Domain.Domain = ([string]$Section.Controls.TxtDomainName.Text).Trim()
    $CompanyProfile.Domain.Account = ([string]$Section.Controls.TxtDomainAccount.Text).Trim()
} -ImportProfile {
    param($Section, $CompanyProfile)
    # Le mot de passe n'est jamais dans un profil : il est à saisir à chaque préparation.
    $Section.Controls.TxtDomainName.Text = [string]$CompanyProfile.Domain.Domain
    $Section.Controls.TxtDomainAccount.Text = [string]$CompanyProfile.Domain.Account
    $Section.Controls.PwdDomain.Clear()
    $Section.Controls.PnlDomainTest.Children.Clear()
    Update-DomainJoinView
}

function Get-DomainJoinFormError {
    <# Motif qui empêche la jonction saisie, ou $null (domaine vide : pas de jonction, donc pas de motif). #>
    param($Section)
    $c = $Section.Controls
    if (-not ([string]$c.TxtDomainName.Text).Trim()) { return $null }
    $password = $c.PwdDomain.SecurePassword
    try {
        return (Get-DomainJoinError -Domain ([string]$c.TxtDomainName.Text) -Account ([string]$c.TxtDomainAccount.Text) -Password $password)
    } finally {
        $password.Dispose()
    }
}

function Update-DomainJoinView {
    <# Consigne sous le formulaire et état du bouton Tester. #>
    $section = Get-UiSection -Id 'domain-join'
    $c = $section.Controls
    $problem = Get-DomainJoinFormError -Section $section
    $typed = [bool]([string]$c.TxtDomainName.Text).Trim()
    $c.BtnDomainTest.IsEnabled = $typed -and -not $problem -and -not $section.State.TestRunning
    if ($problem) {
        $c.TxtDomainHint.Text = 'À corriger : {0}' -f $problem
        $c.TxtDomainHint.Foreground = Get-ThemeResource -Key 'ErrorBrush'
    } else {
        $c.TxtDomainHint.Text = $section.State.DefaultHint
        $c.TxtDomainHint.Foreground = Get-ThemeResource -Key 'TextSecondaryBrush'
    }
}

function Complete-DomainJoinFormTest {
    <# Fin du test : libère la copie du mot de passe et affiche les lignes de résultat. #>
    param([object[]]$Line)
    $section = Get-UiSection -Id 'domain-join'
    $section.State.TestRunning = $false
    if ($section.State.TestPassword) { $section.State.TestPassword.Dispose() }
    $section.State.TestPassword = $null
    $panel = $section.Controls.PnlDomainTest
    $panel.Children.Clear()
    foreach ($item in @($Line)) { [void]$panel.Children.Add((New-SoftwareTestLine -Level $item.Level -Text $item.Text)) }
    Update-DomainJoinView
}

function Start-DomainJoinFormTest {
    <# Bouton Tester : interroge le domaine en arrière-plan, sans rien modifier sur le poste ni dans l'annuaire. #>
    $section = Get-UiSection -Id 'domain-join'
    if ($section.State.TestRunning) { return }
    $c = $section.Controls
    $section.State.TestRunning = $true
    $password = $c.PwdDomain.SecurePassword    # copie gardée le temps du test
    $password.MakeReadOnly()
    $section.State.TestPassword = $password
    $c.PnlDomainTest.Children.Clear()
    [void]$c.PnlDomainTest.Children.Add((New-SoftwareTestLine -Level 'INFO' -Text 'Test en cours (rien n''est modifié)…'))
    Update-DomainJoinView

    try {
        $work = Start-DomainJoinTest -Context $script:Context -Domain ([string]$c.TxtDomainName.Text).Trim() -Account ([string]$c.TxtDomainAccount.Text).Trim() -Password $password
    } catch {
        Complete-DomainJoinFormTest -Line @([pscustomobject]@{ Level = 'ERREUR'; Text = "Test impossible : $($_.Exception.Message)" })
        return
    }
    Register-UiBackgroundWork -Work $work -OnCompleted {
        param($result)
        $outcome = @($result)[-1]
        Complete-DomainJoinFormTest -Line @($outcome.Lines)
    } -OnFailed {
        param($message)
        Complete-DomainJoinFormTest -Line @([pscustomobject]@{ Level = 'ERREUR'; Text = "Test interrompu : $message" })
    }
}
