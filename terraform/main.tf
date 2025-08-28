terraform {
required_providers {
aws = {
source = "hashicorp/aws"
version = "6.10.0"
}
}
# Remote state storage in S3
backend "s3" {
bucket = "trendapps" # REPLACE THIS NAME
key = "devops-project/terraform.tfstate"
region = "ap-south-1"
}
}
provider "aws" {
region = "ap-south-1"
}
# --- VPC and Subnet ---
resource "aws_vpc" "project_vpc" {
cidr_block = "10.0.0.0/16"
enable_dns_support = true
enable_dns_hostnames = true
tags = {
Name = "Project-VPC"
}
}
resource "aws_subnet" "public_subnet" {
vpc_id = aws_vpc.project_vpc.id
cidr_block = "10.0.1.0/24"
availability_zone = "ap-south-1a"
map_public_ip_on_launch = true
tags = {
Name = "Project-Public-Subnet"
}
}
resource "aws_subnet" "public_subnet_2" {
vpc_id = aws_vpc.project_vpc.id
cidr_block = "10.0.2.0/24" # New CIDR block for the second subnet
availability_zone = "ap-south-1b" # Different AZ
map_public_ip_on_launch = true
tags = {
Name = "Project-Public-Subnet-2"
}
}
resource "aws_internet_gateway" "project_igw" {
vpc_id = aws_vpc.project_vpc.id
tags = {
Name = "Project-IGW"
}
}
resource "aws_route_table" "project_rt" {
vpc_id = aws_vpc.project_vpc.id
route {
cidr_block = "0.0.0.0/0"
gateway_id = aws_internet_gateway.project_igw.id
}
tags = {
Name = "Project-RouteTable"
}
}
resource "aws_route_table_association" "project_rta" {
subnet_id = aws_subnet.public_subnet.id
route_table_id = aws_route_table.project_rt.id
}
# --- Security Group for Jenkins EC2 ---
resource "aws_security_group" "jenkins_sg" {
vpc_id = aws_vpc.project_vpc.id
name = "jenkins-ec2-sg"
description = "Security group for Jenkins EC2 instance"
ingress {
from_port = 22
to_port = 22
protocol = "tcp"
cidr_blocks = ["0.0.0.0/0"]
}
ingress {
from_port = 8080
to_port = 8080
protocol = "tcp"
cidr_blocks = ["0.0.0.0/0"]
}
ingress {
from_port = 50000
to_port = 50000
protocol = "tcp"
cidr_blocks = ["0.0.0.0/0"]
}
egress {
from_port = 0
to_port = 0
protocol = "-1"
cidr_blocks = ["0.0.0.0/0"]
}
tags = {
Name = "Jenkins-EC2-SG"
}
}
# --- IAM Role for Jenkins EC2 ---
resource "aws_iam_role" "ec2_instance_profile_role" {
name = "ec2-jenkins-role"
assume_role_policy = jsonencode({
Version = "2012-10-17"
Statement = [
{
Action = "sts:AssumeRole"
Effect = "Allow"
Principal = {
Service = "ec2.amazonaws.com"
}
},
]
})
tags = {
Name = "EC2-Jenkins-Role"
}
}
resource "aws_iam_role_policy_attachment" "ec2_policy_attachment" {
role = aws_iam_role.ec2_instance_profile_role.name
policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
role = aws_iam_role.ec2_instance_profile_role.name
policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_iam_role_policy_attachment" "eks_service_policy" {
role = aws_iam_role.ec2_instance_profile_role.name
policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}
resource "aws_iam_instance_profile" "ec2_instance_profile" {
name = "ec2-jenkins-instance-profile"
role = aws_iam_role.ec2_instance_profile_role.name
}
# --- SSH Key Pair Generation ---
resource "tls_private_key" "sshkey" {
algorithm = "RSA"
rsa_bits = 4096
}
resource "local_file" "private_key" {
content = tls_private_key.sshkey.private_key_pem
filename = "${path.module}/terraform_ssh_key.pem"
file_permission = "0400"
}
resource "aws_key_pair" "generated" {
key_name = "terraform-jenkins-key"
public_key = tls_private_key.sshkey.public_key_openssh
}
# --- Jenkins EC2 Instance ---
resource "aws_instance" "jenkins_ec2" {
ami = "ami-02d26659fd82cf299" # Ubuntu Server 24.04 LTS (HVM)
instance_type = "t3.medium"
key_name = aws_key_pair.generated.key_name
subnet_id = aws_subnet.public_subnet.id
vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
associate_public_ip_address = true
iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name
user_data = <<-EOF
#!/bin/bash
sudo apt update -y
sudo apt upgrade -y
# Install Java 17
sudo apt install -y openjdk-17-jdk
# Add Jenkins repository key
curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key | sudo tee \
/usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
https://pkg.jenkins.io/debian binary/" | sudo tee \
/etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update -y
sudo apt install -y jenkins
# Install Docker
sudo apt install -y docker.io
sudo usermod -aG docker jenkins
sudo usermod -aG docker ubuntu
sudo systemctl enable docker
sudo systemctl start docker
# Start and enable Jenkins
sudo systemctl start jenkins
sudo systemctl enable jenkins
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
# Install eksctl
curl -LO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz"
tar -xzf eksctl_Linux_amd64.tar.gz
sudo mv eksctl /usr/local/bin
# Install AWS CLI
sudo apt install awscli -y
EOF
tags = {
Name = "Jenkins-EC2-Instance"
}
}
output "jenkins_public_ip" {
description = "The public IP address of the Jenkins EC2 instance"
value = aws_instance.jenkins_ec2.public_ip
}
output "ssh_private_key_path" {
description = "Path to the generated SSH private key"
value = "${path.module}/terraform_ssh_key.pem"
}