---
name: training-plans
description: Search, purchase, list, and manage SageMaker Training Plans for GPU reservations
user-invocable: true
---

# Training Plans Management

Manage SageMaker Training Plans for ML GPU capacity reservations.

## Commands

### `/training-plans search`
Search for available Training Plan offerings.

**Procedure:**
1. Ask the user for: instance type (e.g., ml.p5.48xlarge), instance count, duration, and region
2. Call:
   ```
   aws sagemaker search-training-plan-offerings \
     --instance-type <type> \
     --instance-count <count> \
     --duration-hours <hours> \
     --region <region>
   ```
3. Format results showing: Offering ID, Instance Type, Count, Duration, Price, Upfront Cost, Available Start Dates

### `/training-plans buy`
Purchase a Training Plan.

**Procedure:**
1. Get the Training Plan Offering ID from user (from a previous search)
2. Confirm details: instance type, count, duration, pricing
3. For cross-account purchases, assume role into the target account
4. Execute:
   ```
   aws sagemaker create-training-plan \
     --training-plan-offering-id <id> \
     --training-plan-name <user-specified-name> \
     --region <region>
   ```
5. Return the Training Plan ARN

### `/training-plans list`
List Training Plans across accounts.

**Procedure:**
1. For each account and region:
   ```
   aws sagemaker list-training-plans --region <region>
   ```
2. Format as table: Account, Region, Plan Name, ARN, Status, Instance Type, Count, Start, End

### `/training-plans status`
Check detailed status of a Training Plan.

**Procedure:**
1. Get the Training Plan name or ARN
2. Call `aws sagemaker describe-training-plan --training-plan-name <name>`
3. Show: Status, Instance Type, Count, Reserved Hours Used/Total, Start/End, Associated Clusters
