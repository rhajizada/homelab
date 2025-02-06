NAME := homelab
VAR_FILE := dev.tfvars
HOMELAB_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
OUTPUT_DIR := $(HOMELAB_DIR)/output

SSH_DIR := $(OUTPUT_DIR)/ssh
DNS_SSH_KEY := $(SSH_DIR)/dns.rsa
VPN_SSH_KEY := $(SSH_DIR)/vpn.rsa

BASE_TARGETS := init plan apply destroy format deploy ssh config help
MODULE := $(firstword $(filter-out $(BASE_TARGETS),$(MAKECMDGOALS)))

.PHONY: init
## init: Initialize terraform
init:
	@if [ -z "$(MODULE)" ]; then \
		terraform -chdir=terraform init -var-file=$(VAR_FILE); \
	else \
		terraform -chdir=terraform init -target=module.$(MODULE) -var-file=$(VAR_FILE); \
	fi

.PHONY: plan
## plan: Plan terraform configuration
plan:
	@if [ -z "$(MODULE)" ]; then \
		terraform -chdir=terraform plan -var-file=$(VAR_FILE); \
	else \
		terraform -chdir=terraform plan -target=module.$(MODULE) -var-file=$(VAR_FILE); \
	fi

.PHONY: apply
## apply: Apply terraform configuration
apply:
	@if [ -z "$(MODULE)" ]; then \
		terraform -chdir=terraform apply -var-file=$(VAR_FILE); \
	else \
		terraform -chdir=terraform apply -target=module.$(MODULE) -var-file=$(VAR_FILE); \
	fi

.PHONY: destroy
## destroy: Destroy terraform configuration or specific module
destroy:
	@if [ -z "$(MODULE)" ]; then \
		terraform -chdir=terraform destroy -var-file=$(VAR_FILE); \
	else \
		terraform -chdir=terraform destroy -target=module.$(MODULE) -var-file=$(VAR_FILE); \
	fi

.PHONY: format
## format: Format terraform code
format:
	terraform -chdir=terraform fmt -recursive .

# Combined configuration target for talos, kube and vpn.
.PHONY: config
## config: Generate configuration files (talos, kube or vpn)
config:
	@if [ -z "$(MODULE)" ]; then \
		echo "Usage: make config <talos|kube|vpn>"; \
		exit 1; \
	elif [ "$(MODULE)" = "talos" ]; then \
		mkdir -p $(OUTPUT_DIR)/talos; \
		terraform -chdir=terraform output -json | jq -r .talos_client_config.value > $(OUTPUT_DIR)/talos/talosconfig; \
		echo export TALOSCONFIG=\'$(OUTPUT_DIR)/talos/talosconfig\'; \
	elif [ "$(MODULE)" = "kube" ]; then \
		mkdir -p $(OUTPUT_DIR)/kube; \
		terraform -chdir=terraform output -json | jq -r .talos_kubeconfig.value > $(OUTPUT_DIR)/kube/config; \
		echo alias kubectl=\'kubectl --kubeconfig=$(OUTPUT_DIR)/kube/config\'; \
		echo alias k9s=\'k9s --kubeconfig=$(OUTPUT_DIR)/kube/config\'; \
	elif [ "$(MODULE)" = "vpn" ]; then \
		mkdir -p $(OUTPUT_DIR)/wireguard; \
		terraform -chdir=terraform output --json wireguard_client_configuration | jq -r . > $(OUTPUT_DIR)/wireguard/homelab.conf; \
	else \
		echo "Unknown config type: $(MODULE). Valid options are: 'talos', 'kube' or 'vpn'"; \
		exit 1; \
	fi

.PHONY: ssh
## ssh: Generate SSH key and connect to specified node (vpn or dns)
ssh:
	@if [ -z "$(MODULE)" ]; then \
		echo "Usage: make ssh <vpn|dns>"; \
		exit 1; \
	elif [ "$(MODULE)" = "vpn" ]; then \
		echo "Connecting to VPN node..."; \
		mkdir -p $(SSH_DIR); \
		terraform -chdir=terraform output -json vpn_node_credentials | jq -r .ssh_private_key > $(VPN_SSH_KEY); \
		chmod 0600 $(VPN_SSH_KEY); \
		USERNAME=$$(terraform -chdir=terraform output -json vpn_node_credentials | jq -r .username); \
		IP_ADDR=$$(terraform -chdir=terraform output -json vpn_node_ip | jq -r .); \
		ssh-keygen -R $${IP_ADDR}; \
		ssh -i $(VPN_SSH_KEY) $${USERNAME}@$${IP_ADDR}; \
	elif [ "$(MODULE)" = "dns" ]; then \
		mkdir -p $(SSH_DIR); \
		terraform -chdir=terraform output -json dns_node_credentials | jq -r .ssh_private_key > $(DNS_SSH_KEY); \
		chmod 0600 $(DNS_SSH_KEY); \
		USERNAME=$$(terraform -chdir=terraform output -json dns_node_credentials | jq -r .username); \
		IP_ADDR=$$(terraform -chdir=terraform output -json dns_node_ip | jq -r .); \
		ssh-keygen -R $${IP_ADDR}; \
		ssh -i $(DNS_SSH_KEY) $${USERNAME}@$${IP_ADDR}; \
	else \
		echo "Unknown node: $(MODULE). Valid options are: 'vpn' or 'dns'"; \
		exit 1; \
	fi

.PHONY: help
## help: Show help message
help: Makefile
	@echo
	@echo " Choose a command to run in $(NAME):"
	@echo
	@sed -n 's/^##//p' $< | column -t -s ':' | sed -e 's/^/ /'
	@echo

$(MODULE):
	@:

