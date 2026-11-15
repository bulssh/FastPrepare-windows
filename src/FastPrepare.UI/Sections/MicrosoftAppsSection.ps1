<#
    Section 3 — Désinstallation des programmes Microsoft.
    « Dossier OneDrive » est grisé tant que OneDrive n'est pas coché ; nombre de fichiers affiché.
#>

Register-UiSection -Id 'microsoft-apps' -Number 3 -Page 'nettoyage' -Column Right -XamlFile 'Sections\MicrosoftApps.xaml' -Initialize {
    param($Section, $Context)
    $Section.Controls.ChkOneDrive.Add_Click({
            Invoke-UiAction -Name 'OneDrive' -Action {
                $controls = (Get-UiSection -Id 'microsoft-apps').Controls
                $controls.ChkOneDriveFolder.IsEnabled = [bool]$controls.ChkOneDrive.IsChecked
                if (-not $controls.ChkOneDrive.IsChecked) { $controls.ChkOneDriveFolder.IsChecked = $false }
            }
        })
} -OnSnapshot {
    param($Section, $Snapshot, $Context)
    $Section.Controls.TxtOneDriveCount.Text = if ($Snapshot.OneDrive.Exists) { '{0} fichier(s) trouvé(s)' -f $Snapshot.OneDrive.FileCount } else { 'dossier absent' }
} -GetSelection {
    param($Section, $Selection)
    $c = $Section.Controls
    $ms = $Selection.MicrosoftApps
    $ms.OfficeClickToRun = [bool]$c.ChkOfficeC2R.IsChecked
    $ms.OfficeMsi = [bool]$c.ChkOfficeMsi.IsChecked
    $ms.OutlookClassic = [bool]$c.ChkOutlookClassic.IsChecked
    $ms.OutlookNew = [bool]$c.ChkOutlookNew.IsChecked
    $ms.OneNote = [bool]$c.ChkOneNote.IsChecked
    $ms.Teams = [bool]$c.ChkTeams.IsChecked
    $ms.OneDrive = [bool]$c.ChkOneDrive.IsChecked
    $ms.OneDriveFolder = [bool]$c.ChkOneDrive.IsChecked -and [bool]$c.ChkOneDriveFolder.IsChecked
} -ExportProfile {
    param($Section, $CompanyProfile)
    $c = $Section.Controls
    $ms = $CompanyProfile.MicrosoftApps
    $ms.OfficeClickToRun = [bool]$c.ChkOfficeC2R.IsChecked
    $ms.OfficeMsi = [bool]$c.ChkOfficeMsi.IsChecked
    $ms.OutlookClassic = [bool]$c.ChkOutlookClassic.IsChecked
    $ms.OutlookNew = [bool]$c.ChkOutlookNew.IsChecked
    $ms.OneNote = [bool]$c.ChkOneNote.IsChecked
    $ms.Teams = [bool]$c.ChkTeams.IsChecked
    $ms.OneDrive = [bool]$c.ChkOneDrive.IsChecked
    $ms.OneDriveFolder = [bool]$c.ChkOneDrive.IsChecked -and [bool]$c.ChkOneDriveFolder.IsChecked
} -ImportProfile {
    param($Section, $CompanyProfile)
    $c = $Section.Controls
    $ms = $CompanyProfile.MicrosoftApps
    $c.ChkOfficeC2R.IsChecked = [bool]$ms.OfficeClickToRun
    $c.ChkOfficeMsi.IsChecked = [bool]$ms.OfficeMsi
    $c.ChkOutlookClassic.IsChecked = [bool]$ms.OutlookClassic
    $c.ChkOutlookNew.IsChecked = [bool]$ms.OutlookNew
    $c.ChkOneNote.IsChecked = [bool]$ms.OneNote
    $c.ChkTeams.IsChecked = [bool]$ms.Teams
    $c.ChkOneDrive.IsChecked = [bool]$ms.OneDrive
    $c.ChkOneDriveFolder.IsEnabled = [bool]$ms.OneDrive
    $c.ChkOneDriveFolder.IsChecked = [bool]$ms.OneDrive -and [bool]$ms.OneDriveFolder
}
