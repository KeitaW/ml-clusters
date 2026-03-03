# Training Plans Management

Manage SageMaker Training Plans for ML GPU capacity reservations.

## Context
- Main account: 483026362307, region: us-east-1
- Secondary account (159553542841) is not yet configured for cross-account access — skip it if role assumption fails
- User arguments are passed as: $ARGUMENTS

## Sub-commands

Parse the first word of $ARGUMENTS to determine the sub-command:

### `search` (default if no sub-command)
Search for available Training Plan offerings.

1. Parse arguments for: instance type (default: ml.p5.48xlarge), instance count (default: 8), duration in hours (default: 168), region (default: us-east-1)
2. Run via the AWS MCP tool or Bash:
   ```
   aws sagemaker search-training-plan-offerings \
     --instance-type <type> \
     --instance-count <count> \
     --duration-hours <hours> \
     --region <region>
   ```
3. Format results as a table: Offering ID, Instance Type, Count, Duration, Price, Upfront Cost, Available Start Dates

### `buy`
Purchase a Training Plan.

1. Get the Training Plan Offering ID from the user (from a previous search)
2. Ask for a plan name
3. Confirm details with the user before executing
4. Run:
   ```
   aws sagemaker create-training-plan \
     --training-plan-offering-id <id> \
     --training-plan-name <name> \
     --region <region>
   ```
5. Return the Training Plan ARN

### `list`
List Training Plans.

1. Query the main account:
   ```
   aws sagemaker list-training-plans --region us-east-1
   ```
2. Format as table: Plan Name, ARN, Status, Instance Type, Count, Start, End

### `status`
Check detailed status of a Training Plan.

1. Get the Training Plan name or ARN from the user
2. Run: `aws sagemaker describe-training-plan --training-plan-name <name>`
3. Show: Status, Instance Type, Count, Reserved Hours Used/Total, Start/End, Associated Clusters
