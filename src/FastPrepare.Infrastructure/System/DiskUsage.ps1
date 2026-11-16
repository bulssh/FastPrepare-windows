<#
    Analyse de disque : lecture seule du système de fichiers (page « Analyse de disque »).
    Rien n'est modifié sur le poste, quel que soit le mode de l'outil.
#>

function Get-FixedDrive {
    <# Disques fixes prêts : { Name ('C:\'), Label, TotalBytes, FreeBytes }. #>
    [CmdletBinding()]
    param()
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -ne [System.IO.DriveType]::Fixed -or -not $drive.IsReady) { continue }
        [pscustomobject]@{
            Name       = $drive.Name
            Label      = [string]$drive.VolumeLabel
            TotalBytes = [long]$drive.TotalSize
            FreeBytes  = [long]$drive.TotalFreeSpace
        }
    }
}

function Read-DiskUsage {
    <#
        Parcourt -Path et renvoie l'arbre des tailles, en tableaux parallèles indexés par nœud
        (le nœud 0 est -Path) :
          Name, Parent, Kind (0 dossier, 1 fichier, 2 groupe de fichiers d'une même extension
          dans un dossier), Size (octets, cumulés pour un dossier), Count (fichiers), Extension
          (indice dans ExtensionName, -1 pour un dossier), ChildStart et ChildCount (les enfants
          d'un dossier sont des nœuds consécutifs), Largest (son plus gros enfant, -1 s'il est vide).
        Un fichier d'au moins -LargeFileBytes a son propre nœud ; les autres sont regroupés par
        extension dans leur dossier, ce qui borne la mémoire sur un disque de plusieurs millions
        de fichiers. Les jonctions et liens symboliques ne sont pas suivis (pas de double compte).
        Un dossier illisible est compté dans Inaccessible et n'arrête pas le parcours.
        -Progress : table synchronisée { Files, Bytes, Path, Cancel } mise à jour à chaque dossier ;
        Cancel = $true interrompt le parcours (résultat partiel, Cancelled = $true).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [long]$LargeFileBytes = 1MB,
        $Progress
    )
    $rootInfo = New-Object System.IO.DirectoryInfo $Path
    if (-not $rootInfo.Exists) { throw "Dossier introuvable : $Path" }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()

    $names = New-Object 'System.Collections.Generic.List[string]'
    $parents = New-Object 'System.Collections.Generic.List[int]'
    $kinds = New-Object 'System.Collections.Generic.List[byte]'
    $sizes = New-Object 'System.Collections.Generic.List[long]'
    $counts = New-Object 'System.Collections.Generic.List[int]'
    $extensions = New-Object 'System.Collections.Generic.List[int]'
    $childStarts = New-Object 'System.Collections.Generic.List[int]'
    $childCounts = New-Object 'System.Collections.Generic.List[int]'

    $extensionIndex = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)
    $extensionNames = New-Object 'System.Collections.Generic.List[string]'
    $extensionBytes = New-Object 'System.Collections.Generic.List[long]'
    $extensionFiles = New-Object 'System.Collections.Generic.List[int]'

    $directoryFlag = [int][System.IO.FileAttributes]::Directory
    $reparseFlag = [int][System.IO.FileAttributes]::ReparsePoint
    $totalFiles = 0
    $totalBytes = [long]0
    $directories = 0
    $inaccessible = 0
    $cancelled = $false

    $names.Add($rootInfo.FullName); $parents.Add(-1); $kinds.Add(0); $sizes.Add(0); $counts.Add(0); $extensions.Add(-1); $childStarts.Add(0); $childCounts.Add(0)
    $pendingIndex = New-Object 'System.Collections.Generic.Stack[int]'
    $pendingInfo = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pendingIndex.Push(0)
    $pendingInfo.Push($rootInfo)
    $groupBytes = New-Object 'System.Collections.Generic.Dictionary[string,long]' ([System.StringComparer]::Ordinal)
    $groupFiles = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([System.StringComparer]::Ordinal)

    while ($pendingIndex.Count -gt 0) {
        if ($Progress -and $Progress.Cancel) { $cancelled = $true; break }
        $index = $pendingIndex.Pop()
        $info = $pendingInfo.Pop()
        $directories++
        # Tout ce qui est ajouté pendant le traitement de ce dossier est un de ses enfants.
        $firstChild = $names.Count
        $groupBytes.Clear()
        $groupFiles.Clear()
        try {
            $seen = 0
            foreach ($entry in $info.EnumerateFileSystemInfos()) {
                # Arrêt demandé : vérifié aussi à l'intérieur d'un dossier (certains ont des dizaines de milliers d'entrées).
                $seen++
                if (($seen -band 511) -eq 0 -and $Progress -and $Progress.Cancel) { $cancelled = $true; break }
                $attributes = [int]$entry.Attributes
                if (($attributes -band $reparseFlag) -ne 0) { continue }
                if (($attributes -band $directoryFlag) -ne 0) {
                    $names.Add($entry.Name); $parents.Add($index); $kinds.Add(0); $sizes.Add(0); $counts.Add(0); $extensions.Add(-1); $childStarts.Add(0); $childCounts.Add(0)
                    $pendingIndex.Push($names.Count - 1)
                    $pendingInfo.Push($entry)
                    continue
                }
                $length = [long]$entry.Length
                $extension = $entry.Extension.ToLowerInvariant()
                $totalFiles++
                $totalBytes += $length
                if ($length -ge $LargeFileBytes) {
                    $slot = 0
                    if (-not $extensionIndex.TryGetValue($extension, [ref]$slot)) {
                        $slot = $extensionNames.Count
                        $extensionIndex[$extension] = $slot
                        $extensionNames.Add($extension); $extensionBytes.Add(0); $extensionFiles.Add(0)
                    }
                    $extensionBytes[$slot] += $length
                    $extensionFiles[$slot] += 1
                    $names.Add($entry.Name); $parents.Add($index); $kinds.Add(1); $sizes.Add($length); $counts.Add(1); $extensions.Add($slot); $childStarts.Add(0); $childCounts.Add(0)
                } elseif ($groupBytes.ContainsKey($extension)) {
                    $groupBytes[$extension] += $length
                    $groupFiles[$extension] += 1
                } else {
                    $groupBytes[$extension] = $length
                    $groupFiles[$extension] = 1
                }
            }
        } catch {
            # Accès refusé, chemin trop long, dossier supprimé pendant le parcours : on continue.
            $inaccessible++
        }
        foreach ($extension in $groupBytes.Keys) {
            $slot = 0
            if (-not $extensionIndex.TryGetValue($extension, [ref]$slot)) {
                $slot = $extensionNames.Count
                $extensionIndex[$extension] = $slot
                $extensionNames.Add($extension); $extensionBytes.Add(0); $extensionFiles.Add(0)
            }
            $extensionBytes[$slot] += $groupBytes[$extension]
            $extensionFiles[$slot] += $groupFiles[$extension]
            $names.Add($extension); $parents.Add($index); $kinds.Add(2); $sizes.Add($groupBytes[$extension]); $counts.Add($groupFiles[$extension]); $extensions.Add($slot); $childStarts.Add(0); $childCounts.Add(0)
        }
        $childStarts[$index] = $firstChild
        $childCounts[$index] = $names.Count - $firstChild
        if ($cancelled) { break }
        # Avancement publié tous les 32 dossiers : la table est synchronisée, chaque écriture coûte.
        if ($Progress -and ($directories -band 31) -eq 0) {
            $Progress.Files = $totalFiles
            $Progress.Bytes = $totalBytes
            $Progress.Path = $info.FullName
        }
    }

    if ($Progress) {
        $Progress.Files = $totalFiles
        $Progress.Bytes = $totalBytes
        $Progress.Path = $rootInfo.FullName
    }

    # Cumul vers les dossiers : un enfant a toujours un indice supérieur à celui de son parent.
    # Au passage, le plus gros enfant de chaque dossier (couleur d'un dossier dessiné d'un bloc).
    $largest = New-Object 'int[]' $names.Count
    for ($node = 0; $node -lt $largest.Length; $node++) { $largest[$node] = -1 }
    for ($node = $names.Count - 1; $node -gt 0; $node--) {
        $parent = $parents[$node]
        $size = $sizes[$node]
        $sizes[$parent] += $size
        $counts[$parent] += $counts[$node]
        $best = $largest[$parent]
        if ($best -lt 0 -or $size -gt $sizes[$best]) { $largest[$parent] = $node }
    }

    return [pscustomobject]@{
        PSTypeName     = 'FastPrepare.DiskUsage'
        Root           = $rootInfo.FullName
        Name           = $names
        Parent         = $parents
        Kind           = $kinds
        Size           = $sizes
        Count          = $counts
        Extension      = $extensions
        ChildStart     = $childStarts
        ChildCount     = $childCounts
        Largest        = $largest
        ExtensionName  = $extensionNames
        ExtensionBytes = $extensionBytes
        ExtensionFiles = $extensionFiles
        Files          = $totalFiles
        Bytes          = $totalBytes
        Directories    = $directories
        Inaccessible   = $inaccessible
        Cancelled      = $cancelled
        Seconds        = $watch.Elapsed.TotalSeconds
    }
}

function Show-PathInExplorer {
    <# Ouvre l'Explorateur de fichiers sur -Path (dossier ouvert, fichier sélectionné). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, $Log)
    if ($Path -match '"') { throw "Chemin invalide : $Path" }
    $explorer = Join-Path $env:windir 'explorer.exe'
    $isFolder = Test-Path -LiteralPath $Path -PathType Container
    if (-not $isFolder -and -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Introuvable : $Path" }
    $arguments = if ($isFolder) { '"{0}"' -f $Path } else { '/select,"{0}"' -f $Path }
    # L'Explorateur rend la main aussitôt, avec le code 1 même quand tout va bien.
    [void](Invoke-ExternalProcess -FilePath $explorer -ArgumentList $arguments -SuccessExitCode @(0, 1) -TimeoutMinutes 1 -Interactive -Log $Log)
}
