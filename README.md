# Wiki.js on Google Cloud Run - Terraform Deployment

![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white) ![Google Cloud](https://img.shields.io/badge/GoogleCloud-%234285F4.svg?style=for-the-badge&logo=google-cloud&logoColor=white) ![PostgreSQL](https://img.shields.io/badge/postgresql-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)

Deploy [Wiki.js](https://wiki.js.org/) on Google Cloud Run with a complete, automated Terraform configuration. This repository provides a **single-command deployment** that sets up everything you need for a production-ready Wiki.js instance.

## 🏗️ Architecture

- **🚀 Cloud Run**: Serverless Wiki.js application hosting
- **🗄️ Cloud SQL**: Managed PostgreSQL 15 database
- **📦 Artifact Registry**: Private container image storage  
- **🔧 Cloud Build**: Automated image building and deployment
- **🔐 IAM**: Properly configured service accounts and permissions
- **🌐 Public Access**: Ready-to-use wiki accessible from anywhere

## ⚡ Quick Start

### Prerequisites
- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) installed and configured
- [Terraform](https://www.terraform.io/downloads) installed (>= 1.0)
- A GCP project with billing enabled
- `gcloud auth application-default login` completed

### One-Command Deployment

```bash
# 1. Clone this repository
git clone https://github.com/Comeon2022/wikijstf.git
cd wikijstf

# 2. Initialize Terraform
terraform init

# 3. Deploy everything (you'll be prompted for your GCP project ID)
terraform apply
```

That's it! ✨ Terraform will handle everything else automatically:

- ✅ Enable required GCP APIs
- ✅ Create service accounts with proper permissions  
- ✅ Set up Cloud SQL PostgreSQL database
- ✅ Create Artifact Registry repository
- ✅ Build and push Wiki.js container image using Cloud Build
- ✅ Deploy Cloud Run service with database connection
- ✅ Configure public access

## 📋 What Gets Created

| Resource | Name | Purpose |
|----------|------|---------|
| **Cloud Run Service** | `wiki-js` | Hosts the Wiki.js application |
| **Cloud SQL Instance** | `wiki-postgres-instance` | PostgreSQL 15 database |
| **Artifact Registry** | `wiki-js` | Stores container images |
| **Service Account** | `wiki-js-sa` | Cloud Run application identity |
| **Service Account** | `wiki-js-build-sa` | Cloud Build identity |
| **Cloud Build Trigger** | `wiki-js-image-builder` | Builds and pushes images |

## 🔧 Configuration Options

You can customize the deployment by modifying variables:

```bash
# Deploy with custom region
terraform apply -var="region=europe-west1"

# Deploy with custom zone  
terraform apply -var="zone=europe-west1-a"
```

Available variables:
- `project_id` (required): Your GCP project ID
- `region` (optional): GCP region (default: `us-central1`)
- `zone` (optional): GCP zone (default: `us-central1-a`)

## 📊 Monitoring & Management

After deployment, manage your Wiki.js instance through:

- **📱 Application**: Visit the provided Wiki.js URL to set up your wiki
- **☁️ Cloud Run**: [GCP Console → Cloud Run](https://console.cloud.google.com/run)
- **🗄️ Database**: [GCP Console → Cloud SQL](https://console.cloud.google.com/sql)
- **📦 Images**: [GCP Console → Artifact Registry](https://console.cloud.google.com/artifacts)
- **🏗️ Builds**: [GCP Console → Cloud Build](https://console.cloud.google.com/cloud-build)

## 🛡️ Security Features

- **🔐 IAM**: Least privilege service accounts
- **🔒 Private Registry**: Container images in private Artifact Registry
- **🛡️ Network Security**: Cloud SQL with authorized networks
- **📝 Audit Logging**: All actions logged to Cloud Logging
- **🔄 Automatic Backups**: Daily database backups enabled

## 💰 Cost Estimation

Approximate monthly costs for light usage:

| Service | Configuration | Est. Monthly Cost |
|---------|---------------|-------------------|
| Cloud Run | 1M requests, 512MB RAM | ~$2-5 |
| Cloud SQL | db-f1-micro, 10GB SSD | ~$7-10 |
| Artifact Registry | <1GB storage | ~$0.10 |
| Cloud Build | Few builds/month | ~$0.10 |
| **Total** | | **~$10-15/month** |

## 🔧 Advanced Usage

### Custom Database Configuration

Edit `main.tf` to modify database settings:

```hcl
resource "google_sql_database_instance" "wiki_postgres" {
  settings {
    tier = "db-custom-2-4096"  # 2 vCPU, 4GB RAM
    disk_size = 50             # 50GB SSD
    # ... other settings
  }
}
```

### Scaling Configuration

Modify Cloud Run scaling limits:

```hcl
resource "google_cloud_run_v2_service" "wiki_js" {
  template {
    scaling {
      min_instance_count = 1   # Always keep 1 instance warm
      max_instance_count = 100 # Allow up to 100 instances
    }
  }
}
```

## 🧹 Cleanup

To destroy all resources and avoid charges:

```bash
terraform destroy
```

⚠️ **Warning**: This will permanently delete your database and all wiki content!

## 🐛 Troubleshooting

### Common Issues

**"APIs not enabled" errors**
- Wait 2-3 minutes after first `terraform apply` for APIs to fully activate
- Re-run `terraform apply`

**Cloud Build timeout**
- Check [Cloud Build history](https://console.cloud.google.com/cloud-build/builds) for detailed logs
- Re-run `terraform apply` to retry

**Database connection issues**  
- Verify Cloud SQL instance is `RUNNABLE` status
- Check Cloud Run logs for connection errors

### Getting Help

1. **Check Cloud Run logs**:
   ```bash
   gcloud run services logs read wiki-js --region=us-central1
   ```

2. **Verify database connectivity**:
   ```bash
   gcloud sql connect wiki-postgres-instance --user=wikijs
   ```

3. **Check Terraform state**:
   ```bash
   terraform show
   terraform refresh
   ```

## 🏷️ Version History

- **v1.0.0**: Initial release with complete automation
  - Full Terraform deployment
  - Cloud Build integration  
  - Production-ready configuration

## 🤝 Contributing

1. Fork this repository
2. Create a feature branch: `git checkout -b feature-name`
3. Commit changes: `git commit -am 'Add feature'`
4. Push to branch: `git push origin feature-name`
5. Submit a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Wiki.js](https://wiki.js.org/) - Amazing open-source wiki software
- [Google Cloud Platform](https://cloud.google.com/) - Reliable cloud infrastructure  
- [Terraform](https://www.terraform.io/) - Infrastructure as Code excellence

---

**⭐ If this helped you, please give it a star!** ⭐