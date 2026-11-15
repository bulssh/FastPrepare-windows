<#
    Profils entreprise (itération 14) : réglages d'un client enregistrés sur la clé
    (profils\<nom>.json) et rappelés d'un clic pour pré-remplir la fenêtre. Fonctions pures.
    Un profil ne contient JAMAIS de mot de passe : ConvertTo-CompanyProfile ne recopie que des
    champs connus, dont aucun n'en porte ; les mots de passe sont saisis à chaque préparation.
    Ce qui dépend du poste (logiciels à désinstaller, sessions à supprimer, constructeur, cartes
    réseau) n'est pas dans un profil.
#>

$script:CompanyProfileVersion = 1
$script:MaxCompanyProfileNameLength = 60

function New-CompanyProfile {
    <# Profil vide (rien de coché, aucune liste). #>
    [CmdletBinding()]
    param([string]$Name = '')
    return [pscustomobject][ordered]@{
        ProfileVersion = $script:CompanyProfileVersion
        Name           = $Name
        MicrosoftApps  = [pscustomobject][ordered]@{
            OfficeClickToRun = $false; OfficeMsi = $false; OutlookClassic = $false; OutlookNew = $false
            OneNote = $false; Teams = $false; OneDrive = $false; OneDriveFolder = $false
        }
        Office         = [pscustomobject][ordered]@{ EditionKey = ''; WithoutTeams = $false; IncludedApps = @() }
        Software       = @()
        WindowsUpdate  = $true
        Power          = $true
        LocalAccounts  = @()
        Agents         = [pscustomobject][ordered]@{ RmmUrl = ''; AntivirusUrl = '' }
        NetworkDrives  = @()
        Printers       = @()
        Domain         = [pscustomobject][ordered]@{ Domain = ''; Account = '' }
    }
}

function ConvertTo-CompanyProfile {
    <#
        Profil normalisé à partir d'un objet lu dans un fichier (ou construit par l'interface) :
        champs connus seulement, types forcés, valeurs absentes remplacées par celles du profil vide.
    #>
    [CmdletBinding()]
    param([AllowNull()]$InputObject)

    $result = New-CompanyProfile -Name (Get-ProfileText -Object $InputObject -Name 'Name')
    if ($null -eq $InputObject) { return $result }

    $apps = Get-ProfileValue -Object $InputObject -Name 'MicrosoftApps'
    foreach ($property in @($result.MicrosoftApps.PSObject.Properties)) {
        $property.Value = Get-ProfileBool -Object $apps -Name $property.Name -Default $false
    }

    $office = Get-ProfileValue -Object $InputObject -Name 'Office'
    $result.Office.EditionKey = Get-ProfileText -Object $office -Name 'EditionKey'
    $result.Office.WithoutTeams = Get-ProfileBool -Object $office -Name 'WithoutTeams' -Default $false
    $result.Office.IncludedApps = @(Get-ProfileList -Object $office -Name 'IncludedApps' | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })

    $result.Software = @(Get-ProfileList -Object $InputObject -Name 'Software' | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    $result.WindowsUpdate = Get-ProfileBool -Object $InputObject -Name 'WindowsUpdate' -Default $true
    $result.Power = Get-ProfileBool -Object $InputObject -Name 'Power' -Default $true

    $result.LocalAccounts = @(Get-ProfileList -Object $InputObject -Name 'LocalAccounts' | ForEach-Object {
            [pscustomobject][ordered]@{
                Name                 = Get-ProfileText -Object $_ -Name 'Name'
                FullName             = Get-ProfileText -Object $_ -Name 'FullName'
                Description          = Get-ProfileText -Object $_ -Name 'Description'
                Administrator        = Get-ProfileBool -Object $_ -Name 'Administrator' -Default $false
                PasswordNeverExpires = Get-ProfileBool -Object $_ -Name 'PasswordNeverExpires' -Default $false
                MustChangePassword   = Get-ProfileBool -Object $_ -Name 'MustChangePassword' -Default $false
                CannotChangePassword = Get-ProfileBool -Object $_ -Name 'CannotChangePassword' -Default $false
                Disabled             = Get-ProfileBool -Object $_ -Name 'Disabled' -Default $false
            }
        } | Where-Object { $_.Name })

    $agents = Get-ProfileValue -Object $InputObject -Name 'Agents'
    $result.Agents.RmmUrl = Get-ProfileText -Object $agents -Name 'RmmUrl'
    $result.Agents.AntivirusUrl = Get-ProfileText -Object $agents -Name 'AntivirusUrl'

    $result.NetworkDrives = @(Get-ProfileList -Object $InputObject -Name 'NetworkDrives' | ForEach-Object {
            $drive = New-NetworkDriveRequest -Letter (Get-ProfileText -Object $_ -Name 'Letter') -Path (Get-ProfileText -Object $_ -Name 'Path') -Label (Get-ProfileText -Object $_ -Name 'Label')
            [pscustomobject][ordered]@{ Letter = $drive.Letter; Path = $drive.Path; Label = $drive.Label }
        } | Where-Object { $_.Path })

    $result.Printers = @(Get-ProfileList -Object $InputObject -Name 'Printers' | ForEach-Object {
            [pscustomobject][ordered]@{
                Name       = Get-ProfileText -Object $_ -Name 'Name'
                Address    = Get-ProfileText -Object $_ -Name 'Address'
                InfPath    = Get-ProfileText -Object $_ -Name 'InfPath'
                DriverName = Get-ProfileText -Object $_ -Name 'DriverName'
            }
        } | Where-Object { $_.Name })

    $domain = Get-ProfileValue -Object $InputObject -Name 'Domain'
    $result.Domain.Domain = Get-ProfileText -Object $domain -Name 'Domain'
    $result.Domain.Account = Get-ProfileText -Object $domain -Name 'Account'
    return $result
}

