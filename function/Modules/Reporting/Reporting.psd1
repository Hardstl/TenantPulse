@{
    RootModule        = 'Reporting.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '0f2b7c59-7a13-4a58-9f2d-8c3d5c6ab321'
    Author            = 'TenantPulse'
    CompanyName       = 'TenantPulse'
    Copyright         = '(c) TenantPulse. All rights reserved.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
        'Invoke-Export',
        'Get-ConfiguredExportNamesByPrefix',
        'Get-RoleAssignmentsExport',
        'Get-AccountMatchesExport',
        'Get-GroupMembersExport',
        'Get-AuGroupMembersExport',
        'Get-SubscriptionsExport',
        'Get-AppRegistrationsExport',
        'Get-GraphPermissionsExport',
        'Get-LicenseExport',
        'Get-InactiveEntraAdminAccountsExport'
    )
}

