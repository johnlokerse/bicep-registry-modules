metadata name = 'basic-infrastructure-private-deployment-scripts'
metadata description = 'This module deploys required infrastructure to run deployment scripts privately over private endpoint.'
metadata owner = 'Azure/module-maintainers'

@description('Optional. Location for all Resources.')
param location string = resourceGroup().location

@description('Required. The name of the Managed Identity resource.')
param managedIdentityName string

param storageAccountName string
param storageAccountSkuName string
param storageAccountPublicNetworkAccess string
param storageAccountNetworkAcls object = {
  defaultAction: 'Deny'
  bypass: 'AzureServices'
}

param privateEndpointName string
param privateEndpointNicName string

param virtualNetworkName string
param virtualNetworkAddressPrefixes string[]
param subnetPrivateEndpoint subnetType
param subnetContainerInstance subnetType

@description('Optional. Enable/Disable usage telemetry for module.')
param enableTelemetry bool = true

var combineSubnets = array(union(subnetPrivateEndpoint, subnetContainerInstance))
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

module managedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.2' = {
  name: '${uniqueString(deployment().name, managedIdentityName, location)}-managed-identity-deployment'
  params: {
    name: managedIdentityName
    location: location
  }
}

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.1.8' = {
  name: '${uniqueString(deployment().name, virtualNetworkName, location)}-virtual-network-deployment'
  params: {
    name: virtualNetworkName
    location: location
    addressPrefixes: virtualNetworkAddressPrefixes
    subnets: combineSubnets
  }
}

module storageAccount 'br/public:avm/res/storage/storage-account:0.11.0' = {
  name: '${uniqueString(deployment().name, storageAccountName, location)}-storage-account-deployment'
  params: {
    name: storageAccountName
    location: location
    skuName: storageAccountSkuName
    publicNetworkAccess: storageAccountPublicNetworkAccess
    networkAcls: storageAccountNetworkAcls
    roleAssignments: [
      {
        principalId: managedIdentity.outputs.principalId
        roleDefinitionIdOrName: roleStorageFileDataPrivilegedContributorId
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

module privateEndpoint 'br/public:avm/res/network/private-endpoint:0.4.3' = {
  name: '${uniqueString(deployment().name, privateEndpointName, location)}-private-endpoint-deployment'
  params: {
    name: privateEndpointName
    location: location
    subnetResourceId: null ?? first(filter(
      virtualNetwork.outputs.subnetResourceIds,
      arg => contains(arg, subnetPrivateEndpoint.name)
    ))
    privateLinkServiceConnections: [
      {
        name: storageAccount.outputs.resourceId
        properties: {
          privateLinkServiceId: storageAccount.outputs.resourceId
          groupIds: [
            'file'
          ]
        }
      }
    ]
    customNetworkInterfaceName: null ?? privateEndpointNicName
  }
}

module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.3.1' = {
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
            ipv4Address: first(first(privateEndpoint.outputs.customDnsConfigs)!.ipAddresses)
          }
        ]
      }
    ]
  }
}

resource resPrivateDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'my-private-deployment-script'
  dependsOn: [
    resPrivateEndpoint
    resPrivateDnsZone::resVirtualNetworkLink
  ]
  location: parLocation
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resManagedIdentity.id}': {}
    }
  }
  properties: {
    storageAccountSettings: {
      storageAccountName: resStorageAccount.name
    }
    containerSettings: {
      subnetIds: [
        {
          id: resVirtualNetwork::resContainerInstanceSubnet.id
        }
      ]
    }
    azPowerShellVersion: '9.0'
    retentionInterval: 'P1D'
    scriptContent: 'Write-Host "Hello World!"'
  }
}

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
