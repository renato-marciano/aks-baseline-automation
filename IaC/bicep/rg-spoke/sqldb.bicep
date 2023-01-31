targetScope = 'subscription'

@description('The regional network spoke VNet Resource ID that the cluster will be joined to.')
@minLength(79)
param targetVnetResourceId string

@description('Name of the resource group')
param resourceGroupName string = 'rg-bu0001a0008'

@description('Location for all resources.')
param location string

var subRgUniqueString = uniqueString('aks', subscription().subscriptionId, resourceGroupName, location)

@description('The administrator username of the SQL logical server.')
@secure()
param administratorLogin string

@description('The administrator password of the SQL logical server.')
@secure()
param administratorLoginPassword string

var sqlServerName = 'sqlServer${subRgUniqueString}'

module rg '../CARML/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: resourceGroupName
  params: {
    name: resourceGroupName
    location: location
  }
}


module sqlServer '../CARML/Microsoft.Sql/servers/deploy.bicep' = {
  name: sqlServerName
  params: {
    name: sqlServerName
    location: location
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    databases: [
      {
        name: 'db-ist'
      }
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
    dnsPrivateZoneSql
  ]
}

module sqlPrivateEndpoint '../CARML/Microsoft.Network/privateEndpoints/deploy.bicep' = {
  name: 'nodepools-to-sql'
  params: {
    name: 'nodepools-to-sql'
    location: location
    subnetResourceId: spokeVirtualNetwork::snetClusterNodes.id
    groupIds: [
      'sqlServer'
    ]
    serviceResourceId: sqldb.outputs.resourceId
    privateDnsZoneGroup: {
      privateDNSResourceIds: [
        dnsPrivateZoneSql.outputs.resourceId
      ]
    }
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
    dnsPrivateZoneSql
    sqlServer
  ]
}

module dnsPrivateZoneSql '../CARML/Microsoft.Network/privateDnsZones/deploy.bicep' = {
  name: 'privatelink.database.windows.net'
  params: {
    name: 'privatelink.database.windows.net'
    location: 'global'
    virtualNetworkLinks: [
      {
        name: 'to_${spokeVirtualNetwork.name}'
        virtualNetworkResourceId: targetVnetResourceId
        registrationEnabled: false
      }
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

/*** EXISTING RESOURCES ***/

resource spokeResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: '${split(targetVnetResourceId, '/')[4]}'
}

resource spokeVirtualNetwork 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  scope: spokeResourceGroup
  name: '${last(split(targetVnetResourceId, '/'))}'

  resource snetClusterNodes 'subnets@2021-05-01' existing = {
    name: 'snet-clusternodes'
  }
}

output sqlServerName string = sqlServerName