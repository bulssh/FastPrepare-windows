<#
    Étape 15 — Antivirus depuis le lien collé par le technicien (section 12, itération 16) :
    Bitdefender (setupdownloader_[…].exe /bdparams /silent, ou .msi /qn) ou ESET
    (PROTECT_Installer_*.exe --silent --accepteula, installateur en ligne --silent --acceptterms).
#>

Register-Step -Id 'install-antivirus' -Section 12 -Title 'Installation de l''antivirus' -Plan {
    param($Selection, $Snapshot, $Context)
    New-LinkInstallerAction -Kind Antivirus -Url $Selection.Agents.AntivirusUrl -Title 'Antivirus'
} -Invoke {
    param($Action, $Context)
    Invoke-LinkInstaller -Installer $Action.Parameters.Installer -Context $Context
}
