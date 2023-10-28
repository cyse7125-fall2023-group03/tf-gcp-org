variable "region" {
  default = "us-east1"
}

variable "default_project_id" {
  type = string
}

variable "zone" {
  default = "us-east1-c"
}

variable "billing_account" {
  type = string
}

variable "org_id" {
  type = string   
}


variable "api_service_list" {
  type = list(string)
}

variable "sleep_time" {
  type = string
}

variable "ssh_user" {
  type = string
}

variable "service_account_credentials" {
  type = string
}

variable "my_ssh_key" {
  type = string
}
