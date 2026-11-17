<#
    Règle de journalisation de la connexion internet (DEC28) : une coupure courte n'est pas une erreur,
    une coupure qui dépasse le délai de grâce l'est.
#>
BeforeAll {
    . (Join-Path $PSScriptRoot '..\TestHelpers.ps1')
    Import-FastPrepareModule Core
    $script:t0 = [datetime]'2026-11-17T10:00:00'
}

Describe 'Get-ConnectivityLogEntry' {
    It 'premier test réussi : OK « validée »' {
        $e = Get-ConnectivityLogEntry -Ok $true -WasKnown $false -Now $t0 -GraceSeconds 60
        $e.Level | Should -Be 'OK'
        $e.Message | Should -Be 'Connexion internet validée'
        $e.FailingSince | Should -BeNullOrEmpty
    }

    It 'connexion toujours présente : rien à écrire' {
        (Get-ConnectivityLogEntry -Ok $true -WasKnown $true -WasOk $true -Now $t0 -GraceSeconds 60).Level | Should -BeNullOrEmpty
    }

    It 'premier test en échec au démarrage : INFO, pas d''ERREUR' {
        $e = Get-ConnectivityLogEntry -Ok $false -WasKnown $false -Now $t0 -GraceSeconds 60
        $e.Level | Should -Be 'INFO'
        $e.FailingSince | Should -Be $t0
        $e.ErrorReported | Should -BeFalse
    }

    It 'coupure qui commence : INFO avec le délai' {
        $e = Get-ConnectivityLogEntry -Ok $false -WasKnown $true -WasOk $true -Now $t0 -GraceSeconds 60
        $e.Level | Should -Be 'INFO'
        $e.Message | Should -Match '60 s'
    }

    It 'coupure encore dans le délai : rien à écrire, début conservé' {
        $e = Get-ConnectivityLogEntry -Ok $false -WasKnown $true -WasOk $false -FailingSince $t0 -Now $t0.AddSeconds(25) -GraceSeconds 60
        $e.Level | Should -BeNullOrEmpty
        $e.FailingSince | Should -Be $t0
    }

    It 'retour dans le délai (reprise d''une VM) : OK « validée », aucune ERREUR' {
        $e = Get-ConnectivityLogEntry -Ok $true -WasKnown $true -WasOk $false -FailingSince $t0 -Now $t0.AddSeconds(25) -GraceSeconds 60
        $e.Level | Should -Be 'OK'
        $e.Message | Should -Be 'Connexion internet validée'
        $e.FailingSince | Should -BeNullOrEmpty
    }

    It 'coupure au-delà du délai : ERREUR une seule fois' {
        $e = Get-ConnectivityLogEntry -Ok $false -WasKnown $true -WasOk $false -FailingSince $t0 -Now $t0.AddSeconds(61) -GraceSeconds 60
        $e.Level | Should -Be 'ERREUR'
        $e.Message | Should -Be 'Pas de connexion internet depuis 61 s'
        $e.ErrorReported | Should -BeTrue
        $again = Get-ConnectivityLogEntry -Ok $false -WasKnown $true -WasOk $false -FailingSince $t0 -ErrorReported $true -Now $t0.AddSeconds(90) -GraceSeconds 60
        $again.Level | Should -BeNullOrEmpty
        $again.ErrorReported | Should -BeTrue
    }

    It 'retour après une ERREUR : OK « rétablie après N s »' {
        $e = Get-ConnectivityLogEntry -Ok $true -WasKnown $true -WasOk $false -FailingSince $t0 -ErrorReported $true -Now $t0.AddSeconds(95) -GraceSeconds 60
        $e.Level | Should -Be 'OK'
        $e.Message | Should -Be 'Connexion internet rétablie après 95 s'
        $e.ErrorReported | Should -BeFalse
    }
}
