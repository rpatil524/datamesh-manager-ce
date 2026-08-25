# AWS CloudFormation Templates

Two templates are available, both in this directory and in a public S3 bucket:

| Template | Runs on | S3 |
| --- | --- | --- |
| `template-ecs.yaml` | ECS Fargate behind an Application Load Balancer, RDS PostgreSQL 16 | https://entropy-data-ce.s3.us-east-1.amazonaws.com/template-ecs.yaml |
| `template.yaml` | AWS App Runner, RDS PostgreSQL | https://entropy-data-ce.s3.us-east-1.amazonaws.com/template.yaml |

Use the ECS template if App Runner is not available to you. Both use the same parameter names for image, database and SMTP settings.

## ECS Fargate (`template-ecs.yaml`)

[Quick-Create Link](https://eu-central-1.console.aws.amazon.com/cloudformation/home?region=eu-central-1#/stacks/create/review?templateURL=https://entropy-data-ce.s3.us-east-1.amazonaws.com/template-ecs.yaml)

The stack creates a VPC (two public and two private subnets, NAT gateway), an RDS PostgreSQL 16 instance with credentials generated in Secrets Manager, an ECS cluster with a Fargate service and CPU based autoscaling, an Application Load Balancer (HTTP, or HTTPS when `CertificateArn` is set) with health checks on `/actuator/health/readiness`, and a CloudWatch log group `/ecs/<ApplicationName>`.

Secrets (database credentials, SMTP password, SSO client secret) are stored in Secrets Manager and injected into the container at start.

```
aws cloudformation deploy \
  --stack-name entropy-data \
  --template-file ./template-ecs.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    ImageIdentifier=public.ecr.aws/s4e5k7s9/entropy-data-ce:latest \
    ApplicationHostWeb=https://entropy.example.com \
    CertificateArn=arn:aws:acm:eu-central-1:123456789012:certificate/... \
    SuperAdmins=admin@example.com \
    SMTPHost=email-smtp.eu-central-1.amazonaws.com \
    SMTPPort=587 \
    SMTPUsername=xxx \
    SMTPPassword=xxx \
    MailFrom=support@example.com \
  --region eu-central-1
```

Leave `ApplicationHostWeb` and `CertificateArn` empty to run on the load balancer DNS name over plain HTTP (for testing). To use a custom domain, request an ACM certificate in the stack's region, create a CNAME from your domain to the `LoadBalancerDNSName` output, and set both parameters.

To upgrade, change `ImageIdentifier` to the new tag and deploy again; ECS rolls out the new task and rolls back if it does not become healthy. Before deleting the stack, set `DBDeletionProtection=false`; the database is snapshotted on deletion.

Additional [configuration options](https://docs.entropy-data.com/configuration) can be added to the `Environment` list of the container definition.

## App Runner (`template.yaml`)

It uses the Docker Image hosted on AWS Public ECR: `public.ecr.aws/s4e5k7s9/entropy-data-ce:latest` (see more on https://gallery.ecr.aws/s4e5k7s9/entropy-data-ce).

[Quick-Create Link](https://eu-central-1.console.aws.amazon.com/cloudformation/home?region=eu-central-1#/stacks/create/review?templateURL=https://entropy-data-ce.s3.us-east-1.amazonaws.com/template.yaml)

### Constraints

Using a public image from Docker Hub in AWS AppRunner comes with many constraints on AWS.

- AppRunner does not support public images from Docker Hub, only from ECR Public.
- AppRunner does not support automated deployment from images on ECR Public.

The alternative requires a private ECR repository, which either gets the image pushed or configures a pull-through cache.
The pull-through cache always requires credentials configured in the AWS Secrets Manager, even for public docker images on Docker Hub.

Because of that, the CloudFormation template uses `public.ecr.aws/s4e5k7s9/entropy-data-ce:latest` from ECR Public. But be aware that it does not automatically upgrade to newer versions of the Entropy Data!

### Running the CloudFormation Template from CLI

```
aws cloudformation create-stack \
  --stack-name entropy-data \
  --template-body file://./template.yaml \
  --parameters \
    ParameterKey=ImageIdentifier,ParameterValue=public.ecr.aws/s4e5k7s9/entropy-data-ce:latest \
    ParameterKey=DBInstanceIdentifier,ParameterValue=entropy-data-postgres \
    ParameterKey=DBName,ParameterValue=postgres \
    ParameterKey=SuperAdmins,ParameterValue= \
    ParameterKey=SMTPHost,ParameterValue=email-smtp.eu-central-1.amazonaws.com \
    ParameterKey=SMTPPort,ParameterValue=587 \
    ParameterKey=SMTPUsername,ParameterValue=xxx \
    ParameterKey=SMTPPassword,ParameterValue=xxx \
    ParameterKey=MailFrom,ParameterValue=support@example.com \  
  --region eu-central-1
```

### Testing the CloudFormation Template

Run this manually before changing `template.yaml`. A TaskCat run deploys the whole stack — VPC, NAT
gateway, two RDS instances and an App Runner service — so it needs an account you are willing to have
stacks created in, and it bills for the duration of the test.

#### Running Taskcat

```bash
# requires AWS credentials via environment variables
uvx taskcat test run
```
