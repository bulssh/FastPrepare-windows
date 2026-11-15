<#
    Étape 14 — Agent RMM depuis le lien collé par le technicien (section 12, itération 16) :
    NinjaOne (.msi, msiexec /i /qn /norestart) ou Datto RMM (.exe lancé tel quel).
#>

Register-Step -Id 'install-rmm-agent' -Section 12 -Title 'Installation de l''agent RMM' -Plan {
    param($Selection, $Snapshot, $Context)
    New-LinkInstallerAction -Kind Rmm -Url $Selection.Agents.RmmUrl -Title 'Agent RMM'
} -Invoke {
    param($Action, $Context)
    Invoke-LinkInstaller -Installer $Action.Parameters.Installer -Context $Context
}
