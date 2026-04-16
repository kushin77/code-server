# tflint configuration for code-server-enterprise Terraform (hashicorp/local + null providers)
# No kreuzwerker/docker plugin exists for tflint — basic ruleset is sufficient.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}
