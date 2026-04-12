.PHONY: help init plan apply destroy clean logs status dashboard shell redeploy smoke

help:
	@echo "Code-Server Enterprise IaC - Available Commands"
	@echo "=============================================="
	@echo ""
	@echo "Deployment:"
	@echo "  make init        - Initialize Terraform"
	@echo "  make plan        - Show deployment plan"
	@echo "  make apply       - Deploy infrastructure"
	@echo "  make destroy     - Destroy infrastructure"
	@echo ""
	@echo "Maintenance:"
	@echo "  make status      - Show deployment status"
	@echo "  make logs        - View container logs"
	@echo "  make shell       - Shell into code-server"
	@echo "  make clean       - Clean temporary files"
	@echo ""
	@echo "Monitoring:"
	@echo "  make dashboard   - Show deployment dashboard"
	@echo ""
	@echo "Examples:"
	@echo "  make plan apply  - Plan and apply"
	@echo "  make destroy     - Remove all resources"
	@echo ""

init:
	@terraform init -upgrade
	@echo "✓ Terraform initialized"

plan:
	@terraform plan -out=tfplan
	@echo "✓ Plan created"

apply: plan
	@terraform apply tfplan
	@echo "✓ Infrastructure deployed"
	@terraform output code_server_url
	@terraform output code_server_password
	@pwsh -NoProfile -File ./scripts/mandatory-redeploy.ps1
	@echo "✓ Mandatory redeploy completed"
	@pwsh -NoProfile -File ./scripts/smoke-check.ps1
	@echo "✓ Runtime smoke checks passed"

redeploy:
	@pwsh -NoProfile -File ./scripts/mandatory-redeploy.ps1
	@echo "✓ Mandatory redeploy completed"

smoke:
	@pwsh -NoProfile -File ./scripts/smoke-check.ps1
	@echo "✓ Runtime smoke checks passed"

destroy:
	@terraform destroy -auto-approve
	@echo "✓ Resources destroyed"

clean:
	@rm -rf .terraform
	@rm -f tfplan tfplan.json
	@rm -f terraform.tfstate* 
	@echo "✓ Cleaned temporary files"

status:
	@echo "Deployment Status:"
	@echo "=================="
	@docker.exe compose ps
	@echo ""
	@echo "Terraform State:"
	@terraform state list

logs:
	@docker.exe compose logs -f --tail=200

shell:
	@docker.exe exec -it code-server sh

dashboard:
	@echo "Code-Server Enterprise Dashboard"
	@echo "=================================="
	@echo ""
	@echo "Access URL:"
	@terraform output -raw code_server_url 2>/dev/null || echo "Not deployed"
	@echo ""
	@echo "Container Status:"
	@docker.exe compose ps --format "table {{.Name}}\t{{.State}}\t{{.Health}}"
	@echo ""
	@echo "Disk Usage:"
	@docker.exe volume ls | findstr code-server
	@echo ""
	@echo "Network:"
	@docker.exe network ls | findstr code-server
	@echo ""

validate:
	@terraform validate
	@echo "✓ Configuration is valid"

fmt:
	@terraform fmt -recursive
	@echo "✓ Formatted Terraform files"

state-list:
	@terraform state list

state-show:
	@terraform state show

refresh:
	@terraform refresh
	@echo "✓ State refreshed"

output:
	@terraform output

output-json:
	@terraform output -json
