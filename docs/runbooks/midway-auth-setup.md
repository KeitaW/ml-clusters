# Midway Authentication Setup Runbook

Deployment runbook for securing EKS-hosted services (ArgoCD, Atlantis) with Midway authentication via ALB + Cognito + Amazon Federate.

**Account**: 483026362307 (`mlkeita@amazon.co.jp`)
**Region**: us-east-1
**EKS Cluster**: ml-cluster-main-us-east-1
**Domain**: mlkeita.people.aws.dev

## Architecture Overview

```
Internet --> ALB (shared via IngressGroup "ml-cluster-services")
               |
               +--> argocd.mlkeita.people.aws.dev
               |      Auth: Cognito --> Federate --> Midway
               |      Backend: ArgoCD (ClusterIP)
               |
               +--> atlantis.mlkeita.people.aws.dev
                      /events: No auth (GitHub webhooks, group.order=10)
                      /*:      Cognito auth (group.order=20)
                      Backend: Atlantis (ClusterIP)
```

The ALB is provisioned by the AWS Load Balancer Controller via Kubernetes Ingress annotations. Terraform manages Cognito, ACM, and Route53. External-dns auto-creates Route53 records from Ingress hostnames.

## Prerequisites Checklist

Before deploying, complete these manual steps in order:

- [ ] Step 1: Create Nova IAM role
- [ ] Step 2: Register domain via SuperNova
- [ ] Step 3: Create Federate service profile
- [ ] Step 4: Create external-dns IRSA role
- [ ] Step 5: Create ALB controller IRSA role
- [ ] Step 6: Tag subnets for ALB auto-discovery
- [ ] Step 7: Update external-dns placeholder in gitops

---

## Step 1: Create the Nova IAM Role

SuperNova requires an IAM role named `Nova-DO-NOT-DELETE` in your account to verify domain ownership and manage Route53 records.

### 1.1 Get the exact trust policy from SuperNova

1. Go to **https://supernova.amazon.dev/**
2. Start the domain registration flow (Step 2 below)
3. SuperNova will display the **exact IAM role trust policy JSON** you need, including the correct principal ARN
4. **Copy that JSON directly** — do not use a template, as the trust principal format may change over time

### 1.2 Create the role in IAM

