# tf-gcp-org
GCP Infrastructure

- In this repo, we will create a GKE cluster by accessing it via bastion Host.
- Helm Charts *.tgz will be copied from Github release into the bastion host to install helm charts and run the cluster.

# Terraform commands
- cd in to the repo directory 
- terraform init .
- terraform apply -var-file=dev.tfvars
- terraform destroy -var-file=dev.tfvars
