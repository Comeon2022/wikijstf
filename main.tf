# =============================================================================
# Wiki.js on Google Cloud Run - Complete Terraform Deployment
# Repository: https://github.com/Comeon2022/wikijstf.git
# Version: 1.0.0
# Last Updated: 2025-08-15
# 
# Usage:
# 1. git clone https://github.com/Comeon2022/wikijstf.git
# 2. cd wikijstf
# 3. terraform init
# 4. terraform apply
# 5. Enter your GCP project ID when prompted
# 6. Everything else is automated!
# =============================================================================

# Variables
variable "project_id" {
  description = "GCP Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "GCP Region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone for resources"
  type        = string
  default     = "us-central1-a"
}

# Provider configuration
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# =============================================================================
# STEP 1: ENABLE REQUIRED APIS
# =============================================================================

resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "sqladmin.googleapis.com",
    "sql-component.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "compute.googleapis.com",
    "logging.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Wait for APIs to be fully enabled
resource "time_sleep" "wait_for_apis" {
  depends_on      = [google_project_service.required_apis]
  create_duration = "90s"
}

# =============================================================================
# STEP 2: CREATE SERVICE ACCOUNTS
# =============================================================================

# Main Wiki.js Service Account
resource "google_service_account" "wiki_js_sa" {
  account_id   = "wiki-js-sa"
  display_name = "Wiki.js Application Service Account"
  description  = "Service account for Wiki.js Cloud Run application"
  project      = var.project_id
  
  depends_on = [time_sleep.wait_for_apis]
}

# Cloud Build Service Account
resource "google_service_account" "cloudbuild_sa" {
  account_id   = "wiki-js-build-sa"
  display_name = "Wiki.js Cloud Build Service Account"
  description  = "Service account for building and pushing Wiki.js container images"
  project      = var.project_id
  
  depends_on = [time_sleep.wait_for_apis]
}

# =============================================================================
# STEP 3: CREATE ARTIFACT REGISTRY
# =============================================================================

resource "google_artifact_registry_repository" "wiki_js_repo" {
  location      = var.region
  repository_id = "wiki-js"
  description   = "Container repository for Wiki.js application images"
  format        = "DOCKER"
  
  depends_on = [time_sleep.wait_for_apis]
}

# =============================================================================
# STEP 4: IAM PERMISSIONS FOR SERVICE ACCOUNTS
# =============================================================================

# IAM permissions for Wiki.js Service Account
resource "google_project_iam_member" "wiki_js_sa_permissions" {
  for_each = toset([
    "roles/run.developer",
    "roles/logging.logWriter",
    "roles/logging.viewer",
    "roles/cloudsql.client"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.wiki_js_sa.email}"
}

# Artifact Registry permissions for Wiki.js Service Account
resource "google_artifact_registry_repository_iam_member" "wiki_js_sa_registry" {
  project    = var.project_id
  location   = google_artifact_registry_repository.wiki_js_repo.location
  repository = google_artifact_registry_repository.wiki_js_repo.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.wiki_js_sa.email}"
}

