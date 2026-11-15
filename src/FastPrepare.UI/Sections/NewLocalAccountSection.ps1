<#
    Section 11 — Sessions locales à créer (itération 8 ; plusieurs sessions depuis l'itération 15).
    Le technicien saisit une session puis l'ajoute à la liste ; chaque session de la liste devient
    une action du plan. Saisie vérifiée par FastPrepare.Core (Get-LocalAccountNameError,
    Get-LocalAccountPasswordError, Get-LocalAccountOptionError).
    Les mots de passe ne sont jamais lus en clair : seule PasswordBox.SecurePassword est utilisée ;
    la section garde une copie par session de la liste et la libère au retrait ou à la fermeture (DEC15).
#>

Register-UiSection -Id 'new-local-account' -Number 11 -Page 'comptes' -Column Left -XamlFile 'Sections\NewLocalAccount.xaml' -Initialize {
    param($Section, $Context)
    $c = $Section.Controls
    $Section.State.DefaultHint = "20 caractères max · mot de passe saisi deux fois · profil Windows créé à la première ouverture de session"
    $Section.State.ExistingNames = @()
    $Section.State.RemovedNames = @()
    $Section.State.ComputerNames = @()
    $Section.State.Accounts = New-Object System.Collections.Generic.List[object]

    # Valeurs par défaut du parc (config.json, bloc facultatif NewLocalAccount).
    $defaults = @{ Administrator = $false; PasswordNeverExpires = $true; MustChangePassword = $false }
    if ($Context.Config.PSObject.Properties['NewLocalAccount']) {
        foreach ($key in @($defaults.Keys)) {
            if ($Context.Config.NewLocalAccount.PSObject.Properties[$key]) { $defaults[$key] = [bool]$Context.Config.NewLocalAccount.$key }
        }
    }
    $Section.State.Defaults = $defaults
    Reset-NewLocalAccountForm -Section $Section

    # Update-UiState rappelle Refresh, qui met à jour l'affichage de la section.
    $onChange = { Invoke-UiAction -Name 'session à créer' -Action { Update-UiState } }
    $c.TxtNewName.Add_TextChanged($onChange)
    $c.TxtNewDescription.Add_TextChanged($onChange)
    $c.PwdNew.Add_PasswordChanged($onChange)
    $c.PwdNewConfirm.Add_PasswordChanged($onChange)
    # « À changer à la première ouverture » est grisé dès que « n'expire jamais » ou « ne peut pas
    # être changé » est coché (Windows ignorerait ou refuserait la combinaison).
    $onOption = {
        Invoke-UiAction -Name 'session à créer' -Action {
            Update-NewLocalAccountOption
            Update-UiState
        }
    }
    $c.ChkNewNeverExpires.Add_Click($onOption)
    $c.ChkNewCannotChange.Add_Click($onOption)
    $c.ChkNewMustChange.Add_Click($onOption)
    $c.BtnNewAdd.Add_Click({ Invoke-UiAction -Name 'ajout d''une session' -Action { Add-NewLocalAccountFromForm } })
    $c.TxtNewHint.Text = $Section.State.DefaultHint
} -OnSnapshot {
    param($Section, $Snapshot, $Context)
    $Section.State.ExistingNames = @($Snapshot.LocalAccounts.Names)
    $Section.State.ComputerNames = @(@([string]$Snapshot.Identity.HostName) | Where-Object { $_ })
    Update-NewLocalAccountView
} -Refresh {
    param($Section, $Selection)
    # Un nom libéré par la section 4 redevient disponible.
    $Section.State.RemovedNames = @(@($Selection.LocalAccounts.Items) | ForEach-Object { [string]$_.Name })
    Update-NewLocalAccountView
} -GetSelection {
    param($Section, $Selection)
    $items = foreach ($account in $Section.State.Accounts) {
        # Copie du mot de passe : libérée par Clear-SelectionSecret, celle de la section est gardée.
        $password = $null
        if ($account.Password) {
            $password = $account.Password.Copy()
            $password.MakeReadOnly()
        }
        New-LocalAccountRequest -Name $account.Name -FullName $account.FullName -Description $account.Description -Password $password `
            -Administrator:$account.Administrator -PasswordNeverExpires:$account.PasswordNeverExpires -MustChangePassword:$account.MustChangePassword `
            -CannotChangePassword:$account.CannotChangePassword -Disabled:$account.Disabled
    }
    $Selection.NewLocalAccounts.Items = @($items)
} -Validate {
    param($Section)
    $c = $Section.Controls
    if ($c.TxtNewName.Text.Length -gt 0) {
        return ("Grisé : session « {0} » saisie mais pas ajoutée à la liste (Ajouter à la liste, ou vider le nom)" -f $c.TxtNewName.Text)
    }
    $taken = @(Get-NewLocalAccountTakenName -Section $Section)
    foreach ($account in $Section.State.Accounts) {
        $nameError = Get-LocalAccountNameError -Name $account.Name -ExistingName $taken -ComputerName @($Section.State.ComputerNames)
        if ($nameError) { return ("Grisé : session à créer « {0} » — {1}" -f $account.Name, $nameError) }
        if (-not $account.Password) { return ("Grisé : session à créer « {0} » — mot de passe à saisir (bouton Modifier)" -f $account.Name) }
        $taken += $account.Name
    }
    return $null
} -Dispose {
    param($Section)
    # .ToArray() et non @(...) : sous Windows PowerShell 5.1, @() sur une List[object] lève « Argument types do not match ».
    foreach ($account in $Section.State.Accounts.ToArray()) {
        if ($account.Password) { $account.Password.Dispose() }
    }
    $Section.State.Accounts.Clear()
} -ExportProfile {
    param($Section, $CompanyProfile)
    # Tout sauf le mot de passe.
    $CompanyProfile.LocalAccounts = @($Section.State.Accounts | ForEach-Object {
            [pscustomobject][ordered]@{
                Name = $_.Name; FullName = $_.FullName; Description = $_.Description; Administrator = [bool]$_.Administrator
                PasswordNeverExpires = [bool]$_.PasswordNeverExpires; MustChangePassword = [bool]$_.MustChangePassword
                CannotChangePassword = [bool]$_.CannotChangePassword; Disabled = [bool]$_.Disabled
            }
        })
} -ImportProfile {
    param($Section, $CompanyProfile)
    # Les sessions du profil arrivent sans mot de passe : « Modifier » pour le saisir (Lancer reste grisé d'ici là).
    foreach ($existing in $Section.State.Accounts.ToArray()) {
        if ($existing.Password) { $existing.Password.Dispose() }
    }
    $Section.State.Accounts.Clear()
    foreach ($item in @($CompanyProfile.LocalAccounts)) {
        $Section.State.Accounts.Add((New-LocalAccountRequest -Name $item.Name -FullName $item.FullName -Description $item.Description -Password $null `
                    -Administrator:([bool]$item.Administrator) -PasswordNeverExpires:([bool]$item.PasswordNeverExpires) -MustChangePassword:([bool]$item.MustChangePassword) `
                    -CannotChangePassword:([bool]$item.CannotChangePassword) -Disabled:([bool]$item.Disabled)))
    }
    Reset-NewLocalAccountForm -Section $Section
    Update-NewLocalAccountList
}

function Get-NewLocalAccountTakenName {
    <# Comptes du poste qui existeront encore au moment de la création (ceux cochés pour suppression sont libérés). #>
    param($Section)
    return @($Section.State.ExistingNames | Where-Object { $Section.State.RemovedNames -notcontains $_ })
}

function Get-NewLocalAccountFormError {
    <# Motif qui empêche d'ajouter la session saisie à la liste, ou $null. #>
    param($Section)
    $c = $Section.Controls
    $taken = @(Get-NewLocalAccountTakenName -Section $Section) + @($Section.State.Accounts | ForEach-Object { $_.Name })
    $nameError = Get-LocalAccountNameError -Name ([string]$c.TxtNewName.Text) -ExistingName $taken -ComputerName @($Section.State.ComputerNames)
    if ($nameError) { return $nameError }

    $optionError = Get-LocalAccountOptionError -Description ([string]$c.TxtNewDescription.Text) -PasswordNeverExpires:([bool]$c.ChkNewNeverExpires.IsChecked) `
        -MustChangePassword:([bool]$c.ChkNewMustChange.IsChecked) -CannotChangePassword:([bool]$c.ChkNewCannotChange.IsChecked)
    if ($optionError) { return $optionError }

    $password = $c.PwdNew.SecurePassword
    $confirmation = $c.PwdNewConfirm.SecurePassword
    try {
        return (Get-LocalAccountPasswordError -Password $password -Confirmation $confirmation)
    } finally {
        $password.Dispose()
        $confirmation.Dispose()
    }
}

function Update-NewLocalAccountOption {
    <# Grise « à changer à la première ouverture » quand une option incompatible est cochée. #>
    $c = (Get-UiSection -Id 'new-local-account').Controls
    $blocked = [bool]$c.ChkNewNeverExpires.IsChecked -or [bool]$c.ChkNewCannotChange.IsChecked
    if ($blocked) { $c.ChkNewMustChange.IsChecked = $false }
    $c.ChkNewMustChange.IsEnabled = -not $blocked
}

function Reset-NewLocalAccountForm {
    <# Formulaire vide, options aux valeurs par défaut du parc. #>
    param($Section)
    $c = $Section.Controls
    $defaults = $Section.State.Defaults
    $c.TxtNewName.Text = ''
    $c.TxtNewFullName.Text = ''
    $c.TxtNewDescription.Text = ''
    $c.PwdNew.Clear()
    $c.PwdNewConfirm.Clear()
    $c.RbNewAdmin.IsChecked = [bool]$defaults.Administrator
    $c.RbNewUser.IsChecked = -not [bool]$defaults.Administrator
    $c.ChkNewNeverExpires.IsChecked = [bool]$defaults.PasswordNeverExpires
    $c.ChkNewMustChange.IsChecked = [bool]$defaults.MustChangePassword -and -not [bool]$defaults.PasswordNeverExpires
    $c.ChkNewCannotChange.IsChecked = $false
    $c.ChkNewDisabled.IsChecked = $false
    Update-NewLocalAccountOption
}

function Add-NewLocalAccountFromForm {
    <# Bouton « Ajouter à la liste » : vérifie la saisie, garde la session et vide le formulaire. #>
    $section = Get-UiSection -Id 'new-local-account'
    $c = $section.Controls
    $problem = Get-NewLocalAccountFormError -Section $section
    if ($problem) {
        $c.TxtNewHint.Text = 'À corriger : {0}' -f $problem
        $c.TxtNewHint.Foreground = Get-ThemeResource -Key 'ErrorBrush'
        return
    }
    $password = $c.PwdNew.SecurePassword    # copie gardée par la section jusqu'au retrait de la session
    $password.MakeReadOnly()
    $account = New-LocalAccountRequest -Name ([string]$c.TxtNewName.Text) -FullName ([string]$c.TxtNewFullName.Text).Trim() `
        -Description ([string]$c.TxtNewDescription.Text).Trim() -Password $password -Administrator:([bool]$c.RbNewAdmin.IsChecked) `
        -PasswordNeverExpires:([bool]$c.ChkNewNeverExpires.IsChecked) -MustChangePassword:([bool]$c.ChkNewMustChange.IsChecked) `
        -CannotChangePassword:([bool]$c.ChkNewCannotChange.IsChecked) -Disabled:([bool]$c.ChkNewDisabled.IsChecked)
    $section.State.Accounts.Add($account)
    Reset-NewLocalAccountForm -Section $section
    Update-NewLocalAccountList
    Update-UiState
}

function Remove-NewLocalAccountEntry {
    <# Retire une session de la liste et libère son mot de passe. -Edit : la remet dans le formulaire (sans mot de passe). #>
    param($Account, [switch]$Edit)
    $section = Get-UiSection -Id 'new-local-account'
    [void]$section.State.Accounts.Remove($Account)
    if ($Account.Password) { $Account.Password.Dispose() }
    $Account.Password = $null
    if ($Edit) {
        $c = $section.Controls
        Reset-NewLocalAccountForm -Section $section
        $c.TxtNewName.Text = [string]$Account.Name
        $c.TxtNewFullName.Text = [string]$Account.FullName
        $c.TxtNewDescription.Text = [string]$Account.Description
        $c.RbNewAdmin.IsChecked = [bool]$Account.Administrator
        $c.RbNewUser.IsChecked = -not [bool]$Account.Administrator
        $c.ChkNewNeverExpires.IsChecked = [bool]$Account.PasswordNeverExpires
        $c.ChkNewCannotChange.IsChecked = [bool]$Account.CannotChangePassword
        $c.ChkNewMustChange.IsChecked = [bool]$Account.MustChangePassword
        $c.ChkNewDisabled.IsChecked = [bool]$Account.Disabled
        Update-NewLocalAccountOption
    }
    Update-NewLocalAccountList
    Update-UiState
}

function Update-NewLocalAccountList {
    <# Reconstruit la liste des sessions à créer : résumé (sans mot de passe), Modifier, Retirer. #>
    $section = Get-UiSection -Id 'new-local-account'
    $panel = $section.Controls.PnlNewAccounts
    $panel.Children.Clear()
    foreach ($account in $section.State.Accounts) {
        $row = [System.Windows.Controls.DockPanel]::new()
        $row.Margin = [System.Windows.Thickness]::new(10, 6, 10, 6)

        foreach ($definition in @(@{ Text = 'Retirer'; Edit = $false }, @{ Text = 'Modifier'; Edit = $true })) {
            $button = [System.Windows.Controls.Button]::new()
            $button.Content = $definition.Text
            $button.Style = Get-ThemeResource -Key 'Secondary'
            $button.Height = 26
            $button.Width = 74
            $button.Margin = [System.Windows.Thickness]::new(6, 0, 0, 0)
            $button.Tag = $account
            [System.Windows.Controls.DockPanel]::SetDock($button, [System.Windows.Controls.Dock]::Right)
            if ($definition.Edit) {
                $button.Add_Click({
                        param($source, $clickArgs)
                        Invoke-UiAction -Name 'modification d''une session' -Action { Remove-NewLocalAccountEntry -Account $source.Tag -Edit }
                    })
            } else {
                $button.Add_Click({
                        param($source, $clickArgs)
                        Invoke-UiAction -Name 'retrait d''une session' -Action { Remove-NewLocalAccountEntry -Account $source.Tag }
                    })
            }
            [void]$row.Children.Add($button)
        }

        $text = [System.Windows.Controls.TextBlock]::new()
        $summary = Format-LocalAccountSummary -Name $account.Name -FullName $account.FullName -Administrator:$account.Administrator `
            -PasswordNeverExpires:$account.PasswordNeverExpires -MustChangePassword:$account.MustChangePassword `
            -CannotChangePassword:$account.CannotChangePassword -Disabled:$account.Disabled
        if (-not $account.Password) { $summary += ' · MOT DE PASSE À SAISIR' }
        $text.Text = $summary
        $text.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $text.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        if (-not $account.Password) { $text.Foreground = Get-ThemeResource -Key 'ErrorBrush' }
        [void]$row.Children.Add($text)

        [void]$panel.Children.Add($row)
    }
    $section.Controls.TxtNewNone.Visibility = if ($section.State.Accounts.Count -eq 0) { 'Visible' } else { 'Collapsed' }
}

function Update-NewLocalAccountView {
    <# Consigne sous le formulaire : rien de saisi, la consigne ; sinon le motif du refus, en rouge. #>
    $section = Get-UiSection -Id 'new-local-account'
    $c = $section.Controls
    $password = $c.PwdNew.SecurePassword
    try { $typed = $c.TxtNewName.Text.Length -gt 0 -or $password.Length -gt 0 } finally { $password.Dispose() }
    $problem = if ($typed) { Get-NewLocalAccountFormError -Section $section } else { $null }
    if ($problem) {
        $c.TxtNewHint.Text = 'À corriger : {0}' -f $problem
        $c.TxtNewHint.Foreground = Get-ThemeResource -Key 'ErrorBrush'
    } else {
        $c.TxtNewHint.Text = $section.State.DefaultHint
        $c.TxtNewHint.Foreground = Get-ThemeResource -Key 'TextSecondaryBrush'
    }
}