Open the [IAM Console](https://us-east-1.console.aws.amazon.com/iam/home?region=us-east-1#/roles) in account 483026362307.

Click **Create role** → **Custom trust policy** → paste the trust policy JSON from SuperNova.

Click **Next**.

### 1.3 Attach policies

Search and attach these two AWS managed policies:

1. `SecurityAudit`
2. `AmazonRoute53FullAccess`

### 1.4 Name the role

- Role name: **`Nova-DO-NOT-DELETE`** (exact name required by SuperNova)
- Click **Create role**

### 1.5 Verify

```bash
aws iam get-role --role-name Nova-DO-NOT-DELETE --query 'Role.Arn'
# Expected: arn:aws:iam::483026362307:role/Nova-DO-NOT-DELETE
```

### 1.6 Return to SuperNova

Go back to the SuperNova domain registration page and continue — it will now detect the role.

---

## Step 2: Register Domain via SuperNova

SuperNova is Amazon's internal domain registration service. It creates a Route53 hosted zone in your account automatically.

### 2.1 Open SuperNova

Go to **https://supernova.amazon.dev/**

### 2.2 Register the domain

1. Click **Domains** in the left navigation
2. Click **Register a Domain**
3. Select domain type: **people.aws.dev** (personal domains for Amazon employees)
4. Enter your alias: **mlkeita**
   - This creates the domain: `mlkeita.people.aws.dev`
5. Select AWS account: **483026362307**
6. Select region: **us-east-1** (for the Route53 hosted zone)
7. SuperNova will verify the Nova IAM role (created in Step 1) and create the Route53 hosted zone

### 2.3 Wait for provisioning

Domain provisioning typically takes 5–15 minutes. SuperNova will send a notification when complete.

### 2.4 Verify the hosted zone

```bash
aws route53 list-hosted-zones-by-name \
  --dns-name mlkeita.people.aws.dev \
  --query 'HostedZones[0].{Id:Id,Name:Name}' \
  --output table
```

Expected output:
```
------------------------------------------------------
|                  ListHostedZonesByName               |
+------+----------------------------------------------+
|  Id  |  /hostedzone/Z0123456789ABCDEFGHIJ           |
|  Name|  mlkeita.people.aws.dev.                     |
+------+----------------------------------------------+
```

Record the **Zone ID** (the part after `/hostedzone/`). You will need it in Step 4.

### 2.5 Verify name server delegation

```bash
dig NS mlkeita.people.aws.dev +short
```

You should see 4 AWS name servers (e.g., `ns-123.awsdns-45.com`). If these don't resolve yet, wait a few more minutes for DNS propagation.

---

## Step 3: Create a Federate Service Profile

Amazon Federate bridges Cognito to Midway via OIDC. This step requires the Federate web UI.

### 3.1 Open Federate

Go to **https://ep.federate.a2z.com/draft**

### 3.2 Create new service profile

1. Click **Questionnaire Based Onboarding**
2. **Protocol**: Select **OIDC**
3. **Use Case**: Select **Pre-Approved Use Cases** → **Federate-Cognito Integration**

### 3.3 Configure OIDC details

Fill in the following fields:

| Field | Value |
|-------|-------|
| **Redirect URI** | `https://ml-clusters-mlkeita.auth.us-east-1.amazoncognito.com/oauth2/idpresponse` |
| **Client Secret** | Enable (check the box) |
| **PKCE Enabled** | **Disable** (uncheck the box) |

The redirect URI follows the pattern: `https://{cognito_domain_prefix}.auth.{region}.amazoncognito.com/oauth2/idpresponse`

Where:
- `cognito_domain_prefix` = `ml-clusters-mlkeita` (from `live/main-account/us-east-1/midway-auth/terragrunt.hcl`)
- `region` = `us-east-1`

**Important**: PKCE must be **disabled**. AWS Cognito does not send `code_challenge` parameters when acting as an OIDC client to upstream IdPs. If PKCE is enabled, Federate will reject the callback from Midway with `invalid_request` (400). The client secret provides sufficient security for confidential clients (RFC 6749 §2.1).

### 3.4 Configure discovery

- Select **Midway** as the discovery method
- (Optional) Under **Permissions**, restrict access by POSIX group, ANT team, or LDAP group

### 3.5 Configure claims

- Accept the defaults (email, sub, profile)

### 3.6 Save and record credentials

After saving the service profile:

1. **Copy the Client ID** — displayed on the profile summary page
2. **Copy the Client Secret** — displayed **only once** immediately after creation

**Store these securely.** You will need them as Terraform environment variables:

```bash
export TF_VAR_federate_client_id="<paste-client-id-here>"
export TF_VAR_federate_client_secret="<paste-client-secret-here>"
```

If you lose the client secret, you must create a new Federate service profile.

### 3.7 Note the OIDC issuer URL

The standard Amazon Federate issuer URL is:

```
https://idp.federate.amazon.com
```

This is already configured as the default in `modules/midway-auth/variables.tf`. No action needed unless your Federate profile uses a different issuer.

---

## Step 4: Create the External-DNS IRSA Role

The external-dns controller running on EKS needs IAM permissions to manage Route53 records. This uses IRSA (IAM Roles for Service Accounts) via the EKS cluster's OIDC provider.

### 4.1 Get the EKS OIDC provider URL

```bash
OIDC_PROVIDER=$(aws eks describe-cluster \
  --name ml-cluster-main-us-east-1 \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed 's|https://||')

echo "OIDC Provider: $OIDC_PROVIDER"
# Expected: oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE
```

### 4.2 Get the Route53 hosted zone ID

```bash
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name mlkeita.people.aws.dev \
  --query "HostedZones[0].Id" \
  --output text | sed 's|/hostedzone/||')

echo "Zone ID: $ZONE_ID"
```

### 4.3 Create the IAM policy

```bash
cat > /tmp/external-dns-policy.json << 'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/ZONE_ID_PLACEHOLDER"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResource"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
POLICY

# Replace placeholder with actual zone ID
sed -i "s/ZONE_ID_PLACEHOLDER/$ZONE_ID/" /tmp/external-dns-policy.json

aws iam create-policy \
  --policy-name ExternalDNSPolicy \
  --policy-document file:///tmp/external-dns-policy.json \
  --description "Allows external-dns to manage Route53 records for mlkeita.people.aws.dev"
```

### 4.4 Create the IRSA role

```bash
ACCOUNT_ID=483026362307

cat > /tmp/external-dns-trust.json << TRUST
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:kube-system:external-dns",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
TRUST

aws iam create-role \
  --role-name ExternalDNSRole \
  --assume-role-policy-document file:///tmp/external-dns-trust.json \
  --description "IRSA role for external-dns controller on EKS"

aws iam attach-role-policy \
  --role-name ExternalDNSRole \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/ExternalDNSPolicy"
```

### 4.5 Verify the role

```bash
aws iam get-role --role-name ExternalDNSRole --query 'Role.Arn'
# Expected: arn:aws:iam::483026362307:role/ExternalDNSRole
```

---

## Step 5: Create the ALB Controller IRSA Role

The AWS Load Balancer Controller needs IAM permissions to create ALBs, target groups, and manage security groups. Without IRSA, it falls back to EC2 instance metadata which may not be available.

### 5.1 Download the upstream IAM policy

```bash
curl -sL https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json \
  -o /tmp/alb-iam-policy.json
```

### 5.2 Create the IAM policy

```bash
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file:///tmp/alb-iam-policy.json \
  --description "IAM policy for AWS Load Balancer Controller v2.11.0"
```

### 5.3 Create the IRSA role

```bash
ACCOUNT_ID=483026362307
OIDC_PROVIDER=$(aws eks describe-cluster \
  --name ml-cluster-main-us-east-1 \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed 's|https://||')

cat > /tmp/alb-trust-policy.json << TRUST
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }
  ]
}
TRUST

aws iam create-role \
  --role-name AWSLoadBalancerControllerRole \
  --assume-role-policy-document file:///tmp/alb-trust-policy.json \
  --description "IRSA role for AWS Load Balancer Controller on EKS"

aws iam attach-role-policy \
  --role-name AWSLoadBalancerControllerRole \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
```

### 5.4 Annotate the service account

After installing the ALB controller via Helm, annotate its service account:

```bash
kubectl annotate serviceaccount -n kube-system aws-load-balancer-controller \
  eks.amazonaws.com/role-arn=arn:aws:iam::483026362307:role/AWSLoadBalancerControllerRole

kubectl rollout restart deployment -n kube-system aws-load-balancer-controller
```

---

## Step 6: Tag Subnets for ALB Auto-Discovery

The ALB controller uses subnet tags to discover where to place the ALB. Without these tags, it fails with `couldn't auto-discover subnets`.

### 6.1 Tag public subnets

Public subnets (with internet gateway routes) need `kubernetes.io/role/elb=1`:

```bash
# Find public subnets in the VPC
VPC_ID=vpc-02809940b6e2aa557

# Tag public subnets
aws ec2 create-tags \
  --resources subnet-0b8d375e4475cfead subnet-0841a88eacb5a039f \
  --tags Key=kubernetes.io/role/elb,Value=1
```

### 6.2 Tag private subnets (optional, for internal load balancers)

```bash
aws ec2 create-tags \
  --resources subnet-0f4105bb59e3c0e39 subnet-0d23000c7357fa612 \
  --tags Key=kubernetes.io/role/internal-elb,Value=1
```

### 6.3 Verify

```bash
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "Subnets[*].{SubnetId:SubnetId,Tags:Tags[?Key=='kubernetes.io/role/elb'].Value|[0]}" \
  --output table
```

---

## Step 7: Update External-DNS GitOps Config

Replace the placeholder in the external-dns ArgoCD application manifest.

### 5.1 Edit the file

Open `gitops/add-ons/external-dns.yaml` and replace:

```
EXTERNAL_DNS_ROLE_ARN_PLACEHOLDER
```

with the actual role ARN:

```
arn:aws:iam::483026362307:role/ExternalDNSRole
```

### 5.2 Commit the change

This change should be committed to the repository so ArgoCD can sync it.

---

## Deployment Sequence

After completing all prerequisites above, deploy in this order:

### Deploy 1: Midway-Auth Module

This creates the Cognito User Pool, OIDC Identity Provider, ACM certificate, and Route53 validation records.

```bash
# Set Federate credentials
export TF_VAR_federate_client_id="<your-client-id>"
export TF_VAR_federate_client_secret="<your-client-secret>"

cd /mnt/fsx/ubuntu/workspace/projects/ml-clusters/ml-clusters/live/main-account/us-east-1/midway-auth
terragrunt plan
terragrunt apply
```

**Expected resources created**:
- Route53 DNS validation records for ACM
- ACM certificate (waits for DNS validation — may take 5–30 minutes)
- Cognito User Pool (`ml-clusters-auth`)
- Cognito OIDC Identity Provider (`AmazonFederate`)
- Cognito User Pool Domain (`ml-clusters-mlkeita`)
- Cognito App Clients: `argocd`, `atlantis`

**Verify ACM certificate is issued**:
```bash
aws acm list-certificates \
  --query "CertificateSummaryList[?DomainName=='mlkeita.people.aws.dev'].{Domain:DomainName,Status:Status}" \
  --output table
# Status should be ISSUED (may take a few minutes after apply)
```

**Verify Cognito User Pool**:
```bash
aws cognito-idp list-user-pools --max-results 10 \
  --query "UserPools[?Name=='ml-clusters-auth'].{Id:Id,Name:Name}" \
  --output table
```

### Deploy 2: ArgoCD (Redeploy with Ingress + Cognito Auth)

This switches ArgoCD from LoadBalancer service to ClusterIP with ALB Ingress and Cognito authentication.

**Important**: This will delete the existing Classic ELB and create an ALB instead. ArgoCD will be briefly unreachable during the transition.

```bash
cd /mnt/fsx/ubuntu/workspace/projects/ml-clusters/ml-clusters/live/main-account/us-east-1/argocd
terragrunt plan
terragrunt apply
```

**Expected changes**:
- ArgoCD server service type: `LoadBalancer` → `ClusterIP`
- New: Kubernetes Ingress resource with ALB annotations + Cognito auth
- Classic ELB is removed (no longer needed)
- ALB is created by AWS Load Balancer Controller via IngressGroup

### Deploy 3: Atlantis (Add Cognito Auth)

This adds the authenticated catch-all ingress alongside the existing webhook ingress.

```bash
cd /mnt/fsx/ubuntu/workspace/projects/ml-clusters/ml-clusters/live/main-account/us-east-1/atlantis
terragrunt plan
terragrunt apply
```

**Expected changes**:
- Existing ingress: adds `certificate-arn`, `group.name`, `group.order=10` annotations
- New: `atlantis-authenticated` Ingress resource with Cognito auth and `group.order=20`
- Both ingresses share the same ALB via IngressGroup `ml-cluster-services`

### Deploy 4: External-DNS (via ArgoCD sync)

If ArgoCD is running and syncing, external-dns will deploy automatically from the gitops manifest. If ArgoCD is not yet syncing the add-ons, apply manually:

```bash
kubectl apply -f /mnt/fsx/ubuntu/workspace/projects/ml-clusters/ml-clusters/gitops/add-ons/external-dns.yaml
```

---

## Verification

### Check 1: All Ingress resources share the same ALB

```bash
kubectl get ingress -A -o wide
```

All ingresses with `group.name: ml-cluster-services` should show the same `ADDRESS` (ALB DNS name).

### Check 2: DNS resolution

```bash
dig argocd.mlkeita.people.aws.dev +short
dig atlantis.mlkeita.people.aws.dev +short
```

Both should resolve to the ALB IP addresses. If not, wait for external-dns to sync (check its logs):

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns --tail=50
```

### Check 3: ArgoCD redirects to Midway

```bash
curl -sI https://argocd.mlkeita.people.aws.dev 2>&1 | head -5
```

Expected: `HTTP/2 302` with `Location` header pointing to Cognito hosted UI.

### Check 4: Atlantis webhook path is unauthenticated

```bash
curl -sI https://atlantis.mlkeita.people.aws.dev/events 2>&1 | head -5
```

Expected: `HTTP/2 200` or `HTTP/2 405` (method not allowed for GET, but not 302). The key is it should NOT redirect to Cognito.

### Check 5: Atlantis UI requires authentication

```bash
curl -sI https://atlantis.mlkeita.people.aws.dev/ 2>&1 | head -5
```

Expected: `HTTP/2 302` with `Location` header pointing to Cognito.

### Check 6: Full authentication flow

1. Open `https://argocd.mlkeita.people.aws.dev` in a browser
2. You should be redirected through: ALB → Cognito → Federate → Midway login
3. Authenticate with your Amazon credentials + YubiKey
4. You should be redirected back to the ArgoCD dashboard

### Check 7: Update GitHub webhook URL

After deployment, update the GitHub webhook for the `ml-clusters` repo:

1. Go to **https://github.com/KeitaW/ml-clusters/settings/hooks**
2. Edit the existing webhook (or create new)
3. Set **Payload URL** to: `https://atlantis.mlkeita.people.aws.dev/events`
4. Set **Content type** to: `application/json`
5. Set **Secret** to the webhook secret from Secrets Manager:
   ```bash
   aws secretsmanager get-secret-value \
     --secret-id atlantis/github-credentials \
     --query 'SecretString' --output text | jq -r '.ATLANTIS_GH_WEBHOOK_SECRET'
   ```
6. Select events: **Pull requests** and **Pushes** (or **Send me everything**)
7. Click **Update webhook**
8. Verify delivery: push a test commit and check the **Recent Deliveries** tab for a 200 response

---

## Troubleshooting

### ACM certificate stuck in PENDING_VALIDATION

The ACM certificate requires DNS validation records in Route53. Verify:

```bash
# Check certificate status
aws acm describe-certificate \
  --certificate-arn $(terragrunt output -raw acm_certificate_arn) \
  --query 'Certificate.DomainValidationOptions'

# Check if validation CNAME records exist in Route53
aws route53 list-resource-record-sets \
  --hosted-zone-id $(aws route53 list-hosted-zones-by-name \
    --dns-name mlkeita.people.aws.dev \
    --query 'HostedZones[0].Id' --output text) \
  --query "ResourceRecordSets[?Type=='CNAME']"
```

If validation records are missing, re-run `terragrunt apply` on the midway-auth module.

### ALB not created after Ingress apply

Check that the AWS Load Balancer Controller is running:

```bash
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50
```

Common issues:
- **No IRSA role**: Controller logs show `no EC2 IMDS role found`. See Step 5 to create the IRSA role and annotate the service account.
- **Missing subnet tags**: Controller logs show `couldn't auto-discover subnets: unable to resolve at least one subnet (0 match VPC and tags: [kubernetes.io/role/elb])`. See Step 6 to tag subnets.
- Controller missing IAM permissions for `cognito-idp:DescribeUserPoolClient`
- Ingress class annotation mismatch
- Certificate ARN invalid or not in ISSUED state

### External-DNS not creating Route53 records

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=external-dns --tail=100
```

Common issues:
- IRSA role not correctly associated (check service account annotations)
- Route53 zone ID not matching the domain filter
- Policy missing `route53:ChangeResourceRecordSets` for the correct zone

### Federate returns "invalid_request" (400)

```json
{"error": "invalid_request", "error_description": "Invalid request", "status": 400}
```

This error occurs at Federate's `/api/v1/intermediate` endpoint after Midway authenticates the user. The most common cause is **PKCE being enabled** on the Federate service profile.

**Fix**: Go to [ep.federate.a2z.com](https://ep.federate.a2z.com/profile/ml-clusters-mlkeita), edit the profile, and set **PKCE Enabled** to `false`. AWS Cognito does not send `code_challenge` parameters to upstream OIDC IdPs, so PKCE must be disabled.

You can verify the profile configuration via:
```
https://ep.federate.a2z.com/serviceprofile_microservice/v1/serviceProfiles/<client-id>
```
Check that `pkceRequired` is `false`.

### Cognito login shows "error_description=unauthorized"

This usually means the Federate OIDC provider is misconfigured. Verify:

1. The redirect URI in Federate matches exactly: `https://ml-clusters-mlkeita.auth.us-east-1.amazoncognito.com/oauth2/idpresponse`
2. The Client ID and Client Secret in Terraform match the Federate service profile
3. The Cognito identity provider name matches `AmazonFederate` (case-sensitive)

### Atlantis webhooks returning 403 or 302

If GitHub webhook deliveries fail:

1. Check that the `/events` ingress has NO auth annotations:
   ```bash
   kubectl get ingress -n atlantis -o yaml | grep -A 20 "auth-type"
   ```
2. Verify the `/events` path ingress has a lower `group.order` (10) than the authenticated ingress (20)
3. Check ALB listener rules in the AWS Console → EC2 → Load Balancers → select ALB → Listeners → View/edit rules

---

## Rollback

If issues occur, disable Cognito auth without removing the midway-auth infrastructure:

### Quick rollback: Disable auth on ArgoCD

In `live/main-account/us-east-1/argocd/terragrunt.hcl`, set:

```hcl
enable_cognito_auth = false
```

Then `terragrunt apply`. This reverts ArgoCD to a ClusterIP service with no ingress. To restore full public access, also change `server.service.type` back to `"LoadBalancer"` in the module.

### Quick rollback: Disable auth on Atlantis

In `live/main-account/us-east-1/atlantis/terragrunt.hcl`, set:

```hcl
enable_cognito_auth = false
```

Then `terragrunt apply`. This removes the authenticated ingress while keeping the webhook ingress.

### Full rollback

To remove all Midway auth infrastructure:

```bash
cd live/main-account/us-east-1/midway-auth
terragrunt destroy
```

This removes the Cognito User Pool, ACM certificate, and Route53 validation records. The ArgoCD and Atlantis modules will continue to work with `enable_cognito_auth = false`.

---

## Reference Links

| Resource | URL |
|----------|-----|
| SuperNova (domain registration) | https://supernova.amazon.dev/ |
| Federate (OIDC service profile) | https://ep.federate.a2z.com/draft |
| DyePack remediation guide | https://w.amazon.com/bin/view/AWS_IT_Security/Security_Automation_Integrators/DyePack/Plugins/Details/EC2IPAuthentication |
| Midway in NAWS | https://w.amazon.com/bin/view/NextGenMidway/UserGuide/ServiceIntegration/MidwayInNAWS/ |
| MidwayAuthNDemoCDK reference | https://code.amazon.com/packages/MidwayAuthNDemoCDK |
| ALB Cognito auth docs | https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-authenticate-users.html |
| External-DNS Helm chart | https://kubernetes-sigs.github.io/external-dns |
| DyePack Support Slack | https://amazon.enterprise.slack.com/archives/C01CBUL3XTN |
