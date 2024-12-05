targetScope = 'subscription'

metadata name = 'Using Azure PowerShell'
metadata description = 'This instance deploys the module with Azure PowerShell properties'

// ========== //
// Parameters //
// ========== //

@description('Optional. The name of the resource group to deploy for testing purposes.')
@maxLength(90)
param resourceGroupName string = 'dep-${namePrefix}-deploymentscript-infra-${serviceShort}-rg'

@description('Optional. The location to deploy resources to.')
param resourceLocation string = deployment().location

@description('Optional. A short identifier for the kind of deployment. Should be kept short to not run into resource-name length-constraints.')
param serviceShort string = 'dsinfrapwsh'

@description('Optional. A token to inject into the name of each resource. This value can be automatically injected by the CI.')
param namePrefix string = '#_namePrefix_#'

// ============== //
// General resources
// =================
resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-07-01' = {
  name: resourceGroupName
  location: resourceLocation
}

// ============== //
// Test Execution //
// ============== //
var addressPrefix = '192.168.1.0/24'
@batchSize(1)
module testDeployment '../../main.bicep' = [
  for iteration in ['init', 'idem']: {
    scope: resourceGroup
    name: '${uniqueString(deployment().name, resourceLocation)}-pwsh-test-${serviceShort}-${iteration}'
    params: {
      managedIdentityName: '${namePrefix}${serviceShort}mi001'
      privateEndpointName: '${namePrefix}${serviceShort}pe001'
      privateEndpointNicName: '${namePrefix}${serviceShort}pen001'
      storageAccountName: '${namePrefix}${serviceShort}sa001'
      storageAccountSkuName: 'Standard_LRS'
      virtualNetworkName: '${namePrefix}${serviceShort}vnet001'
      virtualNetworkAddressPrefixes: [
        addressPrefix
      ]
      subnetPrivateEndpoint: {
        name: 'PrivateEndpointSubnet'
        addressPrefixes: [
          cidrSubnet(addressPrefix, 25, 0)
        ]
      }
      subnetContainerInstance: {
        name: 'PrivateEndpointSubnet'
        addressPrefixes: [
          cidrSubnet(addressPrefix, 25, 1)
        ]
      }
      deploymentScriptConfiguration: [
        {
          name: '${namePrefix}${serviceShort}pwsh001'
          kind: 'AzurePowerShell'
          azPowerShellVersion:
          cleanupPreference:
        }
      ]
    }
  }
]
