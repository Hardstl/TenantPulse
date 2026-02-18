param location string = resourceGroup().location

@minLength(1)
param functionAppName string

@maxLength(24)
@minLength(3)
param storageAccountName string

@maxLength(24)
@minLength(3)
param exportStorageAccountName string

param logAnalyticsName string = '${functionAppName}-log'
param appInsightsName string = '${functionAppName}-appi'
param appServicePlanName string = '${functionAppName}-plan'

@allowed([512, 2048, 4096])
param instanceMemoryMB int = 2048

@minValue(40)
@maxValue(1000)
param maximumInstanceCount int = 100

param exportContainerName string = 'exports'

param entraRoleMembersSchedule string = '0 0 0 * * 0' // Runs every Sunday at 00:00 UTC
param accountMatchSchedule string = '0 15 0 * * 0' // Runs every Sunday at 00:15 UTC
param groupMembersSchedule string = '0 30 0 * * 0' // Runs every Sunday at 00:30 UTC
param auGroupMembersSchedule string = '0 0 1 * * 0' // Runs every Sunday at 01:00 UTC
param subscriptionsSchedule string = '0 0 4 * * 0' // Runs every Sunday at 04:00 UTC
param appRegistrationsSchedule string = '0 0 2 * * 0' // Runs every Sunday at 02:00 UTC
param graphPermissionsSchedule string = '0 30 1 * * 0' // Runs every Sunday at 01:30 UTC
param licensesSchedule string = '0 0 3 * * 0' // Runs every Sunday at 03:00 UTC
param inactiveEntraAdminsSchedule string = '0 30 3 * * 0' // Runs every Sunday at 03:30 UTC

var deploymentContainerName = 'app-package-${uniqueString(resourceGroup().id, functionAppName)}'
var storageBlobDataContributor = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var storageBlobDataOwner = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageTableDataContributor = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
var functionAppPrincipalId = functionApp.outputs.systemAssignedMIPrincipalId!

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.15.0' = {
  name: 'log-${uniqueString(resourceGroup().id, logAnalyticsName)}'
  params: {
    name: logAnalyticsName
    location: location
    dataRetention: 30
  }
}

module appInsights 'br/public:avm/res/insights/component:0.6.0' = {
  name: 'appi-${uniqueString(resourceGroup().id, appInsightsName)}'
  params: {
    name: appInsightsName
    location: location
    kind: 'web'
    applicationType: 'web'
    workspaceResourceId: resourceId('Microsoft.OperationalInsights/workspaces', logAnalyticsName)
  }
}

module storage 'br/public:avm/res/storage/storage-account:0.31.0' = {
  name: 'st-${uniqueString(resourceGroup().id, storageAccountName)}'
  params: {
    name: storageAccountName
    location: location
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    roleAssignments: [
      {
        name: guid(resourceId('Microsoft.Storage/storageAccounts', storageAccountName), functionAppName, storageBlobDataOwner)
        roleDefinitionIdOrName: storageBlobDataOwner
        principalId: functionAppPrincipalId
        principalType: 'ServicePrincipal'
      }
      {
        name: guid(resourceId('Microsoft.Storage/storageAccounts', storageAccountName), functionAppName, storageTableDataContributor)
        roleDefinitionIdOrName: storageTableDataContributor
        principalId: functionAppPrincipalId
        principalType: 'ServicePrincipal'
      }
      {
        name: guid(resourceId('Microsoft.Storage/storageAccounts', storageAccountName), functionAppName, storageBlobDataContributor, 'deployer')
        roleDefinitionIdOrName: storageBlobDataContributor
        principalId: deployer().objectId
        principalType: 'User'
      }
    ]
  }
}

module deploymentContainer 'br/public:avm/res/storage/storage-account/blob-service/container:0.3.2' = {
  name: 'deploy-container-${uniqueString(resourceGroup().id, deploymentContainerName)}'
  dependsOn: [
    storage
  ]
  params: {
    name: deploymentContainerName
    storageAccountName: storageAccountName
  }
}

