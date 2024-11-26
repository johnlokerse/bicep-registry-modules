metadata name = 'infrastructure-private-deployment-scripts'
metadata description = 'This module deploys required infrastructure to run deployment scripts privately over private endpoint.'
metadata owner = 'Azure/module-maintainers'

@description('Optional. Location for all Resources.')
param location string = resourceGroup().location

@description('Required. The name of the Managed Identity resource.')
param managedIdentityName string

param managedIdentityId string?

param storageAccountName string
param storageAccountSkuName string
param storageAccountPublicNetworkAccess string
param storageAccountNetworkAcls object = {
  defaultAction: 'Deny'
  bypass: 'AzureServices'
}
param storageAccountId string?

param privateEndpointName string
param privateEndpointNicName string?

param virtualNetworkName string
param virtualNetworkAddressPrefixes string[]
param subnetPrivateEndpoint subnetType
param subnetContainerInstance subnetType
param containerSubnetId string?

param filePrivateDnsZoneId string?

param deploymentScriptConfiguration privateDeploymentScriptType[]

@description('Optional. Enable/Disable usage telemetry for module.')
param enableTelemetry bool = true

var combinedSubnets = array(union(subnetPrivateEndpoint, subnetContainerInstance))
var roleStorageFileDataPrivilegedContributorId = '69566ab7-960f-475b-8e7c-b3118f30c6bd'
var privateDnsZoneName = 'privatelink.file.core.windows.net'

#disable-next-line no-deployments-resources
resource avmTelemetry 'Microsoft.Resources/deployments@2023-07-01' = if (enableTelemetry) {
  name: '46d3xbcp.ptn.pds-infrastructure.${replace('-..--..-', '.', '-')}.${substring(uniqueString(deployment().name, location), 0, 4)}'
  properties: {
    mode: 'Incremental'
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      resources: []
      outputs: {
        telemetry: {
          type: 'String'
          value: 'For more information, see https://aka.ms/avm/TelemetryInfo'
        }
      }
    }
  }
}

module managedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = if (empty(managedIdentityId)) {
  name: '${uniqueString(deployment().name, managedIdentityName, location)}-managed-identity-deployment'
  params: {
    name: managedIdentityName
    location: location
  }
}

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.5.1' = if (empty(containerSubnetId)) {
  name: '${uniqueString(deployment().name, virtualNetworkName, location)}-virtual-network-deployment'
  params: {
    name: virtualNetworkName
    location: location
    addressPrefixes: virtualNetworkAddressPrefixes
    subnets: combinedSubnets
  }
}

module storageAccount 'br/public:avm/res/storage/storage-account:0.14.3' = if (empty(storageAccountId)) {
  name: '${uniqueString(deployment().name, storageAccountName, location)}-storage-account-deployment'
  params: {
    name: storageAccountName
    location: location
    skuName: storageAccountSkuName
    publicNetworkAccess: storageAccountPublicNetworkAccess
    networkAcls: storageAccountNetworkAcls
    privateEndpoints: [
      {
        name: privateEndpointName
        location: location
        customNetworkInterfaceName: privateEndpointNicName ?? '${storageAccountName}-nic'
        service: 'file'
        subnetResourceId: first(filter(
          virtualNetwork.outputs.subnetResourceIds,
          subnet => contains(subnet, subnetPrivateEndpoint.name)
        ))
      }
    ]
    roleAssignments: [
      {
        principalId: managedIdentity.outputs.principalId
        roleDefinitionIdOrName: roleStorageFileDataPrivilegedContributorId
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.6.0' = if (empty(filePrivateDnsZoneId)) {
  name: '${uniqueString(deployment().name, privateDnsZoneName, location)}-private-dns-zone-deployment'
  params: {
    name: privateDnsZoneName
    location: location
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: virtualNetwork.outputs.resourceId
      }
    ]
    a: [
      {
        name: storageAccount.outputs.name
        ttl: 10
        aRecords: [
          {
            ipv4Address: first(first(first(storageAccount.outputs.privateEndpoints).customDnsConfigs).ipAddresses)
          }
        ]
      }
    ]
  }
}

module privateDeploymentScript 'br/public:avm/res/resources/deployment-script:0.5.0' = [for deploymentScript in deploymentScriptConfiguration: {
  name: '${uniqueString(deployment().name, 'private-deployment-script', location)}-deployment-script-deployment'
  params: {
    name: deploymentScript.name
    managedIdentities: {
      userAssignedResourceIds: [
        managedIdentityId ?? managedIdentity.outputs.resourceId
      ]
    }
    subnetResourceIds: [
      containerSubnetId ?? first(filter(
        virtualNetwork.outputs.subnetResourceIds,
        subnet => contains(subnet, subnetContainerInstance.name)
      ))
    ]
    azPowerShellVersion:
    retentionInterval: 'P1D'
    scriptContent: 'Write-Host "Hello World!"'
    environmentVariables:
    storageAccountResourceId: storageAccountId ?? storageAccount.outputs.resourceId
    kind: 'AzurePowerShell'
    azCliVersion:
  }
}]

// Types

type subnetType = {
  @description('Required. The name of the resource that is unique within a resource group. This name can be used to access the resource.')
  name: string

  @description('Required. List of address prefixes for the subnet.')
  addressPrefixes: string[]

  @description('Optional. An array of references to the delegations on the subnet.')
  delegations: {
    @description('Required. The name of the resource that is unique within a subnet. This name can be used to access the resource.')
    name: string

    @description('Required. The name of the service to whom the subnet should be delegated (e.g. Microsoft.Sql/servers).')
    serviceName: string
  }[]?
}

@discriminator('kind')
type privateDeploymentScriptType = azurePowerShellConfigType | azureCliConfigType

type azurePowerShellConfigType = {
  @description('Required. Specifies the Kind of the Deployment Script.')
  kind: 'AzurePowerShell'

  @description('Required. Name of the Deployment Script.')
  name: string

  @description('Required. Azure PowerShell module version to be used. See a list of supported Azure PowerShell versions: https://mcr.microsoft.com/v2/azuredeploymentscripts-powershell/tags/list.')
  azPowerShellVersion: string

  @description('Optional. Script body. Max length: 32000 characters. To run an external script, use primaryScriptURI instead.')
  @maxLength(32000)
  scriptContent: string?

  @description('Optional. Uri for the external script. This is the entry point for the external script. To run an internal script, use the scriptContent parameter instead.')
  primaryScriptUri: string?

  @description('Optional. The environment variables to pass over to the script.')
  environmentVariables: environmentVariableType[]?
}

type azureCliConfigType = {
  @description('Required. Specifies the Kind of the Deployment Script.')
  kind: 'AzureCLI'

  @description('Required. Name of the Deployment Script.')
  name: string

  @description('Optional. Azure CLI module version to be used. See a list of supported Azure CLI versions: https://mcr.microsoft.com/v2/azure-cli/tags/list.')
  azCliVersion: string

  @description('Optional. Script body. Max length: 32000 characters. To run an external script, use primaryScriptURI instead.')
  @maxLength(32000)
  scriptContent: string?

  @description('Optional. Uri for the external script. This is the entry point for the external script. To run an internal script, use the scriptContent parameter instead.')
  primaryScriptUri: string?

  @description('Optional. The environment variables to pass over to the script.')
  environmentVariables: environmentVariableType[]?
}

type environmentVariableType = {
  @description('Required. The name of the environment variable.')
  name: string

  @description('Conditional. The value of the secure environment variable. Required if `value` is null.')
  @secure()
  secureValue: string?

  @description('Conditional. The value of the environment variable. Required if `secureValue` is null.')
  value: string?
}
