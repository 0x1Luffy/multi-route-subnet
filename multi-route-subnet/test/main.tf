##-----------------------------------------------------------------------------
## Place this file in your standalone test folder e.g. ~/subnet-test/main.tf
## Change the source path to point to your local cloned module.
## Tests BOTH for_all routes AND per_subnet routes at the same time.
##-----------------------------------------------------------------------------

provider "aws" {
  region = "eu-west-1"
}

locals {
  name        = "app"
  environment = "test"
}

##-----------------------------------------------------------------------------
## VPC
##-----------------------------------------------------------------------------
module "vpc" {
  source  = "clouddrove/vpc/aws"
  version = "2.0.0"

  enable      = true
  name        = local.name
  environment = local.environment

  cidr_block                          = "10.0.0.0/16"
  enable_flow_log                     = false
  create_flow_log_cloudwatch_iam_role = false
  assign_generated_ipv6_cidr_block    = false
}

##-----------------------------------------------------------------------------
## VPN Gateway — single extra resource, real route target, no second VPC needed
##-----------------------------------------------------------------------------
resource "aws_vpn_gateway" "this" {
  vpc_id = module.vpc.vpc_id

  tags = {
    Name        = "${local.name}-${local.environment}-vgw"
    Environment = local.environment
  }
}

##-----------------------------------------------------------------------------
## Subnet module
##-----------------------------------------------------------------------------
module "subnets" {
  source = "/home/luffy/work/terraform-aws-subnet"   # ← change this

  enable      = true
  name        = local.name
  environment = local.environment

  nat_gateway_enabled = true
  single_nat_gateway  = true
  availability_zones  = ["eu-west-1a", "eu-west-1b"]
  vpc_id              = module.vpc.vpc_id
  type                = "public-private"
  igw_id              = module.vpc.igw_id
  cidr_block          = module.vpc.vpc_cidr_block

  ##---------------------------------------------------------------------------
  ## TEST 1: same route added to ALL public AZs
  ## Both eu-west-1a and eu-west-1b will get this route.
  ##---------------------------------------------------------------------------
  additional_public_routes_for_all = [
    {
      destination_cidr_block = "10.100.0.0/16"
      gateway_id             = aws_vpn_gateway.this.id
    }
  ]

  ##---------------------------------------------------------------------------
  ## TEST 2: different route per specific public AZ
  ## eu-west-1a gets 192.168.1.0/24
  ## eu-west-1b gets 192.168.2.0/24
  ## These are IN ADDITION to the for_all route above.
  ##---------------------------------------------------------------------------
  additional_public_routes_per_subnet = {
    "eu-west-1a" = [
      {
        destination_cidr_block = "192.168.1.0/24"
        gateway_id             = aws_vpn_gateway.this.id
      }
    ]
    "eu-west-1b" = [
      {
        destination_cidr_block = "192.168.2.0/24"
        gateway_id             = aws_vpn_gateway.this.id
      }
    ]
  }

  ##---------------------------------------------------------------------------
  ## TEST 3: same route added to ALL private AZs
  ##---------------------------------------------------------------------------
  additional_private_routes_for_all = [
    {
      destination_cidr_block = "10.100.0.0/16"
      gateway_id             = aws_vpn_gateway.this.id
    }
  ]

  ##---------------------------------------------------------------------------
  ## TEST 4: different route per specific private AZ
  ## Only eu-west-1a gets this extra route.
  ## eu-west-1b gets nothing extra beyond for_all.
  ##---------------------------------------------------------------------------
  additional_private_routes_per_subnet = {
    "eu-west-1a" = [
      {
        destination_cidr_block = "192.168.10.0/24"
        gateway_id             = aws_vpn_gateway.this.id
      }
    ]
  }
}

##-----------------------------------------------------------------------------
## Outputs — verify in terminal after apply
##-----------------------------------------------------------------------------
output "public_route_table_ids" {
  value = module.subnets.public_route_tables_id
}

output "private_route_table_ids" {
  value = module.subnets.private_route_tables_id
}