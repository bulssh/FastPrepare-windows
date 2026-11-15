<#
    Vérifications statiques de l'interface (sans charger WPF, donc exécutables partout) :
    XAML bien formé, ressources de thème existantes, contrôles nommés utilisés par le code
    présents dans le XAML, sections rangées dans une page du parcours.
#>

BeforeDiscovery {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    $uiRoot = Join-Path (Get-RepoRoot) 'src\FastPrepare.UI'
    $xamlFiles = @(Get-ChildItem -Path (Join-Path $uiRoot 'Xaml') -Filter '*.xaml' -Recurse | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
    $sectionFiles = @(Get-ChildItem -Path (Join-Path $uiRoot 'Sections') -Filter '*.ps1' | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
    $codeFiles = @(Get-ChildItem -Path $uiRoot -Filter '*.ps1' -Recurse | ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
    $script:UiRoot = Join-Path (Get-RepoRoot) 'src\FastPrepare.UI'
    $script:XamlRoot = Join-Path $script:UiRoot 'Xaml'

    function Get-XamlName {
        <# Noms (attribut Name) déclarés dans un fichier XAML. #>
        param([string]$Path)
        $document = New-Object System.Xml.XmlDocument
        $document.Load($Path)
        return @($document.SelectNodes('//*[@Name]') | ForEach-Object { $_.GetAttribute('Name') })
    }

    function Get-ThemeKey {
        $text = Get-Content -LiteralPath (Join-Path $script:XamlRoot 'Theme.xaml') -Raw -Encoding UTF8
        return @([regex]::Matches($text, 'x:Key="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    }

    function Get-SectionRegistration {
        <# Lecture de l'appel Register-UiSection d'un fichier de section. #>
        param([string]$Path)
        $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $line = [regex]::Match($text, 'Register-UiSection[^\r\n]*').Value
        $read = { param($name) $m = [regex]::Match($line, "-$name\s+'?([^'\s]+)'?"); if ($m.Success) { $m.Groups[1].Value } else { $null } }
        return [pscustomobject]@{
            Text     = $text
            Id       = & $read 'Id'
            Page     = & $read 'Page'
            Column   = & $read 'Column'
            XamlFile = & $read 'XamlFile'
        }
    }
}

Describe 'Fichiers XAML' {
    It '<Name> : XML bien formé' -ForEach $xamlFiles {
        $document = New-Object System.Xml.XmlDocument
        { $document.Load($Path) } | Should -Not -Throw
    }

    It '<Name> : chaque nom de contrôle est unique' -ForEach $xamlFiles {
        $names = @(Get-XamlName -Path $Path)
        @($names | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }) | Should -BeNullOrEmpty
    }

    It '<Name> : chaque ressource utilisée existe dans le thème' -ForEach $xamlFiles {
        $keys = @(Get-ThemeKey)
        $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $used = @([regex]::Matches($text, '\{StaticResource ([^}]+)\}') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        @($used | Where-Object { $keys -notcontains $_ }) | Should -BeNullOrEmpty
    }
}

Describe 'Code de l''interface' {
    It '<Name> : chaque ressource demandée par Get-ThemeResource existe dans le thème' -ForEach $codeFiles {
        $keys = @(Get-ThemeKey)
        $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $used = @([regex]::Matches($text, "Get-ThemeResource -Key '([^']+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        @($used | Where-Object { $keys -notcontains $_ }) | Should -BeNullOrEmpty
    }

    It 'MainWindow.ps1 : chaque contrôle de la coquille utilisé existe dans MainWindow.xaml' {
        $names = @(Get-XamlName -Path (Join-Path $script:XamlRoot 'MainWindow.xaml'))
        $text = Get-Content -LiteralPath (Join-Path $script:UiRoot 'MainWindow.ps1') -Raw -Encoding UTF8
        $used = @([regex]::Matches($text, '(?:\$shell|\$script:Shell\.Controls)\.([A-Z]\w+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $used.Count | Should -BeGreaterThan 10
        @($used | Where-Object { $names -notcontains $_ }) | Should -BeNullOrEmpty
    }

    It 'la coquille porte un seul bouton Lancer, dans le récapitulatif' {
        $document = New-Object System.Xml.XmlDocument
        $document.Load((Join-Path $script:XamlRoot 'MainWindow.xaml'))
        $go = @($document.SelectNodes('//*[@Name="BtnGo"]'))
        $go.Count | Should -Be 1
        $ancestors = @($go[0].SelectNodes('ancestor::*[@Name]') | ForEach-Object { $_.GetAttribute('Name') })
        $ancestors | Should -Contain 'PageRecap'
    }
}

Describe 'Sections' {
    It '<Name> : rangée dans une page de saisie du parcours, fragment présent' -ForEach $sectionFiles {
        $registration = Get-SectionRegistration -Path $Path
        $registration.Id | Should -Not -BeNullOrEmpty
        if ($registration.Column -eq 'Header') {
            $registration.Page | Should -BeNullOrEmpty
            return
        }
        $registration.Column | Should -BeIn @('Left', 'Right')
        $pages = @(Get-WizardPage | Where-Object { $_.Kind -ne 'Review' } | ForEach-Object { $_.Id })
        $pages | Should -Contain $registration.Page
        $registration.XamlFile | Should -Not -BeNullOrEmpty
        Join-Path $script:XamlRoot $registration.XamlFile.Replace('\', [System.IO.Path]::DirectorySeparatorChar) | Should -Exist
    }

    It '<Name> : chaque contrôle utilisé existe dans son fragment' -ForEach $sectionFiles {
        $registration = Get-SectionRegistration -Path $Path
        $xaml = if ($registration.Column -eq 'Header') { Join-Path $script:XamlRoot 'MainWindow.xaml' }
        else { Join-Path $script:XamlRoot $registration.XamlFile.Replace('\', [System.IO.Path]::DirectorySeparatorChar) }
        $names = @(Get-XamlName -Path $xaml)
        $used = @([regex]::Matches($registration.Text, '(?:\$c|\$controls|(?<!Windows)\.Controls)\.([A-Z][a-z]+[A-Z]\w*)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        @($used | Where-Object { $names -notcontains $_ }) | Should -BeNullOrEmpty
    }

    It 'chaque page de saisie accueille au moins une section' {
        $used = @(Get-ChildItem -Path (Join-Path $script:UiRoot 'Sections') -Filter '*.ps1' | ForEach-Object { (Get-SectionRegistration -Path $_.FullName).Page } | Where-Object { $_ })
        foreach ($page in (Get-WizardPage | Where-Object { $_.Kind -ne 'Review' })) {
            $used | Should -Contain $page.Id
        }
    }
}
