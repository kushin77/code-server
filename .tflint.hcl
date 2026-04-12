plugin "aws" {}

# Basic tflint config — extend per repo IaC needs
rule "aws_instance_invalid_type" {
  enabled = true
}
