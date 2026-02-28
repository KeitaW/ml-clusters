---
name: capacity-blocks
description: Search, purchase, list, and manage EC2 Capacity Blocks for GPU reservations
user-invocable: true
---

# Capacity Blocks Management

Manage EC2 Capacity Blocks for ML GPU reservations across accounts and regions.

## Commands

### `/capacity-blocks search`
Search for available Capacity Block offerings.

**Procedure:**
1. Ask the user for: instance type (default: p5.48xlarge), instance count, duration (hours), region, and desired start date range
2. Call `aws ec2 describe-capacity-block-offerings` with the parameters:
   ```
   aws ec2 describe-capacity-block-offerings \
     --instance-type <type> \
     --instance-count <count> \
     --capacity-duration-hours <hours> \
     --region <region>
   ```
3. Format results as a table showing: Offering ID, AZ, Start Date, End Date, Price, Instance Count
4. Highlight offerings that align with the user's preferred dates

### `/capacity-blocks buy`
Purchase a Capacity Block reservation.

**Procedure:**
1. Ask the user which offering to purchase (from a previous search) or get the Capacity Block Offering ID directly
2. Confirm the purchase details: instance type, count, duration, price, and target account
3. For cross-account: assume role into the target account first
4. Execute:
   ```
   aws ec2 purchase-capacity-block \
     --capacity-block-offering-id <id> \
     --instance-platform Linux/UNIX \
     --region <region>
   ```
5. Return the Capacity Reservation ID for use in cluster configs

### `/capacity-blocks list`
List active Capacity Block reservations across accounts.

**Procedure:**
1. For each account (483026362307, 159553542841) and region (us-east-1, us-west-2):
   ```
   aws ec2 describe-capacity-reservations \
     --filters Name=capacity-reservation-type,Values=capacity-block \
     --region <region>
   ```
2. Format as a table: Account, Region, Reservation ID, Instance Type, Count, State, Start, End

### `/capacity-blocks status`
Check status and utilization of a specific Capacity Block.

**Procedure:**
1. Get the reservation ID from the user
2. Call `aws ec2 describe-capacity-reservations --capacity-reservation-ids <id>`
3. Show: State, Available Instance Count, Total Instance Count, Start/End dates
4. If active, check instance usage with `aws ec2 describe-instances --filters Name=capacity-reservation-id,Values=<id>`

### `/capacity-blocks extend`
Search for extension offerings for an expiring Capacity Block.

**Procedure:**
1. Get the current reservation ID
2. Look up its details (instance type, count, AZ)
3. Search for new offerings in the same AZ that start when the current one ends
4. Present options to the user
