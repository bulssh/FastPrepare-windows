<#
    Étape 13 — Création des sessions locales (section 11, une action par session, fonctionnalité ajoutée après le cahier,
    décisions DEC14 à DEC16 du plan d'architecture).
    Le mot de passe voyage en SecureString dans Parameters, que le moteur ne journalise jamais ;
    le libellé est construit sans lui (Format-LocalAccountSummary ne le reçoit pas).
#>

Register-Step -Id 'create-local-account' -Section 11 -Title 'Création des sessions locales' -Plan {
    param($Selection, $Snapshot, $Context)
    $computerNames = @([string]$Snapshot.Identity.HostName)
    foreach ($account in @($Selection.NewLocalAccounts.Items)) {
        $summary = Format-LocalAccountSummary -Name $account.Name -FullName $account.FullName -Administrator:([bool]$account.Administrator) -PasswordNeverExpires:([bool]$account.PasswordNeverExpires) -MustChangePassword:([bool]$account.MustChangePassword) -CannotChangePassword:([bool]$account.CannotChangePassword) -Disabled:([bool]$account.Disabled)

        New-StepAction -Label ("Session locale : New-LocalUser {0}" -f $summary) -Parameters @{
            Kind                 = 'NewLocalAccount'
            Name                 = [string]$account.Name
            FullName             = [string]$account.FullName
            Description          = [string]$account.Description
            Password             = $account.Password
            Administrator        = [bool]$account.Administrator
            PasswordNeverExpires = [bool]$account.PasswordNeverExpires
            MustChangePassword   = [bool]$account.MustChangePassword
            CannotChangePassword = [bool]$account.CannotChangePassword
            Disabled             = [bool]$account.Disabled
            ComputerNames        = $computerNames
        }
    }
} -Invoke {
    param($Action, $Context)
    $p = $Action.Parameters
    # Dernière vérification avec les comptes relus sur le poste (des sessions ont pu être supprimées ou créées entre-temps).
    $existing = @(Get-LocalAccount | ForEach-Object { [string]$_.Name })
    $nameError = Get-LocalAccountNameError -Name $p.Name -ExistingName $existing -ComputerName $p.ComputerNames
    if ($nameError) { throw "nom de session refusé ($nameError)" }
    $passwordError = Get-LocalAccountPasswordError -Password $p.Password
    if ($passwordError) { throw $passwordError }

    $groups = Get-LocalAccountGroupSid -Administrator:([bool]$p.Administrator)
    $result = New-LocalAccount -Name $p.Name -FullName $p.FullName -Description $p.Description -Password $p.Password -GroupSid $groups -PasswordNeverExpires:([bool]$p.PasswordNeverExpires) -MustChangePassword:([bool]$p.MustChangePassword) -CannotChangePassword:([bool]$p.CannotChangePassword) -Disabled:([bool]$p.Disabled) -Log $Context.Log
    Write-RunLog -Log $Context.Log -Message ("Session '{0}' créée ; son profil sera créé à la première ouverture de session" -f $result.Name)
}
