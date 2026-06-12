# 🛡️ DevSecOps Auto-Remediation Bot

An automated cloud security enforcement system that detects and instantly remediates exposed SSH ports on AWS Security Groups — with zero human intervention.

---

## 📖 Overview

This project implements a fully automated **"detect and fix"** security pipeline on AWS. The moment an open SSH rule (`0.0.0.0/0` on port 22) is detected on any Security Group, the system automatically locks it down and fires a Slack alert — all within seconds.

This is a practical demonstration of **Security as Code**: turning compliance checks into automated enforcement actions using cloud-native AWS services.

---

## 🏗️ Architecture

```
AWS Config (Detective)
    │
    │  Detects NON_COMPLIANT Security Group (open SSH)
    ▼
Amazon EventBridge (Nervous System)
    │
    │  Fires event on compliance failure
    ▼
AWS Lambda — remediate.py (The Bot)
    │
    ├──► ec2:RevokeSecurityGroupIngress  →  Removes 0.0.0.0/0:22 rule
    └──► Slack Webhook                   →  Sends alert notification
```

### Components

| Component | AWS Service | Purpose |
|---|---|---|
| **Detective** | AWS Config (`INCOMING_SSH_DISABLED`) | Continuously monitors Security Groups for open SSH |
| **Trigger** | Amazon EventBridge | Routes `NON_COMPLIANT` config events to Lambda |
| **Remediator** | AWS Lambda (Python 3.10) | Revokes the offending firewall rule via EC2 API |
| **Alerting** | Slack Webhook | Notifies the team of every auto-remediation action |
| **Audit Log** | Amazon S3 + CloudWatch Logs | Stores Config history and Lambda execution logs |
| **IaC** | Terraform | Provisions and manages all infrastructure |

---

## 📁 Project Structure

```
devsecops-remediation-bot/
├── src/
│   └── remediate.py          # Lambda handler — the core remediation bot
├── infrastructure/
│   ├── main.tf               # Lambda, Config Rule, EventBridge, permissions
│   ├── config_baseline.tf    # AWS Config recorder, S3 bucket, delivery channel
│   ├── iam.tf                # IAM roles & policies for Lambda and Config
│   └── providers.tf          # AWS provider configuration
├── .github/
│   └── workflows/
│       └── ci.yml            # Ruff → Bandit → Trivy code quality gates
├── images/                   # Project screenshots and documentation assets
└── README.md
```

---

## 🔬 CI — Code Quality & Security Gates

Every push and pull request runs three automated checks in sequence via **GitHub Actions**. Each job must pass before the next one starts.

```
push / pull_request to main
         │
         ▼
    ┌─────────┐
    │  ruff   │  ① Lint & format check — style issues and import order
    └────┬────┘
         │ needs: ruff
         ▼
    ┌─────────┐
    │  bandit │  ② Python security analysis — hardcoded secrets, unsafe calls
    └────┬────┘
         │ needs: bandit
         ▼
    ┌─────────┐
    │  trivy  │  ③ IaC & filesystem vulnerability scan — CRITICAL/HIGH CVEs
    └─────────┘
```

