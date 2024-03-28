variable "profile" {
  type    = string
  default = "default"
}

variable "main-region" {
  type    = string
  default = "ap-northeast-2"
}


variable "cluster_name" {
  type    = string
  default = "simon-test"
}

variable "rolearn" {
  description = "Add admin role to the aws-auth configmap"
}

variable "CREDENTIAL_FILES" {
  description = "This is a path of credentials file"
  default = "/.aws/credentials"
}


variable "oidc_provider" {
  description = "The OpenID Connect identity provider (issuer URL without leading `https://`)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if `enable_irsa = true`"
  type        = string
}




################################################################################
# General Variables from root module
################################################################################


variable "env_name" {
  type    = string
}


################################################################################
# Variables from other Modules
################################################################################

variable "vpc_id" {
  description = "VPC ID which Load balancers will be  deployed in"
  type = string
}


