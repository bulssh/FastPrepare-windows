<#
    Étape 16 — Lecteurs réseau de l'utilisateur de la session ouverte (section 13, itération 17).
    Mappage persistant écrit dans sa ruche (HKU\<SID>\Network\<lettre>), comme le ferait
    « net use /persistent:yes » dans sa session ; visible à sa prochaine ouverture de session.
    Aucun script ni tâche planifiée n'est laissé sur le poste.
#>

Register-Step -Id 'map-network-drives' -Section 13 -Title 'Lecteurs réseau' -Plan {
    param($Selection, $Snapshot, $Context)
    foreach ($drive in @($Selection.NetworkDrives.Items)) {
        New-StepAction -Label ('Lecteur réseau : {0} — mappage persistant pour la session ouverte (HKU\<SID>\Network\{1})' -f (Format-NetworkDriveSummary -Drive $drive), $drive.Letter) -Parameters @{
            Kind = 'NetworkDrive'; Letter = [string]$drive.Letter; Path = [string]$drive.Path; Label = [string]$drive.Label
        }
    }
} -Invoke {
    param($Action, $Context)
    $p = $Action.Parameters
    $user = Get-InteractiveUser
    if (-not $user) { throw 'aucune session utilisateur ouverte : lecteur non connecté.' }
    if (@(Get-UsedDriveLetter) -contains $p.Letter) { throw ('la lettre {0}: est déjà utilisée par un disque du poste.' -f $p.Letter) }

    $result = Set-PersistentNetworkDrive -UserSid $user.Sid -Letter $p.Letter -Path $p.Path -Label $p.Label -LabelKeyName (Get-NetworkDriveLabelKeyName -Path $p.Path) -Log $Context.Log
    if ($result.AlreadyPresent) {
        Write-RunLog -Log $Context.Log -Message ('Lecteur {0}: déjà connecté à {1} pour {2}' -f $p.Letter, $p.Path, $user.Name)
    } else {
        Write-RunLog -Log $Context.Log -Message ('Lecteur {0}: connecté à {1} pour {2} ; visible à sa prochaine ouverture de session' -f $p.Letter, $p.Path, $user.Name)
    }
}
