<#
    Schéma de ce que le technicien a coché : contrat entre l'interface et le moteur.
    Chaque section d'interface écrit sa propre partie ; le moteur ne lit que cet objet,
    jamais les contrôles WPF. Fonction pure.
#>

function New-Selection {
    <# Sélection vide (rien n'est coché). #>
    [CmdletBinding()]
    param()

    $selection = [pscustomobject]@{
        PSTypeName     = 'FastPrepare.Selection'
        Software       = [pscustomobject]@{ Items = @() }
        MicrosoftApps  = [pscustomobject]@{
            OfficeClickToRun = $false
            OfficeMsi        = $false
            OutlookClassic   = $false
            OutlookNew       = $false
            OneNote          = $false
            Teams            = $false
            OneDrive         = $false
            OneDriveFolder   = $false
        }
        LocalAccounts  = [pscustomobject]@{ Items = @() }
        VendorUtility  = [pscustomobject]@{ Key = $null }
        Office         = [pscustomobject]@{ EditionKey = $null; WithoutTeams = $false; IncludedApps = @() }
        Updates        = [pscustomobject]@{ WindowsUpdate = $false; VendorUtility = $false }
        ExtraSoftware  = [pscustomobject]@{ Ids = @() }
        SystemSettings = [pscustomobject]@{ Ipv6Adapters = @(); Power = $false }
        # Sessions à créer (section 11, plusieurs depuis l'itération 15) : objets New-LocalAccountRequest.
        NewLocalAccounts = [pscustomobject]@{ Items = @() }
        # Agent RMM et antivirus : liens collés par le technicien (itération 16) ; vide = rien à installer.
        Agents         = [pscustomobject]@{ RmmUrl = ''; AntivirusUrl = '' }
        # Lecteurs réseau (New-NetworkDriveRequest) et imprimantes IP (New-IpPrinterRequest), itération 17.
        NetworkDrives  = [pscustomobject]@{ Items = @() }
        Printers       = [pscustomobject]@{ Items = @() }
        # Jonction au domaine (itération 18) : Domain vide = pas de jonction. Password : SecureString (DEC15).
        DomainJoin     = [pscustomobject]@{ Domain = ''; Account = ''; Password = $null }
    }
    return $selection
}

function Test-Selection {
    <#
        Cohérence d'une sélection avec la configuration et le relevé du poste. Renvoie la liste des
        incohérences (vide si tout va bien). Défense en profondeur : l'interface ne devrait pas
        permettre ces cas, le plan d'exécution refuse de se construire s'ils se présentent.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]$Selection,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$Snapshot,
        # Catalogue des logiciels de la section 8 (software.json, itération 9).
        [AllowEmptyCollection()][object[]]$SoftwareCatalog = @()
    )

    $problems = New-Object System.Collections.Generic.List[string]

    if ($Selection.MicrosoftApps.OneDriveFolder -and -not $Selection.MicrosoftApps.OneDrive) {
        $problems.Add('Suppression du dossier OneDrive demandée sans la désinstallation de OneDrive')
    }

    $removableSids = @(@($Snapshot.LocalAccounts.Removable) | ForEach-Object { [string]$_.Sid })
    foreach ($account in @($Selection.LocalAccounts.Items)) {
        if ($removableSids -notcontains [string]$account.Sid) {
            $problems.Add(("Session locale '{0}' absente des comptes supprimables" -f $account.Name))
        }
    }

    foreach ($problem in @(Get-NewLocalAccountProblem -Selection $Selection -Snapshot $Snapshot)) { $problems.Add($problem) }

    foreach ($agent in @(@{ Kind = 'Rmm'; Url = $Selection.Agents.RmmUrl; Label = 'Agent RMM' }, @{ Kind = 'Antivirus'; Url = $Selection.Agents.AntivirusUrl; Label = 'Antivirus' })) {
        if (-not ([string]$agent.Url).Trim()) { continue }
        $installer = Resolve-LinkInstaller -Kind $agent.Kind -Url $agent.Url
        if ($installer.Error) { $problems.Add(('{0} : {1}' -f $agent.Label, $installer.Error)) }
    }

    if (([string]$Selection.DomainJoin.Domain).Trim()) {
        $domainError = Get-DomainJoinError -Domain $Selection.DomainJoin.Domain -Account $Selection.DomainJoin.Account -Password $Selection.DomainJoin.Password
        if ($domainError) { $problems.Add(('Jonction au domaine : {0}' -f $domainError)) }
    }

    $letters = @()
    foreach ($drive in @($Selection.NetworkDrives.Items)) {
        $driveError = Get-NetworkDriveError -Drive $drive -UsedLetter $letters
        if ($driveError) { $problems.Add(('Lecteur réseau {0} : {1}' -f (Format-NetworkDriveSummary -Drive $drive), $driveError)) }
        $letters += [string]$drive.Letter
    }
    $printerNames = @()
    foreach ($printer in @($Selection.Printers.Items)) {
        $printerError = Get-IpPrinterError -Printer $printer -ExistingName $printerNames
        if ($printerError) { $problems.Add(("Imprimante '{0}' : {1}" -f $printer.Name, $printerError)) }
        $printerNames += [string]$printer.Name
    }

    $utilityKey = $Selection.VendorUtility.Key
    if ($utilityKey -and -not $Config.Utilities.PSObject.Properties[$utilityKey]) {
        $problems.Add("Utilitaire constructeur inconnu : '$utilityKey'")
    }
    if ($Selection.Updates.VendorUtility -and -not $utilityKey) {
        $problems.Add("Mise à jour de l'utilitaire constructeur demandée sans utilitaire choisi")
    }

    $editionKey = $Selection.Office.EditionKey
    if ($editionKey) {
        $edition = @($Config.Office.Editions) | Where-Object { $_.Key -eq $editionKey } | Select-Object -First 1
        if (-not $edition) { $problems.Add("Édition Office inconnue : '$editionKey'") }
        elseif ($Selection.Office.WithoutTeams -and -not (Test-OfficeEditionHasNoTeamsVariant -Edition $edition)) {
            $problems.Add("L'édition '$editionKey' ne propose pas de variante sans Teams")
        }
        $knownApps = @(@($Config.Office.OptionalApps) | ForEach-Object { [string]$_.Id })
        foreach ($app in @($Selection.Office.IncludedApps)) {
            if ($knownApps -notcontains $app) { $problems.Add("Application Office facultative inconnue : '$app'") }
        }
    }

    $knownSoftware = @(@($SoftwareCatalog) | ForEach-Object { [string]$_.Id })
    foreach ($id in @($Selection.ExtraSoftware.Ids)) {
        if ($knownSoftware -notcontains $id) { $problems.Add("Logiciel inconnu (section 8) : '$id'") }
    }

    return $problems.ToArray()
}