| Job | Tool | What it checks |
|---|---|---|
| `ruff` | [Ruff](https://docs.astral.sh/ruff/) | Python lint rules + `ruff format --check` |
| `bandit` | [Bandit](https://bandit.readthedocs.io/) | Python security vulnerabilities (`-ll -ii`) |
| `trivy` | [Trivy](https://aquasecurity.github.io/trivy/) | Filesystem CVEs + Terraform IaC misconfigs |

> All jobs run on **Node.js 24** with modern action versions (`actions/setup-python@v5`, `actions/setup-node@v4`).

---

## ⚙️ How It Works

1. **AWS Config** continuously evaluates all Security Groups against the managed rule `INCOMING_SSH_DISABLED`.
2. When a Security Group with port 22 open to `0.0.0.0/0` is found, Config marks it **NON_COMPLIANT** and emits a compliance change event.
3. **EventBridge** catches this event and immediately invokes the **Lambda function**.
4. The Lambda bot calls `ec2:RevokeSecurityGroupIngress` to remove the dangerous rule.
5. A **Slack webhook** alert is fired to notify the security team of the automated action.
6. All Lambda execution logs are captured in **CloudWatch Logs** for full auditability.

---

## 🚀 Deployment

### Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- [Terraform](https://www.terraform.io/downloads) >= 1.0
- Python 3.10+
- An AWS account with permissions to create Lambda, IAM, Config, EventBridge, and S3 resources

### Setup

**1. Clone the repository**
```bash
git clone https://github.com/your-username/devsecops-remediation-bot.git
cd devsecops-remediation-bot
```

**2. (Optional) Configure Slack alerting**

Export your Slack Incoming Webhook URL as a Lambda environment variable. You can add this to the Lambda resource in `main.tf`:

```hcl
environment {
  variables = {
    SLACK_WEBHOOK_URL = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
  }
}
```

**3. Deploy the infrastructure**
```bash
cd infrastructure
terraform init
terraform plan
terraform apply
```

Terraform will provision:
- An S3 bucket for AWS Config history
- IAM roles for both Config and Lambda
- AWS Config recorder and delivery channel
- The `restricted-ssh` Config Rule
- The Lambda function (auto-packaged from `src/remediate.py`)
- An EventBridge rule wired to trigger Lambda on compliance failures

---

## 🧪 Testing the Pipeline

To verify the system works end-to-end:

**1. Create a test Security Group with an open SSH rule**
```bash
# Get your default VPC ID
aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text

# Create a test security group
aws ec2 create-security-group \
  --group-name "test-open-ssh" \
  --description "Deliberately insecure SG for testing"

# Add the offending rule
aws ec2 authorize-security-group-ingress \
  --group-id <YOUR_GROUP_ID> \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0
```

**2. Check AWS Config compliance status**
```bash
aws configservice describe-compliance-by-config-rule \
  --config-rule-names restricted-ssh
```

AWS Config will flag the rule as `NON_COMPLIANT`, triggering the full remediation pipeline automatically.

**3. Verify the Lambda logs**

Check CloudWatch Logs under `/aws/lambda/devsecops-sg-remediator` to confirm the bot executed and revoked the rule.

---

## 🔒 IAM Permissions

The Lambda function operates under the **principle of least privilege**, with only the specific permissions it needs:

| Permission | Reason |
|---|---|
| `ec2:RevokeSecurityGroupIngress` | Remove the dangerous firewall rule |
| `ec2:DescribeSecurityGroups` | Inspect current SG state |
| `logs:CreateLogGroup/Stream/PutLogEvents` | Write execution logs to CloudWatch |

---

## 📸 Demo

### 1️⃣ AWS Config — NON_COMPLIANT Detection

The `restricted-ssh` Config Rule detects the exposed Security Group and flags it as `NON_COMPLIANT`:

![AWS Config detecting a NON_COMPLIANT security group with open SSH](images/Screenshot%202026-06-12%20at%2001.36.12.png)

---

### 2️⃣ CloudWatch Logs — Lambda Function Deployed

The Lambda log group `/aws/lambda/devsecops-sg-remediator` is created and active, confirming the bot was successfully deployed:

![CloudWatch Log Groups showing the devsecops-sg-remediator Lambda log group](images/Screenshot%202026-06-12%20at%2001.36.33.png)

---

### 3️⃣ CloudWatch Log Events — Successful Auto-Remediation

The Lambda execution logs confirm the full pipeline running: the bot detected the exposed Security Group, then immediately locked it down:

> `CRITICAL: Exposed SSH detected on Security Group sg-0e392c1e26eb94479. Initiating auto-remediation...`
> `SUCCESS: Port 22 successfully locked down on sg-0e392c1e26eb94479.`

![CloudWatch Log Events showing successful auto-remediation with CRITICAL detection and SUCCESS lock down messages](images/Screenshot%202026-06-12%20at%2001.48.12.png)

---

## 🛠️ Tech Stack

- **Language**: Python 3.10
- **Cloud**: Amazon Web Services (AWS)
- **Infrastructure as Code**: Terraform
- **CI/CD**: GitHub Actions
- **Security Scanning**: Bandit, Ruff
- **Alerting**: Slack Incoming Webhooks

---

## 📄 License

This project is open source and available under the [MIT License](LICENSE).
