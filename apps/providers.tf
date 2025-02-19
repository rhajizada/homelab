terraform {
  backend "s3" {
  }
  required_version = ">= 1.5.0"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.35.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.17.0"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "2024.12.1"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig
}


provider "helm" {
  kubernetes {
    config_path = var.kubeconfig
  }
}