function Get-CompanyProfileError {
    <#
        Incohérences d'un profil (liste vide si tout va bien) : nom, version, et les mêmes règles
        que la saisie pour ses listes. -ExistingName : noms des autres profils de la clé.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]$CompanyProfile,
        [AllowEmptyCollection()][string[]]$ExistingName = @()
    )
    $problems = New-Object System.Collections.Generic.List[string]
    $name = [string]$CompanyProfile.Name
    if (-not $name.Trim()) { $problems.Add('nom du profil vide') }
    elseif ($name.Length -gt $script:MaxCompanyProfileNameLength) { $problems.Add(('nom du profil de {0} caractères sur {1} maximum' -f $name.Length, $script:MaxCompanyProfileNameLength)) }
    elseif ($name -match '[\\/:*?"<>|]') { $problems.Add('caractère interdit dans le nom du profil (\ / : * ? " < > |)') }
    foreach ($existing in @($ExistingName)) {
        if ($existing -and [string]::Equals($existing.Trim(), $name.Trim(), [System.StringComparison]::OrdinalIgnoreCase)) { $problems.Add(("un profil « {0} » existe déjà" -f $existing)) }
    }
    if ([int]$CompanyProfile.ProfileVersion -ne $script:CompanyProfileVersion) {
        $problems.Add(('version de profil {0} non prise en charge (attendue : {1})' -f $CompanyProfile.ProfileVersion, $script:CompanyProfileVersion))
    }

    $accountNames = @()
    foreach ($account in @($CompanyProfile.LocalAccounts)) {
        $accountError = Get-LocalAccountNameError -Name $account.Name -ExistingName $accountNames
        if (-not $accountError) {
            $accountError = Get-LocalAccountOptionError -Description $account.Description -PasswordNeverExpires:([bool]$account.PasswordNeverExpires) -MustChangePassword:([bool]$account.MustChangePassword) -CannotChangePassword:([bool]$account.CannotChangePassword)
        }
        if ($accountError) { $problems.Add(("session '{0}' : {1}" -f $account.Name, $accountError)) }
        $accountNames += [string]$account.Name
    }
    $letters = @()
    foreach ($drive in @($CompanyProfile.NetworkDrives)) {
        $driveError = Get-NetworkDriveError -Drive $drive -UsedLetter $letters
        if ($driveError) { $problems.Add(('lecteur réseau {0} : {1}' -f (Format-NetworkDriveSummary -Drive $drive), $driveError)) }
        $letters += [string]$drive.Letter
    }
    $printerNames = @()
    foreach ($printer in @($CompanyProfile.Printers)) {
        $printerError = Get-IpPrinterError -Printer $printer -ExistingName $printerNames
        if ($printerError) { $problems.Add(("imprimante '{0}' : {1}" -f $printer.Name, $printerError)) }
        $printerNames += [string]$printer.Name
    }
    foreach ($agent in @(@{ Kind = 'Rmm'; Url = $CompanyProfile.Agents.RmmUrl; Label = 'agent RMM' }, @{ Kind = 'Antivirus'; Url = $CompanyProfile.Agents.AntivirusUrl; Label = 'antivirus' })) {
        if (-not $agent.Url) { continue }
        $installer = Resolve-LinkInstaller -Kind $agent.Kind -Url $agent.Url
        if ($installer.Error) { $problems.Add(('{0} : {1}' -f $agent.Label, $installer.Error)) }
    }
    if ($CompanyProfile.Domain.Domain) {
        $domainError = Get-DomainJoinError -Domain $CompanyProfile.Domain.Domain -Account $CompanyProfile.Domain.Account
        if ($domainError) { $problems.Add(('domaine : {0}' -f $domainError)) }
    }
    return $problems.ToArray()
}

function Get-CompanyProfileFileName {
    <# Nom du fichier d'un profil : son nom en minuscules sans accent, tirets à la place du reste, puis .json. #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)
    $decomposed = $Name.Normalize([System.Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder
    foreach ($char in $decomposed.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$builder.Append($char) }
    }
    $base = [regex]::Replace($builder.ToString().ToLowerInvariant(), '[^a-z0-9]+', '-').Trim('-')
    if (-not $base) { $base = 'profil' }
    return ($base + '.json')
}

function Get-ProfileValue {
    <# Valeur d'une propriété, ou $null si l'objet ou la propriété manque. #>
    param($Object, [string]$Name)
    if ($null -eq $Object -or -not ($Object -is [System.Management.Automation.PSCustomObject]) -or -not $Object.PSObject.Properties[$Name]) { return $null }
    return $Object.$Name
}

function Get-ProfileText {
    param($Object, [string]$Name)
    $value = Get-ProfileValue -Object $Object -Name $Name
    if ($null -eq $value -or $value -is [System.Management.Automation.PSCustomObject] -or $value -is [array]) { return '' }
    return ([string]$value).Trim()
}

function Get-ProfileBool {
    param($Object, [string]$Name, [bool]$Default)
    $value = Get-ProfileValue -Object $Object -Name $Name
    if ($value -is [bool]) { return $value }
    return $Default
}

function Get-ProfileList {
    <# Éléments d'une propriété liste (rien si elle manque ; une valeur seule compte pour une liste d'un élément). #>
    param($Object, [string]$Name)
    $value = Get-ProfileValue -Object $Object -Name $Name
    if ($null -eq $value) { return }
    foreach ($item in @($value)) { if ($null -ne $item) { $item } }
}
