Azure Deployment Template
===

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fentropy-data%2Fentropy-data-ce%2Fmain%2Fazure%2Fentropy-data-ce.json)

This deployment template can be used to deploy Entropy Data to Azure.

It is coded as a [bicep file](entropy-data-ce.bicep), and comes with a generated [Azure Resource Manager template](entropy-data-ce.json) that can be used directly in Azure deployments.

Use it directly as a deployment template, or copy it to configure to your custom needs.

Resources
---

As defined in the [bicep file](entropy-data-ce.bicep), these resources will be created:

- Container Apps environment (Consumption workload profile) integrated into the virtual network
- Container App that runs the Docker image with public HTTPS ingress and health probes on `/actuator/health/readiness`
- Log Analytics workspace for the container logs
- PostgreSQL Flexible Server 16 with the extensions `vector`, `uuid-ossp` and `hstore`
- Virtual Network with a subnet for Container Apps and a delegated subnet for PostgreSQL (Postgres is not exposed to public internet)

The application will be available under the default domain of the Container App, which is shown as the `applicationUrl` output of the deployment:

https://${containerAppName}.<random>.<region>.azurecontainerapps.io

The database password is generated during deployment and passed to the Container App as a secret. The SMTP password is stored as a Container App secret as well.


Configuration
---

SMTP parameters are optional. With `smtpHost` empty, the application runs without transactional emails (account verification, notifications). If you don't have an SMTP server, you can use [Azure Communication Services](https://learn.microsoft.com/en-us/azure/communication-services/quickstarts/email/send-email-smtp/smtp-authentication) or [SendGrid](https://portal.azure.com/#create/sendgrid.tsg-saas-offer).

Set `superAdmins` to a comma-separated list of email addresses to make these users super admins.

To use a custom domain, [add the domain and a certificate to the Container App](https://learn.microsoft.com/en-us/azure/container-apps/custom-domains-managed-certificates) and set `applicationHostWeb` to the public URL, e.g. `https://entropy.example.com`. The URL is used in emails to build links.

The container runs with 1 CPU and 2 GiB memory by default (`containerCpu`, `containerMemory`). Both values must be one of the allowed combinations of the Consumption workload profile, e.g. 0.5/1Gi, 1/2Gi, 2/4Gi, 4/8Gi.

Additional [configuration options](https://docs.entropy-data.com/configuration) can be added as environment variables to the container in the bicep file.


Deploy from the command line
---

```
az group create --name entropy-data --location germanywestcentral

az deployment group create \
  --resource-group entropy-data \
  --template-file entropy-data-ce.bicep \
  --parameters \
    superAdmins=admin@example.com \
    smtpHost=smtp.sendgrid.net \
    smtpUsername=apikey \
    smtpPassword=xxx \
    mailFrom=support@example.com
```

To upgrade, run the deployment again with a new `containerImageUrl`. The Container App creates a new revision and switches traffic to it once the health probes pass.


Migrating from the App Service template
---

Earlier versions of this template deployed Entropy Data as an App Service web app. The App Service subnet cannot be removed while the web app is still connected to it, so delete the web app and the App Service plan first, then run the new template in the same resource group. The PostgreSQL server keeps its name and data. Provide the existing `postgresAdminPassword` as a parameter, otherwise a new password is generated and the server's administrator password is changed to it.


Development
---

Compile bicep file to Azure Resource Manager template

```
az bicep build --file entropy-data-ce.bicep --outfile entropy-data-ce.json
```

Validate the template against Azure without creating resources

```
az deployment group validate --resource-group <resource-group> --template-file entropy-data-ce.bicep
```


Get help, reporting bugs and feature requests
--

Community support is offered [in Slack in the channel #entropy-data](https://datacontract.com/slack).

Want to report a bug or request a feature? Open an [issue](https://github.com/entropy-data/entropy-data-ce/issues/new).