# IAM permissions for Cloud Build Service Account
resource "google_project_iam_member" "cloudbuild_sa_permissions" {
  for_each = toset([
    "roles/cloudbuild.builds.builder",
    "roles/logging.logWriter",
    "roles/storage.admin"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# Artifact Registry permissions for Cloud Build Service Account
resource "google_artifact_registry_repository_iam_member" "cloudbuild_sa_registry" {
  project    = var.project_id
  location   = google_artifact_registry_repository.wiki_js_repo.location
  repository = google_artifact_registry_repository.wiki_js_repo.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

# =============================================================================
# STEP 5: CREATE CLOUD SQL DATABASE
# =============================================================================

resource "google_sql_database_instance" "wiki_postgres" {
  name             = "wiki-postgres-instance"
  database_version = "POSTGRES_15"
  region          = var.region
  
  settings {
    tier = "db-f1-micro"
    
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 10
    
    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = false
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
    
    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "stable"
    }
    
    ip_configuration {
      ipv4_enabled = true
      authorized_networks {
        name  = "allow-all-for-development"
        value = "0.0.0.0/0"
      }
    }
    
    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
  }
  
  deletion_protection = false
  
  timeouts {
    create = "30m"
    update = "30m"  
    delete = "30m"
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# Wait for Cloud SQL instance to be fully operational
resource "time_sleep" "wait_for_sql_instance" {
  depends_on      = [google_sql_database_instance.wiki_postgres]
  create_duration = "120s"
}

# Create Wiki.js database
resource "google_sql_database" "wiki_database" {
  name     = "wiki"
  instance = google_sql_database_instance.wiki_postgres.name
  
  depends_on = [time_sleep.wait_for_sql_instance]
}

# Create Wiki.js database user
resource "google_sql_user" "wiki_user" {
  name     = "wikijs"
  instance = google_sql_database_instance.wiki_postgres.name
  password = "wikijsrocks"
  
  depends_on = [time_sleep.wait_for_sql_instance]
}

# =============================================================================
# STEP 6: CLOUD BUILD FOR DOCKER IMAGE
# =============================================================================

# =============================================================================
# STEP 6: BUILD AND PUSH DOCKER IMAGE USING CLOUD BUILD
# =============================================================================

# Execute Cloud Build to pull and push Wiki.js image
resource "terraform_data" "build_and_push_image" {
  triggers_replace = [
    google_artifact_registry_repository.wiki_js_repo.name
  ]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "🚀 Starting Wiki.js image build and push process..."
      
      # Create a temporary build configuration
      cat > /tmp/cloudbuild.yaml << 'EOF'
steps:
  # Pull the official Wiki.js image
  - name: 'gcr.io/cloud-builders/docker'
    args: ['pull', 'ghcr.io/requarks/wiki:2']
    
  # Tag for Artifact Registry
  - name: 'gcr.io/cloud-builders/docker'
    args: 
      - 'tag'
      - 'ghcr.io/requarks/wiki:2'
      - '${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}/wiki:2'
      
  # Tag as latest
  - name: 'gcr.io/cloud-builders/docker'
    args:
      - 'tag' 
      - 'ghcr.io/requarks/wiki:2'
      - '${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}/wiki:latest'
      
  # Push version 2
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', '${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}/wiki:2']
    
  # Push latest
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', '${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}/wiki:latest']

options:
  logging: CLOUD_LOGGING_ONLY
timeout: '600s'
serviceAccount: '${google_service_account.cloudbuild_sa.email}'
EOF
      
      echo "📦 Submitting build job to Cloud Build..."
      
      # Submit the build and capture the build ID properly
      BUILD_OUTPUT=$(gcloud builds submit --config=/tmp/cloudbuild.yaml \
        --no-source \
        --project=${var.project_id} \
        --format="value(id)" 2>&1)
      
      # Extract build ID from output
      BUILD_ID=$(echo "$BUILD_OUTPUT" | grep -E '^[a-f0-9-]{36}

# =============================================================================
# STEP 7: DEPLOY CLOUD RUN SERVICE
# =============================================================================

resource "google_cloud_run_v2_service" "wiki_js" {
  name     = "wiki-js"
  location = var.region
  
  template {
    service_account = google_service_account.wiki_js_sa.email
    
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}/wiki:2"
      
      ports {
        container_port = 3000
      }
      
      # Environment variables for Wiki.js
      env {
        name  = "DB_TYPE"
        value = "postgres"
      }
      
      env {
        name  = "DB_HOST"
        value = google_sql_database_instance.wiki_postgres.public_ip_address
      }
      
      env {
        name  = "DB_PORT"
        value = "5432"
      }
      
      env {
        name  = "DB_USER"
        value = google_sql_user.wiki_user.name
      }
      
      env {
        name  = "DB_PASS"
        value = google_sql_user.wiki_user.password
      }
      
      env {
        name  = "DB_NAME"
        value = google_sql_database.wiki_database.name
      }
      
      # Resource configuration
      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = false
      }
      
      # Health check
      startup_probe {
        http_get {
          path = "/"
          port = 3000
        }
        initial_delay_seconds = 30
        timeout_seconds      = 10
        period_seconds       = 10
        failure_threshold    = 3
      }
      
      liveness_probe {
        http_get {
          path = "/"
          port = 3000
        }
        initial_delay_seconds = 60
        timeout_seconds      = 5
        period_seconds       = 30
        failure_threshold    = 3
      }
    }
    
    # Scaling configuration
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
    
    # Execution environment
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    
    # Timeout
    timeout = "300s"
  }
  
  # Traffic configuration
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  depends_on = [
    terraform_data.build_and_push_image,
    google_sql_database.wiki_database,
    google_sql_user.wiki_user,
    google_project_iam_member.wiki_js_sa_permissions
  ]
}

# Allow public access to Cloud Run service
resource "google_cloud_run_service_iam_member" "public_access" {
  service  = google_cloud_run_v2_service.wiki_js.name
  location = google_cloud_run_v2_service.wiki_js.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "deployment_summary" {
  description = "🎉 Deployment Summary"
  value = {
    "✅ Status"                = "Wiki.js deployment completed successfully!"
    "🌐 Wiki.js URL"          = google_cloud_run_v2_service.wiki_js.uri
    "🗄️  Database"            = "${google_sql_database_instance.wiki_postgres.name} (${google_sql_database_instance.wiki_postgres.public_ip_address})"
    "📦 Image Registry"       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}"
    "🔑 Service Account"      = google_service_account.wiki_js_sa.email
    "🏗️  Build Method"        = "Cloud Build via terraform_data"
  }
}

output "wiki_js_url" {
  description = "🌐 Your Wiki.js Application URL"
  value       = google_cloud_run_v2_service.wiki_js.uri
}

output "next_steps" {
  description = "📋 What to do next"
  value = <<-EOT
    
    🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!
    
    📝 Next Steps:
    1. Visit your Wiki.js URL: ${google_cloud_run_v2_service.wiki_js.uri}
    2. Complete the initial setup wizard
    3. Create your admin account
    4. Start building your wiki!
    
    🔧 Management URLs:
    - Cloud Run: https://console.cloud.google.com/run/detail/${var.region}/wiki-js/metrics?project=${var.project_id}
    - Cloud SQL: https://console.cloud.google.com/sql/instances/wiki-postgres-instance/overview?project=${var.project_id}
    - Artifact Registry: https://console.cloud.google.com/artifacts/docker/${var.project_id}/${var.region}/wiki-js?project=${var.project_id}
    
    💡 Tips:
    - Database connection is pre-configured
    - Your wiki is publicly accessible
    - Logs are available in Cloud Run console
    
    🚀 Happy wiki-ing!
  EOT
}

# Database connection string (sensitive)
output "database_connection" {
  description = "Database connection details"
  sensitive   = true
  value = {
    host     = google_sql_database_instance.wiki_postgres.public_ip_address
    database = google_sql_database.wiki_database.name
    username = google_sql_user.wiki_user.name
    password = google_sql_user.wiki_user.password
    port     = 5432
  }
} | head -1)
      
      if [ -z "$BUILD_ID" ]; then
        echo "❌ Failed to get build ID. Build output:"
        echo "$BUILD_OUTPUT"
        exit 1
      fi
      
      echo "🔨 Build submitted with ID: $BUILD_ID"
      echo "⏳ Waiting for build to complete..."
      
      # Wait for build to complete and stream logs
      if ! gcloud builds log "$BUILD_ID" --stream --project=${var.project_id}; then
        echo "⚠️ Failed to stream logs, but build may still be running..."
      fi
      
      # Wait a bit and check final status
      sleep 30
      BUILD_STATUS=$(gcloud builds describe "$BUILD_ID" --project=${var.project_id} --format="value(status)" 2>/dev/null || echo "UNKNOWN")
      
      # Wait for completion if still running
      WAIT_COUNT=0
      while [ "$BUILD_STATUS" = "WORKING" ] && [ $WAIT_COUNT -lt 20 ]; do
        echo "⏳ Build still running... (check $((WAIT_COUNT + 1))/20)"
        sleep 30
        BUILD_STATUS=$(gcloud builds describe "$BUILD_ID" --project=${var.project_id} --format="value(status)" 2>/dev/null || echo "UNKNOWN")
        WAIT_COUNT=$((WAIT_COUNT + 1))
      done
      
      if [ "$BUILD_STATUS" = "SUCCESS" ]; then
        echo "✅ Wiki.js image successfully built and pushed to Artifact Registry!"
      else
        echo "❌ Build failed or timed out with status: $BUILD_STATUS"
        echo "Check build details: https://console.cloud.google.com/cloud-build/builds/$BUILD_ID?project=${var.project_id}"
        exit 1
      fi
      
      # Clean up temporary file
      rm -f /tmp/cloudbuild.yaml
    EOT
  }
  
  depends_on = [
    google_artifact_registry_repository.wiki_js_repo,
    google_artifact_registry_repository_iam_member.cloudbuild_sa_registry,
    google_project_iam_member.cloudbuild_sa_permissions
  ]
}

# =============================================================================
# STEP 7: DEPLOY CLOUD RUN SERVICE
# =============================================================================

resource "google_cloud_run_v2_service" "wiki_js" {
  name     = "wiki-js"
  location = var.region
  
  template {
    service_account = google_service_account.wiki_js_sa.email
    
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}/wiki:2"
      
      ports {
        container_port = 3000
      }
      
      # Environment variables for Wiki.js
      env {
        name  = "DB_TYPE"
        value = "postgres"
      }
      
      env {
        name  = "DB_HOST"
        value = google_sql_database_instance.wiki_postgres.public_ip_address
      }
      
      env {
        name  = "DB_PORT"
        value = "5432"
      }
      
      env {
        name  = "DB_USER"
        value = google_sql_user.wiki_user.name
      }
      
      env {
        name  = "DB_PASS"
        value = google_sql_user.wiki_user.password
      }
      
      env {
        name  = "DB_NAME"
        value = google_sql_database.wiki_database.name
      }
      
      # Resource configuration
      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = false
      }
      
      # Health check
      startup_probe {
        http_get {
          path = "/"
          port = 3000
        }
        initial_delay_seconds = 30
        timeout_seconds      = 10
        period_seconds       = 10
        failure_threshold    = 3
      }
      
      liveness_probe {
        http_get {
          path = "/"
          port = 3000
        }
        initial_delay_seconds = 60
        timeout_seconds      = 5
        period_seconds       = 30
        failure_threshold    = 3
      }
    }
    
    # Scaling configuration
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
    
    # Execution environment
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    
    # Timeout
    timeout = "300s"
  }
  
  # Traffic configuration
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  depends_on = [
    terraform_data.build_and_push_image,
    google_sql_database.wiki_database,
    google_sql_user.wiki_user,
    google_project_iam_member.wiki_js_sa_permissions
  ]
}

