@description('Location for all resources.')
param location string = resourceGroup().location

@minLength(2)
@maxLength(32)
@description('The name of the Container App. Lowercase letters, numbers and hyphens only. It is part of the default domain name https://\${containerAppName}.<random>.<region>.azurecontainerapps.io')
param containerAppName string = 'entropy-data'

@description('The Docker container image.')
param containerImageUrl string = 'docker.io/entropydata/entropy-data-ce:latest'

@description('CPU cores for the container. Together with the memory it must be one of the allowed combinations of the Consumption workload profile, e.g. 0.5/1Gi, 1/2Gi, 2/4Gi, 4/8Gi.')
param containerCpu string = '1'

@description('Memory for the container, e.g. 2Gi.')
param containerMemory string = '2Gi'

@minValue(1)
@description('Minimum number of running replicas.')
param minReplicas int = 1

@minValue(1)
@description('Maximum number of running replicas.')
param maxReplicas int = 1

@description('Public URL of the application, e.g. https://entropy.example.com. Used in emails to build links. Leave empty to use the default domain of the Container App.')
param applicationHostWeb string = ''

@description('Comma-separated email addresses of super admins. Can be changed later.')
param superAdmins string = ''

@description('SMTP server host. You can use Azure Communication Services, SendGrid or any other SMTP server. Leave empty to run without transactional emails (account verification, notifications).')
param smtpHost string = ''

@description('SMTP server port')
param smtpPort string = '587'

@description('Login user of the SMTP server')
param smtpUsername string = ''

@description('Login password of the SMTP server. If you use SendGrid, this is your API Key.')
@secure()
param smtpPassword string = ''

@description('Use basic authentication for SMTP')
param smtpBasicAuth bool = true

@description('Ensure that TLS is used')
param smtpStarttls bool = true

@description('The sender email address for Entropy Data emails. For many email providers, such as SendGrid, that must be a verified sender email address. Required when smtpHost is set.')
param mailFrom string = ''

@description('Postgres compute tier size')
// $160/month
param postgresComputeTierSizeSku string = 'Standard_D2s_v3'

@description('Postgres storge size in GB. Min 128 GB.')
param postgresStorageSizeGB int = 128

@description('The name of the PostgreSQL server. Must be globally unique.')
param postgresServerName string = 'entropydata-postgres-${resourceGroup().name}'

@description('The administrator username of the PostgreSQL server.')
param postgresAdminUsername string = 'adminuser'

@description('The administrator password of the PostgreSQL server.')
@secure()
param postgresAdminPassword string = newGuid()

@description('The database name.')
param databaseName string = 'postgres'

@description('The virtual network name.')
param vnetName string = 'entropydata-vnet'

@description('The address prefix for the virtual network.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('The name of the Container Apps infrastructure subnet.')
param containerAppsSubnetName string = 'containerapps-subnet'

@description('The address prefix for the Container Apps infrastructure subnet. Min /27.')
param containerAppsSubnetAddressPrefix string = '10.0.0.0/23'

@description('The name of the PostgreSQL subnet.')
param postgresSubnetName string = 'postgres-subnet'

@description('The address prefix for the PostgreSQL subnet.')
param postgresSubnetAddressPrefix string = '10.0.2.0/24'

@description('Retention of container logs in Log Analytics in days.')
param logRetentionInDays int = 30


var hasSmtp = !empty(smtpHost)
var hasSmtpPassword = hasSmtp && !empty(smtpPassword)
var postgresPasswordSecretName = 'postgres-password'
var smtpPasswordSecretName = 'smtp-password'

var baseEnv = [
  {
    name: 'APPLICATION_HOST_WEB'
    value: empty(applicationHostWeb) ? 'https://${containerAppName}.${containerAppsEnvironment.properties.defaultDomain}' : applicationHostWeb
  }
  {
    name: 'APPLICATION_SUPERADMINS'
    value: superAdmins
  }
  {
    name: 'SPRING_DATASOURCE_URL'
    value: 'jdbc:postgresql://${postgres.properties.fullyQualifiedDomainName}:5432/${databaseName}'
  }
  {
    name: 'SPRING_DATASOURCE_USERNAME'
    value: postgresAdminUsername
  }
  {
    name: 'SPRING_DATASOURCE_PASSWORD'
    secretRef: postgresPasswordSecretName
  }
]

var smtpEnv = [
  {
    name: 'SPRING_MAIL_HOST'
    value: smtpHost
  }
  {
    name: 'SPRING_MAIL_PORT'
    value: smtpPort
  }
  {
    name: 'SPRING_MAIL_USERNAME'
    value: smtpUsername
  }
  {
    name: 'SPRING_MAIL_PROPERTIES_MAIL_SMTP_AUTH'
    value: toLower(string(smtpBasicAuth))
  }
  {
    name: 'SPRING_MAIL_PROPERTIES_MAIL_SMTP_STARTTLS_ENABLE'
    value: toLower(string(smtpStarttls))
  }
  {
    name: 'APPLICATION_MAIL_FROM'
    value: mailFrom
  }
]

var smtpPasswordEnv = [
  {
    name: 'SPRING_MAIL_PASSWORD'
    secretRef: smtpPasswordSecretName
  }
]


resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${containerAppName}-logs'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionInDays
  }
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: '${containerAppName}-env'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      internal: false
      infrastructureSubnetId: '${vnet.id}/subnets/${containerAppsSubnetName}'
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    zoneRedundant: false
  }
}

