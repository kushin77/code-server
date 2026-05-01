/**
 * @file modules/stack/versions.tf
 * @description Provider requirements for the stack module.
 *              Must explicitly declare kreuzwerker/docker so Terraform
 *              does not default to hashicorp/docker when the module is called.
 */

terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "= 3.0.2"
    }
  }
}
