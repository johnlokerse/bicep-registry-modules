targetScope = 'subscription'

metadata name = 'Using large parameter set'
metadata description = 'This instance deploys the module with most of its features enabled.'

// ========== //
// Parameters //
// ========== //

@description('Optional. The name of the resource group to deploy for testing purposes.')
@maxLength(90)
param resourceGroupName string = 'dep-${namePrefix}-deploymentscript-infra-${serviceShort}-rg'

@description('Optional. The location to deploy resources to.')
param resourceLocation string = deployment().location

@description('Optional. A short identifier for the kind of deployment. Should be kept short to not run into resource-name length-constraints.')
param serviceShort string = 'pdsi'

@description('Optional. A token to inject into the name of each resource. This value can be automatically injected by the CI.')
param namePrefix string = '#_namePrefix_#'

// ============== //
// General resources
// =================
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: resourceLocation
}

// ============== //
// Test Execution //
// ============== //

@batchSize(1)
module testDeployment '../../main.bicep' = [
  for iteration in ['init', 'idem']: {
    scope: resourceGroup
    name: '${uniqueString(deployment().name, resourceLocation)}-test-${serviceShort}-${iteration}'
    params: {
      location: resourceLocation
      managedIdentityName: 'mi-${namePrefix}-${serviceShort}'
      virtualNetworkName: 'vnet-${namePrefix}-${serviceShort}'
      virtualNetworkAddressPrefixes: [
        cidrSubnet('10.0.0.0', 16, 0)
      ]
      subnetPrivateEndpoint: {
        name: 'subnet-${namePrefix}-${serviceShort}-pe'
        addressPrefixes: [
          cidrSubnet('10.0.0.0', 24, 0)
        ]
      }
      subnetContainerInstance: {
        name: 'subnet-${namePrefix}-${serviceShort}-aci'
        addressPrefixes: [
          cidrSubnet('10.0.0.0', 24, 1)
        ]
        delegations: [
          {
            name: 'Microsoft.ContainerInstance.containerGroups'
            properties: {
              serviceName: 'Microsoft.ContainerInstance/containerGroups'
            }
          }
        ]
      }
      storageAccountName: 'sa${namePrefix}${serviceShort}'
      storageAccountSkuName: 'Standard_LRS'
      privateEndpointName: 'pe-${namePrefix}-${serviceShort}-sa'
      privateEndpointNicName: 'pe-nic-${namePrefix}-${serviceShort}-sa'
      deploymentScriptConfiguration: [
        {
          kind: 'AzureCLI'
          azCliVersion: '2.52.0'
          retentionInterval: 'P1D'
          name: 'test-script'
          cleanupPreference: 'Always'
          scriptContent: 'echo \'AVM Deployment Script test!\''
        }
      ]
      enableTelemetry: true
    }
  }
]
