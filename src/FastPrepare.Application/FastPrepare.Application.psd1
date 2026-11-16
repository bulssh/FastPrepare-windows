@{
    RootModule        = 'FastPrepare.Application.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '3a45e8aa-be4c-4ea8-ac9f-a37029f88096'
    Author            = 'FastPrepare'
    Description       = 'Cas d''usage : contexte d''exécution, relevé du poste, simulation.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'New-AppContext',
        'Get-BackgroundModulePath',
        'Get-WingetSourceRepair',
        'Get-MachineSnapshot',
        'Start-MachineSnapshot',
        'Export-MachineInventory',
        'Get-StepOrder',
        'Get-RegisteredStep',
        'New-ExecutionPlan',
        'Format-ExecutionPlanSummary',
        'Invoke-ExecutionPlan',
        'Start-ExecutionPlan',
        'Write-FinalReport',
        'Get-ConfigPathVariable',
        'Get-PrefetchCachePath',
        'Get-PrefetchedItem',
        'Test-PrefetchUseful',
        'Invoke-Prefetch',
        'Start-Prefetch',
        'Resolve-UtilityDotNetRequirement',
        'Get-CompanyProfileList',
        'Import-CompanyProfile',
        'Export-CompanyProfile',
        'Test-DomainJoinSetting',
        'Start-DomainJoinTest',
        'Get-PrinterDriverFolder',
        'Get-PrinterDriverCatalog',
        'Get-PrinterDriverModel',
        'Set-SoftwareCatalogEntry',
        'Remove-SoftwareCatalogEntry',
        'Test-SoftwareCatalogEntry',
        'Start-SoftwareCatalogTest',
        'Get-DiskUsageDrive',
        'New-DiskUsageProgress',
        'Get-DiskUsage',
        'Get-DiskUsageChild',
        'Start-DiskUsageScan',
        'Get-DiskUsageNodePath',
        'Get-DiskUsageNodeLabel',
        'New-DiskUsageTreemap',
        'Find-DiskUsageTreemapRect',
        'Open-DiskUsageLocation'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
