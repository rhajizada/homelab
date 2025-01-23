VAR_FILE := dev.tfvars


.PHONY: init
## init: Initialize terraform
init:
	terraform init


.PHONY: plan
## plan: Plan terraform configuration
plan:
	terraform plan -var-file=$(VAR_FILE)


.PHONY: apply
## apply: Apply terraform configuration
apply:
	terraform apply -var-file=$(VAR_FILE)


.PHONY: destroy
## destroy: Destrtoy terraform configuration
destroy:
	terraform destroy -var-file=$(VAR_FILE)


.PHONY: kubeconfig
## kubeconfig: Generate kubeconfig
kubeconfig:
	terraform output -json | jq -r .kubeconfig.value >> $(HOME)/.kube/config


.PHONY: help
## help: Show help message
help: Makefile
	echo
	echo " Choose a command to run in "$(NAME)":"
	echo
	sed -n 's/^##//p' $< | column -t -s ':' |  sed -e 's/^/ /'
	echo