function Get-NewLocalAccountProblem {
    <#
        Incohérences des sessions à créer : nom refusé (comptes qui existeront encore après les
        suppressions cochées, nom du poste, nom demandé deux fois), mot de passe absent ou trop
        long, options contradictoires, description trop longue.
    #>
    param($Selection, $Snapshot)
    $accounts = @($Selection.NewLocalAccounts.Items)
    if ($accounts.Count -eq 0) { return }

    $removed = @(@($Selection.LocalAccounts.Items) | ForEach-Object { [string]$_.Name })
    $existing = @()
    if ($Snapshot.LocalAccounts -and $Snapshot.LocalAccounts.PSObject.Properties['Names']) {
        $existing = @(@($Snapshot.LocalAccounts.Names) | Where-Object { $removed -notcontains $_ })
    }
    $computers = @([string]$Snapshot.Identity.HostName)

    foreach ($account in $accounts) {
        $label = "Session à créer '{0}'" -f $account.Name
        $nameError = Get-LocalAccountNameError -Name $account.Name -ExistingName $existing -ComputerName $computers
        if ($nameError) { ("{0} : nom refusé ({1})" -f $label, $nameError) }
        $passwordError = Get-LocalAccountPasswordError -Password $account.Password
        if ($passwordError) { ("{0} : {1}" -f $label, $passwordError) }
        $optionError = Get-LocalAccountOptionError -Description $account.Description -PasswordNeverExpires:([bool]$account.PasswordNeverExpires) -MustChangePassword:([bool]$account.MustChangePassword) -CannotChangePassword:([bool]$account.CannotChangePassword)
        if ($optionError) { ("{0} : {1}" -f $label, $optionError) }
        # Les sessions suivantes ne peuvent pas reprendre ce nom.
        $existing += [string]$account.Name
    }
}

function Clear-SelectionSecret {
    <#
        Libère les mots de passe portés par la sélection (les actions du plan référencent les
        mêmes objets). À appeler dès que la sélection n'est plus utile.
    #>
    [CmdletBinding()]
    param([AllowNull()]$Selection)
    if (-not $Selection) { return }
    if ($Selection.PSObject.Properties['NewLocalAccounts']) {
        foreach ($account in @($Selection.NewLocalAccounts.Items)) {
            if ($account.Password -is [System.Security.SecureString]) { $account.Password.Dispose() }
            $account.Password = $null
        }
    }
    if ($Selection.PSObject.Properties['DomainJoin']) {
        if ($Selection.DomainJoin.Password -is [System.Security.SecureString]) { $Selection.DomainJoin.Password.Dispose() }
        $Selection.DomainJoin.Password = $null
    }
}
