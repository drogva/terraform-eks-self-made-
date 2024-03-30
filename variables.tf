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



