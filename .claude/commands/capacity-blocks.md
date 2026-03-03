# Capacity Blocks Management

Manage EC2 Capacity Blocks for ML GPU reservations.

## Context
- Main account: 483026362307, region: us-east-1
- ParallelCluster compute subnet is in us-east-1a — Capacity Blocks MUST be purchased in the same AZ
- Secondary account (159553542841) is not yet configured for cross-account access — skip it if role assumption fails
- User arguments are passed as: $ARGUMENTS

## Sub-commands

Parse the first word of $ARGUMENTS to determine the sub-command:

### `search` (default if no sub-command)
Search for available Capacity Block offerings.

1. Parse arguments for: instance type (default: p5.48xlarge), instance count (default: 8), duration in hours (default: 168 = 7 days), region (default: us-east-1)
2. Run via the AWS MCP tool or Bash:
   ```
   aws ec2 describe-capacity-block-offerings \
     --instance-type <type> \
     --instance-count <count> \
     --capacity-duration-hours <hours> \
     --region <region>
   ```
3. Format results as a table: Offering ID, AZ, Start Date, End Date, Price, Instance Count
4. Flag any offerings NOT in us-east-1a (incompatible with ParallelCluster compute subnet)

### `buy`
Purchase a Capacity Block reservation.

1. Get the Capacity Block Offering ID from the user (from a previous search)
2. Confirm purchase details with the user before executing
3. Run:
   ```
   aws ec2 purchase-capacity-block \
     --capacity-block-offering-id <id> \
     --instance-platform Linux/UNIX \
     --region <region>
   ```
4. Return the Capacity Reservation ID
5. Remind the user to update `cluster-configs/parallelcluster/training-cluster.yaml` with the reservation ID

### `list`
List active Capacity Block reservations.

1. Query the main account:
   ```
   aws ec2 describe-capacity-reservations \
     --filters Name=reservation-type,Values=capacity-block \
     --region us-east-1
   ```
2. Format as table: Reservation ID, Instance Type, Count, State, AZ, Start, End

### `status`
Check status of a specific Capacity Block.

1. Get the reservation ID from the user
2. Run: `aws ec2 describe-capacity-reservations --capacity-reservation-ids <id>`
3. Show: State, Available Instance Count, Total Instance Count, Start/End dates
4. If active, check usage: `aws ec2 describe-instances --filters Name=capacity-reservation-id,Values=<id>`

### `extend`
Search for extension offerings for an expiring Capacity Block.

1. Get the current reservation ID and look up its details
2. Search for new offerings in the same AZ that start when the current one ends
3. Present options to the user
