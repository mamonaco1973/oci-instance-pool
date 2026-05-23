# CLAUDE.md — aws-autoscaling

## What This Project Does

Deploys a minimal AWS Auto Scaling Group of Apache web servers behind an
Application Load Balancer. Each instance displays its own EC2 instance
metadata (private IP, instance ID, AZ, instance type) on a styled page.
Instances are private (no public IP); outbound access via NAT Gateway.

## Commands

```bash
./apply.sh      # check env, terraform init + apply, then validate
./destroy.sh    # teardown all resources
./validate.sh   # poll ALB DNS, sample 10 /plain responses
```

## Architecture

Single Terraform phase in `01-autoscaling/`. No modules, no workspaces.

- **Region:** us-east-2
- **Instance:** t4g.micro (Graviton2 ARM) — cheapest burstable in AWS
- **LB:** Application Load Balancer (L7) — per-request routing, even distribution
- **ASG:** min 1, desired 4, max 6 across two private subnets (us-east-2a/2b)
- **Scaling:** CloudWatch CPU alarms → scale-up/scale-down policies
- **Startup:** `scripts/userdata.sh` — EC2 user data, fetches EC2 IMDS v2

## Scaling Policy

Scale-out triggers after CPU > 60% for 2 consecutive 1-minute periods.
Scale-in triggers after CPU < 60% for 60 consecutive 1-minute periods (1 hour).
The long scale-in window prevents instance removal during demos.

| Alarm    | Condition  | Periods    | Action      |
|----------|------------|------------|-------------|
| cpu-high | CPU > 60%  | 2 × 1 min  | +1 instance |
| cpu-low  | CPU < 60%  | 60 × 1 min | -1 instance |

## Validation

`validate.sh` resolves the ALB DNS from `terraform output`, polls `/plain`
until the ALB responds, then samples 10 responses. Different private IPs
across responses confirm per-request L7 load balancing is working.

## Key Files

| File | Purpose |
|------|---------|
| `01-autoscaling/lt.tf` | Launch template — instance type, user data, security group |
| `01-autoscaling/asg.tf` | ASG, scaling policies, CloudWatch alarms |
| `01-autoscaling/alb.tf` | ALB, target group, listener, health check |
| `01-autoscaling/networking.tf` | VPC, public/private subnets, IGW, NAT Gateway |
| `01-autoscaling/scripts/userdata.sh` | Cloud-init: installs Apache, fetches IMDS v2, writes HTML + /plain |
