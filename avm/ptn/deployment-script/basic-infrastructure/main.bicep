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

@description('Optional. Enable/Disable usage telemetry for module.')
param enableTelemetry bool = true

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
    subnets: []
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
  }
}

module privateEndpoint 'br/public:avm/res/network/private-endpoint:0.4.3' = {
  name: '${uniqueString(deployment().name, privateEndpointName, location)}-private-endpoint-deployment'
  params: {
    name: privateEndpointName
    location: location
    privateLinkServiceId: null ?? storageAccount.outputs.resourceId
    subnetId: null ?? virtualNetwork.outputs.subnetNames
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

resource resVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'my-vnet'
  location: parLocation
  properties: {
    addressSpace: {
      addressPrefixes: [
        '192.168.4.0/23'
      ]
    }
  }

  resource resPrivateEndpointSubnet 'subnets' = {
    name: 'PrivateEndpointSubnet'
    properties: {
      addressPrefixes: [
        '192.168.4.0/24'
      ]
    }
  }

  resource resContainerInstanceSubnet 'subnets' = {
    name: 'ContainerInstanceSubnet'
    properties: {
      addressPrefix: '192.168.5.0/24'
      delegations: [
        {
          name: 'containerDelegation'
          properties: {
            serviceName: 'Microsoft.ContainerInstance/containerGroups'
          }
        }
      ]
    }
  }
}

resource resPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: resStorageAccount.name
  location: parLocation
  properties: {
    privateLinkServiceConnections: [
      {
        name: resStorageAccount.name
        properties: {
          privateLinkServiceId: resStorageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
    customNetworkInterfaceName: '${resStorageAccount.name}-nic'
    subnet: {
      id: resVirtualNetwork::resPrivateEndpointSubnet.id
    }
  }
}

resource resStorageFileDataPrivilegedContributorRef 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: '69566ab7-960f-475b-8e7c-b3118f30c6bd' // Storage File Data Privileged Contributor
  scope: tenant()
}

resource resRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resStorageFileDataPrivilegedContributorRef.id, resManagedIdentity.id, resStorageAccount.id)
  scope: resStorageAccount
  properties: {
    principalId: resManagedIdentity.properties.principalId
    roleDefinitionId: resStorageFileDataPrivilegedContributorRef.id
    principalType: 'ServicePrincipal'
  }
}

resource resPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.file.core.windows.net'
  location: 'global'

  resource resVirtualNetworkLink 'virtualNetworkLinks' = {
    name: uniqueString(resVirtualNetwork.name)
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: resVirtualNetwork.id
      }
    }
  }

  resource resRecord 'A' = {
    name: resStorageAccount.name
    properties: {
      ttl: 10
      aRecords: [
        {
          ipv4Address: first(first(resPrivateEndpoint.properties.customDnsConfigs)!.ipAddresses)
        }
      ]
    }
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
