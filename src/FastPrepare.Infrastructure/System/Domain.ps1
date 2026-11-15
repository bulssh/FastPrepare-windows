<#
    Domaine Active Directory (itération 18) : état du poste, recherche des contrôleurs,
    vérification d'un compte et jonction. Le mot de passe reste une SecureString d'un bout à
    l'autre (DEC15) ; la jonction ne redémarre jamais le poste.
#>

function Get-ComputerDomainState {
    <# { PartOfDomain, Domain } : Domain est le domaine du poste, ou son groupe de travail. #>
    [CmdletBinding()]
    param()
    $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    return [pscustomobject]@{ PartOfDomain = [bool]$system.PartOfDomain; Domain = [string]$system.Domain }
}

function Find-DomainController {
    <# Noms des contrôleurs du domaine annoncés par le DNS du poste (enregistrements SRV) ; erreur si le domaine est introuvable. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$Domain)
    $records = @(Resolve-DnsName -Name ('_ldap._tcp.dc._msdcs.{0}' -f $Domain) -Type SRV -ErrorAction Stop)
    return @($records | Where-Object { $_.PSObject.Properties['NameTarget'] -and $_.NameTarget } | ForEach-Object { [string]$_.NameTarget } | Sort-Object -Unique)
}

function Test-DomainCredential {
    <#
        Vérifie un compte auprès du domaine par une ouverture de session LDAP (rien n'est modifié
        dans l'annuaire). -User et -UserDomain : FastPrepare.Core, Split-DomainAccount.
        Erreur lisible si le domaine ne répond pas ou si le compte est refusé.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][string]$User,
        [AllowEmptyString()][string]$UserDomain,
        [Parameter(Mandatory)][System.Security.SecureString]$Password,
        [int]$TimeoutSeconds = 15
    )
    Add-Type -AssemblyName System.DirectoryServices.Protocols
    $identifier = New-Object System.DirectoryServices.Protocols.LdapDirectoryIdentifier($Domain, 389)
    # Constructeur (nom, SecureString, domaine) : le mot de passe n'est jamais une chaîne.
    $credential = New-Object System.Net.NetworkCredential($User, $Password, $UserDomain)
    $connection = New-Object System.DirectoryServices.Protocols.LdapConnection($identifier, $credential, [System.DirectoryServices.Protocols.AuthType]::Negotiate)
    try {
        $connection.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
        $connection.SessionOptions.Signing = $true
        $connection.SessionOptions.Sealing = $true
        $connection.Bind()
    } catch {
        $inner = $_.Exception
        while ($inner.InnerException) { $inner = $inner.InnerException }
        if ($inner -is [System.DirectoryServices.Protocols.LdapException] -and $inner.ErrorCode -eq 49) {
            throw 'compte ou mot de passe refusé par le domaine.'
        }
        throw ('domaine injoignable ou session refusée : {0}' -f $inner.Message)
    } finally {
        $connection.Dispose()
    }
}

function Join-ComputerToDomain {
    <#
        Joint le poste au domaine (Add-Computer), dans le conteneur par défaut. Aucun redémarrage :
        la jonction est effective au redémarrage suivant, fait à la main par le technicien.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][string]$QualifiedAccount,
        [Parameter(Mandatory)][System.Security.SecureString]$Password,
        $Log
    )
    $credential = New-Object System.Management.Automation.PSCredential($QualifiedAccount, $Password)
    if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message "Add-Computer -DomainName $Domain (compte $QualifiedAccount)" }
    Add-Computer -DomainName $Domain -Credential $credential -Force -WarningAction SilentlyContinue -ErrorAction Stop
}
