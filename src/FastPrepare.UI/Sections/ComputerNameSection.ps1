<#
    Section 1 — Rappel : renommage du poste.
    L'outil ne renomme pas le poste (DEC22) : la section affiche le nom actuel et signale un nom
    attribué automatiquement par Windows (FastPrepare.Core, Test-DefaultComputerName). Elle ne
    contribue pas à la sélection et ne bloque jamais Lancer : c'est un rappel, pas une contrainte.
#>

Register-UiSection -Id 'computer-name' -Number 1 -Page 'poste' -Column Left -XamlFile 'Sections\ComputerName.xaml' -OnSnapshot {
    param($Section, $Snapshot, $Context)
    $c = $Section.Controls
    $name = [string]$Snapshot.Identity.HostName
    $c.TxtComputerName.Text = $name
    if (Test-DefaultComputerName -Name $name) {
        $c.BdDefaultName.Visibility = 'Visible'
        $c.TxtComputerNameHint.Text = "Le poste porte encore le nom donné par Windows. Le renommer à la main (Paramètres › Système › Informations système › Renommer ce PC), redémarrer, puis relancer l'outil."
        $c.TxtComputerNameHint.Foreground = Get-ThemeResource -Key 'WarningBrush'
    } else {
        $c.BdDefaultName.Visibility = 'Collapsed'
        $c.TxtComputerNameHint.Text = "Le renommage se fait à la main, avant l'outil, suivi d'un redémarrage. L'outil ne renomme pas le poste."
        $c.TxtComputerNameHint.Foreground = Get-ThemeResource -Key 'TextSecondaryBrush'
    }
}
