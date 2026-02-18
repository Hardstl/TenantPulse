param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$FunctionManagedIdentityObjectId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$graphResourceAppId = '00000003-0000-0000-c000-000000000000'

# Fixed set of Microsoft Graph application permissions required by this solution.
$requiredPermissions = @(
    'AuditLog.Read.All',
    'Directory.Read.All',
    'LicenseAssignment.Read.All',
    'RoleAssignmentSchedule.Read.Directory',
    'RoleEligibilitySchedule.Read.Directory',
    'RoleManagement.Read.Directory'
)

$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Applications'
)
Write-Host "[GraphPermissions] Validating required Microsoft Graph PowerShell modules"
$missingModules = @(
    $requiredModules |
        Where-Object { -not (Get-Module -ListAvailable -Name $_) }
)
if (@($missingModules).Count -gt 0) {
    throw ("Missing required PowerShell module(s): {0}. Install them first, for example: " +
        "Install-Module Microsoft.Graph -Scope CurrentUser") -f ($missingModules -join ', ')
}

Write-Host "[GraphPermissions] Importing Microsoft Graph modules"
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Applications -ErrorAction Stop

Write-Host ("[GraphPermissions] Connecting to Microsoft Graph for tenant '{0}'" -f $TenantId)
Connect-MgGraph -TenantId $TenantId -NoWelcome -ErrorAction Stop | Out-Null

Write-Host "[GraphPermissions] Resolving Microsoft Graph service principal"
$graphSp = @(Get-MgServicePrincipal -Filter "appId eq '$graphResourceAppId'" -All -ErrorAction Stop)
if (@($graphSp).Count -ne 1) {
    throw "Expected one Graph service principal for appId '$graphResourceAppId', found $(@($graphSp).Count)."
}
$graphSp = $graphSp[0]

$appRoleByValue = @{}
foreach ($role in @($graphSp.AppRoles)) {
    if ($null -eq $role) { continue }
    if (-not ($role.AllowedMemberTypes -contains 'Application')) { continue }
    if ([string]::IsNullOrWhiteSpace($role.Value)) { continue }
    $appRoleByValue[$role.Value] = $role
}

$unknownPermissions = @($requiredPermissions | Where-Object { -not $appRoleByValue.ContainsKey($_) })
if (@($unknownPermissions).Count -gt 0) {
    throw "Unable to resolve Graph app roles for permissions: $($unknownPermissions -join ', ')"
}

Write-Host ("[GraphPermissions] Resolving managed identity service principal '{0}'" -f $FunctionManagedIdentityObjectId)
$principal = Get-MgServicePrincipal -ServicePrincipalId $FunctionManagedIdentityObjectId -ErrorAction Stop
$assignments = @(
    Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $principal.Id -All -ErrorAction Stop |
        Where-Object { $_.ResourceId -eq $graphSp.Id }
)

$assignedPermissions = @{}
foreach ($assignment in $assignments) {
    if ($null -eq $assignment.AppRoleId) { continue }
    $assignedRole = @($graphSp.AppRoles | Where-Object { $_.Id -eq $assignment.AppRoleId }) | Select-Object -First 1
    if ($null -ne $assignedRole -and -not [string]::IsNullOrWhiteSpace($assignedRole.Value)) {
        $assignedPermissions[$assignedRole.Value] = $true
    }
}

$permissionsToAssign = @(
    $requiredPermissions |
        Where-Object { -not $assignedPermissions.ContainsKey($_) } |
        Sort-Object -Unique
)
Write-Host ("[GraphPermissions] Permissions already assigned: {0}; pending assignment: {1}" -f @($requiredPermissions | Where-Object { $assignedPermissions.ContainsKey($_) }).Count, $permissionsToAssign.Count)

$created = New-Object System.Collections.Generic.List[string]
foreach ($permission in $permissionsToAssign) {
    $roleId = $appRoleByValue[$permission].Id.ToString()
    Write-Host ("[GraphPermissions] Assigning '{0}' to '{1}'" -f $permission, $principal.DisplayName)

    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $principal.Id `
        -BodyParameter @{
            principalId = $principal.Id
            resourceId = $graphSp.Id
            appRoleId = $roleId
        } `
        -ErrorAction Stop | Out-Null

    $created.Add($permission) | Out-Null
    Write-Host ("[GraphPermissions] Assigned '{0}' to FunctionManagedIdentity ({1})" -f $permission, $principal.DisplayName)
}

$summary = [PSCustomObject]@{
    PrincipalName        = $principal.DisplayName
    PrincipalObjectId    = $principal.Id
    RequiredPermissions  = ($requiredPermissions | Sort-Object -Unique) -join ','
    AlreadyAssignedCount = @($requiredPermissions | Where-Object { $assignedPermissions.ContainsKey($_) }).Count
    CreatedCount         = $created.Count
}

Write-Host ("[GraphPermissions] Permission configuration complete. Created: {0}" -f $created.Count)
$summary