# Allow public access to Cloud Run service
resource "google_cloud_run_service_iam_member" "public_access" {
  service  = google_cloud_run_v2_service.wiki_js.name
  location = google_cloud_run_v2_service.wiki_js.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "deployment_summary" {
  description = "🎉 Deployment Summary"
  value = {
    "✅ Status"                = "Wiki.js deployment completed successfully!"
    "🌐 Wiki.js URL"          = google_cloud_run_v2_service.wiki_js.uri
    "🗄️  Database"            = "${google_sql_database_instance.wiki_postgres.name} (${google_sql_database_instance.wiki_postgres.public_ip_address})"
    "📦 Image Registry"       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}"
    "🔑 Service Account"      = google_service_account.wiki_js_sa.email
    "🏗️  Build Method"        = "Cloud Build via terraform_data"
  }
}

output "wiki_js_url" {
  description = "🌐 Your Wiki.js Application URL"
  value       = google_cloud_run_v2_service.wiki_js.uri
}

output "next_steps" {
  description = "📋 What to do next"
  value = <<-EOT
    
    🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!
    
    📝 Next Steps:
    1. Visit your Wiki.js URL: ${google_cloud_run_v2_service.wiki_js.uri}
    2. Complete the initial setup wizard
    3. Create your admin account
    4. Start building your wiki!
    
    🔧 Management URLs:
    - Cloud Run: https://console.cloud.google.com/run/detail/${var.region}/wiki-js/metrics?project=${var.project_id}
    - Cloud SQL: https://console.cloud.google.com/sql/instances/wiki-postgres-instance/overview?project=${var.project_id}
    - Artifact Registry: https://console.cloud.google.com/artifacts/docker/${var.project_id}/${var.region}/wiki-js?project=${var.project_id}
    
    💡 Tips:
    - Database connection is pre-configured
    - Your wiki is publicly accessible
    - Logs are available in Cloud Run console
    
    🚀 Happy wiki-ing!
  EOT
}

# Database connection string (sensitive)
output "database_connection" {
  description = "Database connection details"
  sensitive   = true
  value = {
    host     = google_sql_database_instance.wiki_postgres.public_ip_address
    database = google_sql_database.wiki_database.name
    username = google_sql_user.wiki_user.name
    password = google_sql_user.wiki_user.password
    port     = 5432
  }
}