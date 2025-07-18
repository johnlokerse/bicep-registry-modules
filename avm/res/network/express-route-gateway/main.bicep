metadata name = 'Express Route Gateways'
metadata description = 'This module deploys an Express Route Gateway.'

@description('Required. Name of the Express Route Gateway.')
param name string

@description('Optional. Location for all resources.')
param location string = resourceGroup().location

@description('Optional. Tags of the Firewall policy resource.')
param tags resourceInput<'Microsoft.Network/expressRouteGateways@2024-07-01'>.tags?

@description('Optional. Configures this gateway to accept traffic from non Virtual WAN networks.')
param allowNonVirtualWanTraffic bool = false

@description('Optional. Maximum number of scale units deployed for ExpressRoute gateway.')
param autoScaleConfigurationBoundsMax int = 2

@description('Optional. Minimum number of scale units deployed for ExpressRoute gateway.')
param autoScaleConfigurationBoundsMin int = 2

@description('Optional. List of ExpressRoute connections to the ExpressRoute gateway. **Note:** This parameter will overwrite existing connections, including deleting any that are not provided. This is by-design behavior of the resource provider.')
param expressRouteConnections array = []

@description('Required. Resource ID of the Virtual Wan Hub.')
param virtualHubId string

import { roleAssignmentType } from 'br/public:avm/utl/types/avm-common-types:0.6.0'
@description('Optional. Array of role assignments to create.')
param roleAssignments roleAssignmentType[]?

@description('Optional. Enable/Disable usage telemetry for module.')
param enableTelemetry bool = true

import { lockType } from 'br/public:avm/utl/types/avm-common-types:0.6.0'
@description('Optional. The lock settings of the service.')
param lock lockType?

var builtInRoleNames = {
  Contributor: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  'Network Contributor': subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '4d97b98b-1d4f-4787-a291-c67834d212e7'
  )
  Owner: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8e3af657-a8ff-443c-a75c-2fe8c4bcb635')
  Reader: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  'Role Based Access Control Administrator': subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    'f58310d9-a9f6-439a-9e8d-f62e7b41a168'
  )
  'User Access Administrator': subscriptionResourceId(
    'Microsoft.Authorization/roleDefinitions',
    '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9'
  )
}

var formattedRoleAssignments = [
  for (roleAssignment, index) in (roleAssignments ?? []): union(roleAssignment, {
    roleDefinitionId: builtInRoleNames[?roleAssignment.roleDefinitionIdOrName] ?? (contains(
        roleAssignment.roleDefinitionIdOrName,
        '/providers/Microsoft.Authorization/roleDefinitions/'
      )
      ? roleAssignment.roleDefinitionIdOrName
      : subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleAssignment.roleDefinitionIdOrName))
  })
]

#disable-next-line no-deployments-resources
resource avmTelemetry 'Microsoft.Resources/deployments@2024-03-01' = if (enableTelemetry) {
  name: '46d3xbcp.res.network-expressroutegateway.${replace('-..--..-', '.', '-')}.${substring(uniqueString(deployment().name, location), 0, 4)}'
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

resource expressRouteGateway 'Microsoft.Network/expressRouteGateways@2024-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    allowNonVirtualWanTraffic: allowNonVirtualWanTraffic
    autoScaleConfiguration: {
      bounds: {
        max: autoScaleConfigurationBoundsMax
        min: autoScaleConfigurationBoundsMin
      }
    }
    expressRouteConnections: expressRouteConnections
    virtualHub: {
      id: virtualHubId
    }
  }
}

resource expressRouteGateway_lock 'Microsoft.Authorization/locks@2020-05-01' = if (!empty(lock ?? {}) && lock.?kind != 'None') {
  name: lock.?name ?? 'lock-${name}'
  properties: {
    level: lock.?kind ?? ''
    notes: lock.?kind == 'CanNotDelete'
      ? 'Cannot delete resource or child resources.'
      : 'Cannot delete or modify the resource or child resources.'
  }
  scope: expressRouteGateway
}

resource expressRouteGateway_roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for (roleAssignment, index) in (formattedRoleAssignments ?? []): {
    name: roleAssignment.?name ?? guid(
      expressRouteGateway.id,
      roleAssignment.principalId,
      roleAssignment.roleDefinitionId
    )
    properties: {
      roleDefinitionId: roleAssignment.roleDefinitionId
      principalId: roleAssignment.principalId
      description: roleAssignment.?description
      principalType: roleAssignment.?principalType
      condition: roleAssignment.?condition
      conditionVersion: !empty(roleAssignment.?condition) ? (roleAssignment.?conditionVersion ?? '2.0') : null // Must only be set if condtion is set
      delegatedManagedIdentityResourceId: roleAssignment.?delegatedManagedIdentityResourceId
    }
    scope: expressRouteGateway
  }
]

@description('The resource ID of the ExpressRoute Gateway.')
output resourceId string = expressRouteGateway.id

@description('The resource group of the ExpressRoute Gateway was deployed into.')
output resourceGroupName string = resourceGroup().name

@description('The name of the ExpressRoute Gateway.')
output name string = expressRouteGateway.name

@description('The location the resource was deployed into.')
output location string = expressRouteGateway.location
