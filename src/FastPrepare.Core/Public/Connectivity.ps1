<#
    Règle de journalisation de la connexion internet (DEC28).
    Une coupure courte (démarrage du poste, reprise après une mise en veille) n'est pas une erreur :
    elle n'est écrite en ERREUR que si elle dure au-delà du délai de grâce. Une coupure plus longue,
    pendant l'exécution ou avant, reste une erreur au journal.
#>

function Get-ConnectivityLogEntry {
    <#
        À chaque résultat de test : renvoie la ligne à journaliser (Level vide = rien à écrire) et le nouvel
        état de la coupure { FailingSince, ErrorReported }.
        -Ok            : résultat du test qui vient d'arriver.
        -WasKnown      : un résultat a déjà été reçu (faux au premier test).
        -WasOk         : dernier état connu.
        -FailingSince  : début de la coupure en cours ($null s'il n'y en a pas).
        -ErrorReported : la coupure en cours a déjà été écrite en ERREUR.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][bool]$Ok,
        [bool]$WasKnown,
        [bool]$WasOk,
        [Nullable[datetime]]$FailingSince,
        [bool]$ErrorReported,
        [Parameter(Mandatory)][datetime]$Now,
        [Parameter(Mandatory)][int]$GraceSeconds
    )

    $level = ''
    $message = ''
    if ($Ok) {
        if ($ErrorReported -and $FailingSince) {
            $level = 'OK'
            $message = 'Connexion internet rétablie après {0} s' -f [int][Math]::Round(($Now - [datetime]$FailingSince).TotalSeconds)
        } elseif (-not $WasKnown -or -not $WasOk) {
            $level = 'OK'
            $message = 'Connexion internet validée'
        }
        return [pscustomobject]@{ Level = $level; Message = $message; FailingSince = $null; ErrorReported = $false }
    }

    if (-not $FailingSince) {
        $level = 'INFO'
        $message = 'Connexion internet absente : nouvelle vérification (erreur si elle dure plus de {0} s)' -f $GraceSeconds
        return [pscustomobject]@{ Level = $level; Message = $message; FailingSince = $Now; ErrorReported = $false }
    }

    $elapsed = [int][Math]::Round(($Now - [datetime]$FailingSince).TotalSeconds)
    if (-not $ErrorReported -and $elapsed -ge $GraceSeconds) {
        return [pscustomobject]@{ Level = 'ERREUR'; Message = ('Pas de connexion internet depuis {0} s' -f $elapsed); FailingSince = [datetime]$FailingSince; ErrorReported = $true }
    }
    return [pscustomobject]@{ Level = ''; Message = ''; FailingSince = [datetime]$FailingSince; ErrorReported = $ErrorReported }
}
