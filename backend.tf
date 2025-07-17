terraform {
  backend "s3" {
    bucket  = "theo-projects" # Replace with your actual bucket name
    key     = "rke2-tf/terraform.tfstate"
    region  = "us-east-1"
  }
}
