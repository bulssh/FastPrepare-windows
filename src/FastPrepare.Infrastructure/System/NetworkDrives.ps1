<#
    Lecteurs réseau persistants pour l'utilisateur de la session ouverte (itération 17).
    L'outil s'exécute avec des droits élevés, parfois sous un autre compte que celui de la session :
    le mappage est donc écrit dans la ruche de l'utilisateur (HKEY_USERS\<SID>\Network\<lettre>),
    exactement ce que « net use /persistent:yes » y écrit. Windows reconnecte le lecteur à
    l'ouverture de session suivante. Aucun script ni tâche planifiée.
#>

function Get-InteractiveUser {
    <#
        Utilisateur de la session ouverte : propriétaire de l'Explorateur de la session où tourne
        l'outil (à défaut, du premier Explorateur trouvé). Renvoie { Name, Sid }, ou $null.
    #>
    [CmdletBinding()]
    param()
    $sessionId = -1
    $self = Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId={0}' -f $PID) -ErrorAction SilentlyContinue
    if ($self) { $sessionId = [int]$self.SessionId }
    $shells = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue)
    $ordered = @($shells | Where-Object { $_.SessionId -eq $sessionId }) + @($shells | Where-Object { $_.SessionId -ne $sessionId })
    foreach ($shell in $ordered) {
        $sid = Invoke-CimMethod -InputObject $shell -MethodName GetOwnerSid -ErrorAction SilentlyContinue
        if (-not $sid -or $sid.ReturnValue -ne 0 -or -not $sid.Sid) { continue }
        $owner = Invoke-CimMethod -InputObject $shell -MethodName GetOwner -ErrorAction SilentlyContinue
        $name = if ($owner -and $owner.User) { '{0}\{1}' -f $owner.Domain, $owner.User } else { [string]$sid.Sid }
        return [pscustomobject]@{ Name = $name; Sid = [string]$sid.Sid }
    }
    return $null
}

function Get-UsedDriveLetter {
    <# Lettres déjà prises par les disques du poste (sans les deux-points). #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1).ToUpperInvariant() })
}

function Set-PersistentNetworkDrive {
    <#
        Écrit le mappage persistant d'un lecteur réseau dans la ruche d'un utilisateur.
        -UserRoot : racine de sa ruche (par défaut Registry::HKEY_USERS\<SID>, qui doit être
        chargée : sa session est ouverte). Un mappage déjà présent vers le même chemin est laissé
        tel quel ({ AlreadyPresent = $true }) ; vers un autre chemin, il n'est pas modifié : erreur.
        -LabelKeyName : nom de la clé MountPoints2 du libellé (FastPrepare.Core, Get-NetworkDriveLabelKeyName).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UserSid,
        [Parameter(Mandatory)][ValidatePattern('^[A-Z]$')][string]$Letter,
        [Parameter(Mandatory)][string]$Path,
        [string]$Label,
        [string]$LabelKeyName,
        [string]$UserRoot,
        $Log
    )
    if (-not $UserRoot) { $UserRoot = 'Registry::HKEY_USERS\{0}' -f $UserSid }
    if (-not (Test-Path -LiteralPath $UserRoot)) { throw "profil de l'utilisateur ($UserSid) non chargé : sa session doit être ouverte." }

    $key = Join-Path (Join-Path $UserRoot 'Network') $Letter
    $alreadyPresent = $false
    if (Test-Path -LiteralPath $key) {
        $existing = [string](Get-ItemProperty -LiteralPath $key -ErrorAction Stop).RemotePath
        if (-not [string]::Equals($existing.TrimEnd('\'), $Path.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("le lecteur {0}: de l'utilisateur est déjà connecté à {1} : il n'est pas modifié." -f $Letter, $existing)
        }
        $alreadyPresent = $true
    } else {
        New-Item -Path $key -Force -ErrorAction Stop | Out-Null
        # Mêmes valeurs que « net use /persistent:yes » (fournisseur : réseau Microsoft Windows).
        New-ItemProperty -LiteralPath $key -Name 'RemotePath' -PropertyType String -Value $Path -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -LiteralPath $key -Name 'UserName' -PropertyType String -Value '' -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -LiteralPath $key -Name 'ProviderName' -PropertyType String -Value 'Microsoft Windows Network' -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -LiteralPath $key -Name 'ProviderType' -PropertyType DWord -Value 0x20000 -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -LiteralPath $key -Name 'ConnectionType' -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -LiteralPath $key -Name 'DeferFlags' -PropertyType DWord -Value 4 -Force -ErrorAction Stop | Out-Null
        if ($Log) { Write-RunLog -Log $Log -Level DEBUG -Message ('Registre : {0} (RemotePath = {1})' -f $key, $Path) }
    }

    if ($Label -and $LabelKeyName) {
        $labelKey = Join-Path (Join-Path $UserRoot 'Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2') $LabelKeyName
        if (-not (Test-Path -LiteralPath $labelKey)) { New-Item -Path $labelKey -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -LiteralPath $labelKey -Name '_LabelFromReg' -PropertyType String -Value $Label -Force -ErrorAction Stop | Out-Null
    }
    return [pscustomobject]@{ AlreadyPresent = $alreadyPresent }
}
