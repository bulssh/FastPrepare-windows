BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Infrastructure
}

Describe 'Save-RemoteFile' {
    BeforeEach {
        # Aucun accès réseau : le transfert BITS est simulé par l'écriture d'un contenu connu.
        Mock -ModuleName FastPrepare.Infrastructure Start-BitsTransfer { Set-Content -LiteralPath $Destination -Value 'contenu' -NoNewline -Encoding Ascii }
        $expected = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::ASCII.GetBytes('contenu'))) -Algorithm SHA256).Hash
    }

    It 'refuse un lien qui n''est pas en https' {
        { Save-RemoteFile -Url 'http://exemple.test/a.exe' -Destination (Join-Path $TestDrive 'a.exe') } | Should -Throw '*https*'
    }
    It 'empreinte correcte : fichier final en place, aucun fichier partiel' {
        $target = Join-Path $TestDrive 'ok\a.exe'
        Save-RemoteFile -Url 'https://exemple.test/a.exe' -Destination $target -Sha256 $expected.ToLowerInvariant() | Should -Be $target
        $target | Should -Exist
        "$target.partiel" | Should -Not -Exist
    }
    It 'empreinte fausse : erreur et fichier supprimé' {
        $target = Join-Path $TestDrive 'ko\a.exe'
        { Save-RemoteFile -Url 'https://exemple.test/a.exe' -Destination $target -Sha256 ('0' * 64) } | Should -Throw '*Empreinte SHA-256 inattendue*'
        $target | Should -Not -Exist
        "$target.partiel" | Should -Not -Exist
    }
}

Describe 'Expand-DownloadedArchive' {
    BeforeAll {
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
        function New-TestZip([string]$Path, [string[]]$Entries) {
            $zip = [System.IO.Compression.ZipFile]::Open($Path, 'Create')
            try {
                foreach ($entry in $Entries) {
                    $writer = New-Object System.IO.StreamWriter(($zip.CreateEntry($entry)).Open())
                    $writer.Write('x'); $writer.Dispose()
                }
            } finally { $zip.Dispose() }
        }
    }
    It 'extrait dans un dossier du nom de l''archive et renvoie l''exécutable demandé' {
        $zip = Join-Path $TestDrive 'paquet.zip'
        New-TestZip $zip @('Paquet/VantageInstaller.exe', 'Paquet/SystemUpdate/autre.exe')
        $path = Expand-DownloadedArchive -Path $zip -FileName 'VantageInstaller.exe'
        $path | Should -Be (Join-Path $TestDrive 'paquet\Paquet\VantageInstaller.exe')
        $path | Should -Exist
    }
    It 'extraction précédente remplacée, pas mélangée' {
        $zip = Join-Path $TestDrive 'deux.zip'
        New-TestZip $zip @('a/outil.exe')
        [void](Expand-DownloadedArchive -Path $zip -FileName 'outil.exe')
        Set-Content -LiteralPath (Join-Path $TestDrive 'deux\reste.txt') -Value 'ancien'
        [void](Expand-DownloadedArchive -Path $zip -FileName 'outil.exe')
        Join-Path $TestDrive 'deux\reste.txt' | Should -Not -Exist
    }
    It 'exécutable absent ou en double : erreur explicite' {
        $zip = Join-Path $TestDrive 'double.zip'
        New-TestZip $zip @('a/outil.exe', 'b/outil.exe')
        { Expand-DownloadedArchive -Path $zip -FileName 'outil.exe' } | Should -Throw '*2 fichier(s)*'
        { Expand-DownloadedArchive -Path $zip -FileName 'absent.exe' } | Should -Throw '*0 fichier(s)*'
    }
    It 'nom avec un dossier : refusé' {
        { Expand-DownloadedArchive -Path (Join-Path $TestDrive 'x.zip') -FileName '..\outil.exe' } | Should -Throw '*refusé*'
    }
}

Describe 'Assert-TrustedExecutable' {
    BeforeAll { $notepad = Join-Path ([Environment]::GetFolderPath('System')) 'notepad.exe' }

    It 'exécutable Windows signé par Microsoft : accepté' {
        { Assert-TrustedExecutable -Path $notepad -ExpectedSigner 'Microsoft' } | Should -Not -Throw
    }
    It 'éditeur différent de celui attendu : refusé' {
        { Assert-TrustedExecutable -Path $notepad -ExpectedSigner 'Lenovo' } | Should -Throw '*non lancé*'
    }
    It 'fichier non signé : refusé' {
        $unsigned = Join-Path $TestDrive 'nonsigne.ps1'
        Set-Content -LiteralPath $unsigned -Value 'Write-Output 1'
        { Assert-TrustedExecutable -Path $unsigned -ExpectedSigner '' } | Should -Throw '*non valide*'
    }
}
