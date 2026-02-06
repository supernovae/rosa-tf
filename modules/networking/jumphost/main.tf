#------------------------------------------------------------------------------
# Jump Host Module for ROSA Classic GovCloud
# Creates an SSM-enabled t3.micro EC2 instance for cluster access
# via port forwarding (no SSH keys or public IPs required)
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Data Sources
#------------------------------------------------------------------------------

data "aws_region" "current" {}

data "aws_partition" "current" {}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

#------------------------------------------------------------------------------
# IAM Role for SSM
#------------------------------------------------------------------------------

resource "aws_iam_role" "jumphost" {
  name = "${var.cluster_name}-jumphost-role"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-jumphost-role"
    }
  )
}

# Attach SSM managed policies
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.jumphost.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ssm_patch_manager" {
  role       = aws_iam_role.jumphost.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMPatchAssociation"
}

# Additional policy for CloudWatch Logs (optional but useful)
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "${var.cluster_name}-jumphost-cloudwatch"
  role = aws_iam_role.jumphost.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:*:*:*"
      }
    ]
  })
}

# Instance profile
resource "aws_iam_instance_profile" "jumphost" {
  name = "${var.cluster_name}-jumphost-profile"
  role = aws_iam_role.jumphost.name

  tags = var.tags
}

#------------------------------------------------------------------------------
# Security Group
#------------------------------------------------------------------------------

resource "aws_security_group" "jumphost" {
  name        = "${var.cluster_name}-jumphost-sg"
  description = "Security group for SSM jump host"
  vpc_id      = var.vpc_id

  # Allow all outbound traffic (needed for SSM and cluster access)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # No inbound rules needed - SSM uses outbound connections

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-jumphost-sg"
    }
  )
}

#------------------------------------------------------------------------------
# EC2 Instance
#------------------------------------------------------------------------------

resource "aws_instance" "jumphost" {
  ami                    = var.ami_id != null ? var.ami_id : data.aws_ami.amazon_linux_2023[0].id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.jumphost.name
  vpc_security_group_ids = [aws_security_group.jumphost.id]

  # No public IP - uses SSM for access
  associate_public_ip_address = false

  # Enable EBS optimization for improved EBS performance
  ebs_optimized = true

  # Enable detailed monitoring (1-minute intervals vs 5-minute)
  monitoring = true

  # Use IMDSv2 only for security
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Enable EBS encryption with infrastructure KMS key
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    kms_key_id            = var.kms_key_arn # Infrastructure KMS key
    delete_on_termination = true

    tags = merge(
      var.tags,
      {
        Name = "${var.cluster_name}-jumphost-root"
      }
    )
  }

  # User data script - simplified for cloud-init compatibility
  user_data = base64encode(<<-EOF
#!/bin/bash
exec > >(tee /var/log/jumphost-setup.log) 2>&1

echo "=== JUMPHOST SETUP STARTING ==="
date

# Step 1: SSM Agent
echo "=== Step 1: SSM Agent ==="
dnf install -y amazon-ssm-agent || true
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
systemctl status amazon-ssm-agent || true
echo "=== Step 1: DONE ==="

# Step 2: System update
echo "=== Step 2: System Update ==="
dnf update -y
echo "=== Step 2: DONE ==="

# Step 3: Base tools
echo "=== Step 3: Base Tools ==="
dnf install -y jq wget curl git bind-utils nmap-ncat vim tar gzip
echo "=== Step 3: DONE ==="

# Step 4: OpenShift CLI
echo "=== Step 4: OpenShift CLI ==="
cd /tmp
curl -sL https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable-4.16/openshift-client-linux.tar.gz -o oc.tar.gz
tar -xzf oc.tar.gz -C /usr/local/bin oc kubectl
chmod +x /usr/local/bin/oc /usr/local/bin/kubectl
rm -f oc.tar.gz
/usr/local/bin/oc version --client || true
echo "=== Step 4: DONE ==="

# Step 5: ROSA CLI
echo "=== Step 5: ROSA CLI ==="
cd /tmp
curl -sL https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/rosa/latest/rosa-linux.tar.gz -o rosa.tar.gz
tar -xzf rosa.tar.gz -C /usr/local/bin rosa
chmod +x /usr/local/bin/rosa
rm -f rosa.tar.gz
/usr/local/bin/rosa version || true
echo "=== Step 5: DONE ==="

# Step 6: Helper scripts with cluster info
echo "=== Step 6: Helper Scripts ==="
mkdir -p /opt/rosa-scripts

# Cluster info script
cat > /opt/rosa-scripts/cluster-info.sh << 'CLUSTERSCRIPT'
#!/bin/bash
echo "========================================"
echo "ROSA Cluster: ${var.cluster_name}"
echo "========================================"
echo "API URL:     ${var.cluster_api_url}"
echo "Console URL: ${var.cluster_console_url}"
echo "Domain:      ${var.cluster_domain}"
echo "========================================"
CLUSTERSCRIPT
chmod +x /opt/rosa-scripts/cluster-info.sh

# SSM access helper
cat > /opt/rosa-scripts/connect.sh << 'CONNECTSCRIPT'
#!/bin/bash
echo "================================================================================"
echo "ROSA CLUSTER ACCESS"
echo "================================================================================"
echo ""
echo "You're on the jumphost inside the VPC. Access cluster directly:"
echo ""
echo "  oc login https://api.${var.cluster_domain}:6443 -u cluster-admin"
echo ""
echo "  # Get password from your local machine:"
echo "  # terraform output -raw cluster_admin_password"
echo ""
echo "Useful commands:"
echo "  oc get nodes                    # List cluster nodes"
echo "  oc get clusterversion           # Check cluster version"
echo "  oc get co                       # Check cluster operators"
echo "  oc whoami --show-console        # Show console URL"
echo ""
echo "================================================================================"
CONNECTSCRIPT
chmod +x /opt/rosa-scripts/connect.sh
echo "=== Step 6: DONE ==="

# Step 7: MOTD
echo "=== Step 7: MOTD ==="
cat > /etc/motd << 'MOTDFILE'

  ROSA GovCloud Jump Host
  Cluster: ${var.cluster_name}
  Domain:  ${var.cluster_domain}
  
  Login: oc login https://api.${var.cluster_domain}:6443 -u cluster-admin
  
  Tools: oc, kubectl, rosa, jq
  Help:  /opt/rosa-scripts/connect.sh

MOTDFILE
echo "=== Step 7: DONE ==="

# Final SSM check
echo "=== FINAL: SSM Agent Status ==="
systemctl is-active amazon-ssm-agent && echo "SSM Agent: RUNNING" || echo "SSM Agent: NOT RUNNING"

echo "=== JUMPHOST SETUP COMPLETE ==="
echo "Cluster Domain: ${var.cluster_domain}"
date
  EOF
  )

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-jumphost"
    }
  )

  lifecycle {
    ignore_changes = [
      ami,
      user_data,
    ]
  }
}

#------------------------------------------------------------------------------
# CloudWatch Log Group for SSM Session Logs
# Encrypted with infrastructure KMS key
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ssm_sessions" {
  name              = "/aws/ssm/${var.cluster_name}-jumphost"
  retention_in_days = 365             # Retain logs for 1 year (security/compliance requirement)
  kms_key_id        = var.kms_key_arn # Infrastructure KMS key

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-ssm-logs"
    }
  )
}
