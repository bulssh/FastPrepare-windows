<#
    Étape 17 — Imprimantes IP (section 14, itération 17) : pilote .inf du dossier des pilotes
    (pnputil, Add-PrinterDriver), port TCP/IP standard (Add-PrinterPort), imprimante (Add-Printer).
#>

Register-Step -Id 'add-ip-printers' -Section 14 -Title 'Imprimantes IP' -Plan {
    param($Selection, $Snapshot, $Context)
    foreach ($printer in @($Selection.Printers.Items)) {
        $port = Get-IpPrinterPortName -Address $printer.Address
        New-StepAction -Label ('Imprimante IP : {0} — pnputil /add-driver, Add-PrinterDriver, Add-PrinterPort {1}, Add-Printer' -f (Format-IpPrinterSummary -Printer $printer), $port) -Parameters @{
            Kind = 'IpPrinter'; Name = [string]$printer.Name; Address = [string]$printer.Address
            InfPath = [string]$printer.InfPath; DriverName = [string]$printer.DriverName; PortName = $port
        }
    }
} -Invoke {
    param($Action, $Context)
    $p = $Action.Parameters
    $result = Install-IpPrinter -Name $p.Name -Address $p.Address -InfPath $p.InfPath -DriverName $p.DriverName -PortName $p.PortName -Log $Context.Log
    Write-RunLog -Log $Context.Log -Message ("Imprimante '{0}' installée sur {1}" -f $p.Name, $p.PortName)
    return [pscustomobject]@{ RebootRequired = $result.RebootRequired }
}
