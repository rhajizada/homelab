NAME := homelab
VAR_FILE := dev.tfvars
VPN_SSH_KEY := $(HOME)/.ssh/vpn.rsa
DNS_SSH_KEY := $(HOME)/.ssh/dns.rsa



.PHONY: init
## init: Initialize terraform
init:
	terraform -chdir=terraform init


.PHONY: plan
## plan: Plan terraform configuration
plan:
	terraform  -chdir=terraform plan -var-file=$(VAR_FILE)


.PHONY: apply
## apply: Apply terraform configuration
apply:
	terraform -chdir=terraform apply -var-file=$(VAR_FILE)


.PHONY: destroy
## destroy: Destrtoy terraform configuration
destroy:
	terraform -chdir=terraform destroy -var-file=$(VAR_FILE)


.PHONY: kubeconfig
## kubeconfig: Generate kubeconfig
kubeconfig:
	terraform -chdir=terraform output -json | jq -r .talos_kubeconfig.value >> $(HOME)/.kube/config

.PHONY: vpn-client-config
## vpn-client-config: Generate Wireguard client configuration
vpn-client-config:
	mkdir -p data/wireguard
	terraform -chdir=terraform output --json wireguard_client_configuration | jq -r . > data/wireguard/homelab.conf


.PHONY: ssh-vpn
## ssh-vpn: Generate SSH key for VPN node
ssh-vpn:
	terraform -chdir=terraform output -json vpn_node_credentials | jq -r .ssh_private_key > $(VPN_SSH_KEY); \
	chmod 0600 $(VPN_SSH_KEY); \
	USERNAME=$$(terraform -chdir=terraform output -json vpn_node_credentials | jq -r .username); \
	IP_ADDR=$$(terraform -chdir=terraform output -json vpn_node_ip | jq -r .); \
	ssh-keygen -R $${IP_ADDR}; \
	ssh -i $(VPN_SSH_KEY) $${USERNAME}@$${IP_ADDR}


.PHONY: ssh-dns
## ssh-dns: Generate SSH key for DNS node
ssh-dns:
	terraform -chdir=terraform output -json dns_node_credentials | jq -r .ssh_private_key > $(DNS_SSH_KEY); \
	chmod 0600 $(DNS_SSH_KEY); \
	USERNAME=$$(terraform -chdir=terraform output -json dns_node_credentials | jq -r .username); \
	IP_ADDR=$$(terraform -chdir=terraform output -json dns_node_ip | jq -r .); \
	ssh-keygen -R $${IP_ADDR}; \
	ssh -i $(DNS_SSH_KEY) $${USERNAME}@$${IP_ADDR}


.PHONY: help
## help: Show help message
help: Makefile
	@echo
	@echo " Choose a command to run in "$(NAME)":"
	@echo
	@sed -n 's/^##//p' $< | column -t -s ':' |  sed -e 's/^/ /'
	@echo