resource containerApp 'Microsoft.App/containerApps@2025-07-01' = {
  name: containerAppName
  location: location
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      secrets: concat(
        [
          {
            name: postgresPasswordSecretName
            value: postgresAdminPassword
          }
        ],
        hasSmtpPassword ? [
          {
            name: smtpPasswordSecretName
            value: smtpPassword
          }
        ] : []
      )
    }
    template: {
      containers: [
        {
          name: 'entropy-data'
          image: containerImageUrl
          resources: {
            cpu: json(containerCpu)
            memory: containerMemory
          }
          env: concat(baseEnv, hasSmtp ? smtpEnv : [], hasSmtpPassword ? smtpPasswordEnv : [])
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/actuator/health/readiness'
                port: 8080
              }
              periodSeconds: 10
              failureThreshold: 30
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/actuator/health/readiness'
                port: 8080
              }
              periodSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/actuator/health/liveness'
                port: 8080
              }
              periodSeconds: 30
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: postgresServerName
  location: location
  sku: {
    name: postgresComputeTierSizeSku
    tier: 'GeneralPurpose'
  }
  properties: {
    version: '16'
    storage: {
      storageSizeGB: postgresStorageSizeGB
      autoGrow: 'Enabled'
    }
    network: {
      publicNetworkAccess: 'Disabled'
      delegatedSubnetResourceId: '${vnet.id}/subnets/${postgresSubnetName}'
      privateDnsZoneArmResourceId: privateDnsZones_privatelink_postgres.id
    }
    dataEncryption: {
      type: 'SystemManaged'
    }
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    administratorLogin: postgresAdminUsername
    administratorLoginPassword: postgresAdminPassword
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    maintenanceWindow: {
      customWindow: 'Disabled'
      dayOfWeek: 0
      startHour: 0
      startMinute: 0
    }
  }
  dependsOn: [
    privateDnsZones_privatelink_postgres_dblink
  ]
}

resource postgres_extensions 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: postgres
  name: 'azure.extensions'
  properties: {
    value: 'VECTOR,UUID-OSSP,HSTORE'
    source: 'user-override'
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: containerAppsSubnetName
        properties: {
          addressPrefix: containerAppsSubnetAddressPrefix
          delegations: [
            {
              name: 'dlg-containerapps'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: postgresSubnetName
        properties: {
          addressPrefix: postgresSubnetAddressPrefix
          delegations: [
            {
              name: 'dlg-postgres'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
    ]
  }
}

resource privateDnsZones_privatelink_postgres 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.postgres.database.azure.com'
  location: 'global'
  properties: {}
}

resource privateDnsZones_privatelink_postgres_dblink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZones_privatelink_postgres
  name: '${privateDnsZones_privatelink_postgres.name}-dblink'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}


output applicationUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerAppsEnvironmentName string = containerAppsEnvironment.name
output postgresServerFqdn string = postgres.properties.fullyQualifiedDomainName
