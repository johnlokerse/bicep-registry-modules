metadata name = 'infrastructure-private-deployment-scripts'
metadata description = 'This module deploys required infrastructure to run deployment scripts privately over private endpoint.'
metadata owner = 'Azure/module-maintainers'

@description('Optional. Location for all Resources.')
param location string = resourceGroup().location

@description('Conditional. The name of the Managed Identity resource.')
param managedIdentityName string

@description('Conditional. Use this parameter when you want to refer to an existing managed identity. The ID of the managed identity.')
param managedIdentityId string?

@description('Conditional. Use this parameter when you want a new storage account. The name of the storage account.')
param storageAccountName string?

@description('Conditional. Use this parameter when you want a new storage account. The SKU of the storage account.')
param storageAccountSkuName string?

@description('Conditional. Use this parameter when you want to refer to an existing storage account. The ID of the storage account.')
param storageAccountId string?

@description('Conditional. Use this parameter when you want a new storage account. The name of the private endpoint')
param privateEndpointName string?

@description('Conditional. Use this parameter when you want a new storage account. The NIC name of the private endpoint.')
param privateEndpointNicName string?

@description('Conditional. Use this parameter when you want a new virtual network. The name of the virtual network.')
param virtualNetworkName string?

@description('Conditional. Use this parameter when you want a new virtual network. The address prefixes of the virtual network.')
param virtualNetworkAddressPrefixes string[]?

@description('Conditional. Use this parameter when you want a new virtual network. The private endpoint subnet configuration of the virtual network.')
param subnetPrivateEndpoint subnetType?

@description('Conditional. Use this parameter when you want a new virtual network. The container subnet configuration of the virtual network.')
param subnetContainerInstance subnetType?

@description('Conditional. Use this parameter when you want to refer to an existing subnet. The ID of the subnet for the container instance.')
param containerSubnetId string?

@description('Conditional. Use this parameter when you want to refer to an existing subnet. The ID of the subnet for the private endpoint.')
param privateEndpointSubnetId string?

@description('Conditional. Use this parameter when you want to refer to an existing file DNS zone. The ID of the file DNS zone.')
param filePrivateDnsZoneId string?

@description('Required. The private deployment script configuration.')
param deploymentScriptConfiguration privateDeploymentScriptType[]

@description('Optional. Enable/Disable usage telemetry for module.')
param enableTelemetry bool = true

var combinedSubnets = array(union(subnetPrivateEndpoint!, subnetContainerInstance!))
var roleStorageFileDataPrivilegedContributorId = '69566ab7-960f-475b-8e7c-b3118f30c6bd'
var privateDnsZoneName = 'privatelink.file.${environment().suffixes.storage}'

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
  name: '${uniqueString(deployment().name, virtualNetworkName!, location)}-virtual-network-deployment'
  params: {
    name: virtualNetworkName!
    location: location
    addressPrefixes: virtualNetworkAddressPrefixes!
    subnets: combinedSubnets
  }
}

module storageAccount 'br/public:avm/res/storage/storage-account:0.14.3' = if (empty(storageAccountId)) {
  name: '${uniqueString(deployment().name, storageAccountName!, location)}-storage-account-deployment'
  params: {
    name: storageAccountName!
    location: location
    skuName: storageAccountSkuName
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    privateEndpoints: [
      {
        name: privateEndpointName
        location: location
        customNetworkInterfaceName: privateEndpointNicName ?? '${storageAccountName}-nic'
        service: 'file'
        subnetResourceId: privateEndpointSubnetId ?? first(filter(
          virtualNetwork.outputs.subnetResourceIds,
          subnet => contains(subnet, subnetPrivateEndpoint!.name)
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

module privateDeploymentScript 'br/public:avm/res/resources/deployment-script:0.5.0' = [
  for deploymentScript in deploymentScriptConfiguration: {
    name: '${uniqueString(deployment().name, deploymentScript.name, location)}-deployment-script-deployment'
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
          subnet => contains(subnet, subnetContainerInstance!.name)
        ))
      ]
      azPowerShellVersion: deploymentScript.azPowerShellVersion
      retentionInterval: deploymentScript.retentionInterval
      scriptContent: deploymentScript.scriptContent
      environmentVariables: deploymentScript.environmentVariables
      storageAccountResourceId: storageAccountId ?? storageAccount.outputs.resourceId
      kind: deploymentScript.kind
      cleanupPreference: deploymentScript.cleanupPreference
      azCliVersion: deploymentScript.azCliVersion
    }
  }
]

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

    @description('Optional. The properties of the delegation.')
    properties: {
      @description('Required. The name of the service to whom the subnet should be delegated (e.g. Microsoft.Sql/servers).')
      serviceName: string
    }
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

  @description('Optional. Interval for which the service retains the script resource after it reaches a terminal state. Resource will be deleted when this duration expires. Duration is based on ISO 8601 pattern (for example P7D means one week).')
  retentionInterval: string?

  @description('Optional. Uri for the external script. This is the entry point for the external script. To run an internal script, use the scriptContent parameter instead.')
  primaryScriptUri: string?

  @description('Optional. Optional. The clean up preference when the script execution gets in a terminal state. Specify the preference on when to delete the deployment script resources. The default value is Always, which means the deployment script resources are deleted despite the terminal state (Succeeded, Failed, canceled).')
  cleanupPreference: 'Always' | 'OnExpiration' | 'OnSuccess'

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

  @description('Optional. Interval for which the service retains the script resource after it reaches a terminal state. Resource will be deleted when this duration expires. Duration is based on ISO 8601 pattern (for example P7D means one week).')
  retentionInterval: string?

  @description('Optional. Uri for the external script. This is the entry point for the external script. To run an internal script, use the scriptContent parameter instead.')
  primaryScriptUri: string?

  @description('Optional. Optional. The clean up preference when the script execution gets in a terminal state. Specify the preference on when to delete the deployment script resources. The default value is Always, which means the deployment script resources are deleted despite the terminal state (Succeeded, Failed, canceled).')
  cleanupPreference: ('Always' | 'OnExpiration' | 'OnSuccess')?

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