module exportStorage 'br/public:avm/res/storage/storage-account:0.31.0' = {
  name: 'stexp-${uniqueString(resourceGroup().id, exportStorageAccountName)}'
  params: {
    name: exportStorageAccountName
    location: location
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    roleAssignments: [
      {
        name: guid(resourceId('Microsoft.Storage/storageAccounts', exportStorageAccountName), functionAppName, storageBlobDataContributor)
        roleDefinitionIdOrName: storageBlobDataContributor
        principalId: functionAppPrincipalId
        principalType: 'ServicePrincipal'
      }
      {
        name: guid(resourceId('Microsoft.Storage/storageAccounts', exportStorageAccountName), functionAppName, storageBlobDataContributor, 'deployer')
        roleDefinitionIdOrName: storageBlobDataContributor
        principalId: deployer().objectId
        principalType: 'User'
      }
    ]
  }
}

module exportContainer 'br/public:avm/res/storage/storage-account/blob-service/container:0.3.2' = {
  name: 'export-container-${uniqueString(resourceGroup().id, exportContainerName)}'
  dependsOn: [
    exportStorage
  ]
  params: {
    name: exportContainerName
    storageAccountName: exportStorageAccountName
  }
}

module appServicePlan 'br/public:avm/res/web/serverfarm:0.6.0' = {
  name: 'plan-${uniqueString(resourceGroup().id, appServicePlanName)}'
  params: {
    name: appServicePlanName
    location: location
    skuName: 'FC1'
    kind: 'linux'
    reserved: true
  }
}

module functionApp 'br/public:avm/res/web/site:0.21.0' = {
  name: 'func-${uniqueString(resourceGroup().id, functionAppName)}'
  params: {
    name: functionAppName
    location: location
    kind: 'functionapp,linux'
    managedIdentities: {
      systemAssigned: true
    }
    serverFarmResourceId: appServicePlan.outputs.resourceId
    httpsOnly: true
    siteConfig: {
      alwaysOn: false
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: 'https://${storageAccountName}.blob.${environment().suffixes.storage}/${deploymentContainerName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
      }
      runtime: {
        name: 'powerShell'
        version: '7.4'
      }
    }
  }
}

module appSettings 'br/public:avm/res/web/site/config:0.2.0' = {
  name: 'appsettings-${uniqueString(resourceGroup().id, functionAppName)}'
  dependsOn: [
    functionApp
  ]
  params: {
    name: 'appsettings'
    appName: functionAppName
    properties: {
      FUNCTIONS_EXTENSION_VERSION: '~4'
      AzureWebJobsStorage__accountName: storageAccountName
      APPLICATIONINSIGHTS_CONNECTION_STRING: appInsights.outputs.connectionString
      EXPORT_ENTRAROLEMEMBERS_SCHEDULE: entraRoleMembersSchedule
      EXPORT_ACCOUNTMATCH_SCHEDULE: accountMatchSchedule
      EXPORT_GROUPMEMBERS_SCHEDULE: groupMembersSchedule
      EXPORT_AUGROUPMEMBERS_SCHEDULE: auGroupMembersSchedule
      EXPORT_SUBSCRIPTIONS_SCHEDULE: subscriptionsSchedule
      EXPORT_APPREGS_SCHEDULE: appRegistrationsSchedule
      EXPORT_GRAPHPERMS_SCHEDULE: graphPermissionsSchedule
      EXPORT_LICENSES_SCHEDULE: licensesSchedule
      EXPORT_INACTIVEENTRAADMINS_SCHEDULE: inactiveEntraAdminsSchedule
    }
  }
}

output functionAppHostname string = functionApp.outputs.defaultHostname
output functionAppResourceId string = resourceId('Microsoft.Web/sites', functionAppName)
output exportStorageName string = exportStorageAccountName

