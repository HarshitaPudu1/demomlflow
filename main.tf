terraform {
  required_version = ">= 1.3.1"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.33.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

variable "prefix" {
  type        = string
  default     = "demo"
  description = "description"
}


data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}Azure-Functions"
  location = "East US"
}

resource "azurerm_application_insights" "ai" {
  depends_on = [azurerm_resource_group.rg]

  name                = "${var.prefix}appinsightsai"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
}

resource "azurerm_storage_account" "source_storage" {
  depends_on = [azurerm_resource_group.rg]

  name                     = "${var.prefix}srcblobaccstrg"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_account" "dest_storage" {
  depends_on = [azurerm_resource_group.rg]

  name                     = "${var.prefix}destaccstrg"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_account" "workspace_storage" {
  depends_on = [azurerm_resource_group.rg]

  name                     = "${var.prefix}workspacestrg"
  location                 = azurerm_resource_group.rg.location
  resource_group_name      = azurerm_resource_group.rg.name
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

# Create source blob storage container
resource "azurerm_storage_container" "source_container" {
  depends_on = [azurerm_storage_account.source_storage]

  name                  = "demo-data"
  container_access_type = "private"
  storage_account_name  = azurerm_storage_account.source_storage.name
}

# Create destination blob storage container
resource "azurerm_storage_container" "dest_container" {
  depends_on = [azurerm_storage_account.dest_storage]

  name                  = "demo-data"
  container_access_type = "private"
  storage_account_name  = azurerm_storage_account.dest_storage.name
}

resource "azurerm_service_plan" "app_service_plan" {
  name                = "${var.prefix}appserviceplan"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  os_type  = "Linux"
  sku_name = "Y1"
}


resource "azurerm_linux_function_app" "function_app" {
  depends_on = [
    azurerm_storage_account.source_storage,
    azurerm_service_plan.app_service_plan,
    azurerm_resource_group.rg,
    azurerm_storage_account.dest_storage,
    azurerm_storage_container.source_container,
    azurerm_storage_container.dest_container,
    azurerm_machine_learning_workspace.workspace
  ]

  name                = "mlops-main-func"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.source_storage.name
  storage_account_access_key = azurerm_storage_account.source_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.app_service_plan.id

  site_config {
    application_stack {
      python_version = "3.10"
    }
  }
  app_settings = {
    "AzureWebJobsStorage"            = azurerm_storage_account.source_storage.primary_connection_string,
    "demosrcblobaccstrg_STORAGE"     = azurerm_storage_account.source_storage.primary_connection_string,
    "demodestaccstrg_STORAGE"        = azurerm_storage_account.dest_storage.primary_connection_string,
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.ai.instrumentation_key,
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = true,
    "RESOURCE_GROUP_NAME"            = azurerm_resource_group.rg.name,
    "service_principal_id"           = "970e2d10-b0dc-4821-9bc5-e0145f263e76",
    "service_principal_password"     = "Sr48Q~bd7ZQKghY3~rGwXsiMIO7M2sTPeLczXa-1",
    "tenant_id"                      = data.azurerm_client_config.current.tenant_id,
    "subscription_id"                = data.azurerm_client_config.current.subscription_id,
    "workspace_name"                 = azurerm_machine_learning_workspace.workspace.name,
    "src_storage_acc_name"           = azurerm_storage_account.source_storage.name,
    "dest_storage_acc_name"          = azurerm_storage_account.dest_storage.name,
    "src_storage_container_name"     = azurerm_storage_container.source_container.name,
    "dest_storage_container_name"    = azurerm_storage_container.dest_container.name,
    "src_account_key"                = azurerm_storage_account.source_storage.primary_access_key
    "dest_account_key"               = azurerm_storage_account.dest_storage.primary_access_key
  }
}


resource "azurerm_key_vault" "kv" {
  name                = "${var.prefix}mlkeyvault"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "premium"
}

resource "azurerm_machine_learning_workspace" "workspace" {
  depends_on = [azurerm_key_vault.kv]

  name                    = "${var.prefix}mlworkspace"
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  application_insights_id = azurerm_application_insights.ai.id
  key_vault_id            = azurerm_key_vault.kv.id
  storage_account_id      = azurerm_storage_account.workspace_storage.id

  identity {
    type = "SystemAssigned"
  }
  public_network_access_enabled = true
}


resource "azurerm_role_assignment" "workspace_assignment" {
  scope                = azurerm_machine_learning_workspace.workspace.id
  role_definition_name = "Owner"
  principal_id         = "215582eb-5d3f-4e36-ae0d-762ef479f6fc"
}
