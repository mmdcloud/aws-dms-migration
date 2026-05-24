# -----------------------------------------------------------------------------------------
# Test Instances
# -----------------------------------------------------------------------------------------
# GCP Instance
resource "google_compute_address" "gcp_vm_ip" {
  name = "gcp-vm-public-ip"
}

module "source_test_instance" {
  source                    = "./modules/gcp/compute"
  name                      = "source-test-instance"
  machine_type              = "e2-micro"
  zone                      = "${var.source_location}-a"
  metadata_startup_script   = file("${path.module}/scripts/user_data.sh")
  deletion_protection       = false
  allow_stopping_for_update = true
  image                     = "ubuntu-os-cloud/ubuntu-2004-focal-v20220712"
  network_interfaces = [
    {
      network    = module.source_vpc.vpc_id
      subnetwork = module.source_vpc.subnets[0].id
      access_configs = [
        {
          nat_ip = google_compute_address.gcp_vm_ip.address
        }
      ]
    }
  ]
  tags = ["gcp-instance"]
}

resource "aws_iam_role" "ec2_role" {
  name = "ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_instance_profile" "destination_test_iam_instance_profile" {
  name = "destination-test-instance-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# AWS Instance
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

module "destination_test_instance" {
  source                      = "./modules/aws/ec2"
  name                        = "destination-test-instance"
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  subnet_id                   = module.destination_vpc.public_subnets[0]
  security_groups             = [module.destination_test_instance_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.destination_test_iam_instance_profile.name
  user_data                   = filebase64("${path.module}/scripts/user_data.sh")
}