# Tigris S3 Storage Setup Guide

This guide explains how to configure Medpack to use Tigris S3-compatible storage for file uploads in production.

## Overview

The application now supports two file storage backends:

- **Local storage** (development): Files stored in `priv/static/uploads/`
- **S3 storage** (production): Files stored in Tigris S3-compatible storage

The system automatically switches between storage backends based on the `file_storage_backend` configuration.

## Tigris Setup

### 1. Create a Tigris Account

1. Go to [Tigris.dev](https://www.tigris.dev/)
2. Sign up for an account
3. Create a new project

### 2. Create an S3 Bucket

1. In your Tigris dashboard, create a new bucket
2. Choose a unique bucket name (e.g., `medpack-production-files`)
3. Keep the bucket **private** (default setting) - we'll use presigned URLs for secure access

### 3. Get API Credentials

1. In your Tigris dashboard, go to API Keys
2. Create a new API key pair
3. Note down:
   - Access Key ID
   - Secret Access Key
   - Endpoint URL (usually `https://fly.storage.tigris.dev`)

## Environment Variables

Set the following environment variables in your production environment:

```bash
# Required for S3 storage
S3_BUCKET=your-bucket-name
S3_ENDPOINT=https://fly.storage.tigris.dev
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_REGION=auto

# Optional: Override file storage backend (defaults to :s3 in production)
# FILE_STORAGE_BACKEND=s3
```

## Fly.io Deployment

If you're using Fly.io, set the environment variables using the `fly` CLI:

```bash
# Set the environment variables
fly secrets set S3_BUCKET=your-bucket-name
fly secrets set S3_ENDPOINT=https://fly.storage.tigris.dev
fly secrets set AWS_ACCESS_KEY_ID=your-access-key-id
fly secrets set AWS_SECRET_ACCESS_KEY=your-secret-access-key
fly secrets set AWS_REGION=auto

# Deploy the application
fly deploy
```

## Configuration Details

### Runtime Configuration

The S3 configuration is set in `config/runtime.exs` for production:

```elixir
if config_env() == :prod do
  # Configure S3 storage for production
  config :medpack, :file_storage_backend, :s3

  config :medpack,
    s3_bucket: System.get_env("S3_BUCKET"),
    s3_endpoint: System.get_env("S3_ENDPOINT")

  # Configure ExAws for S3
  config :ex_aws,
    access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
    region: System.get_env("AWS_REGION", "auto")

  # Configure S3 with custom endpoint (for Tigris)
  if s3_endpoint = System.get_env("S3_ENDPOINT") do
    config :ex_aws, :s3,
      scheme: "https://",
      host: s3_endpoint |> String.replace(~r/^https?:\/\//, ""),
      region: System.get_env("AWS_REGION", "auto")
  end
end
```

### Development Configuration

For development, the application continues to use local file storage:

```elixir
# config/dev.exs
config :medpack,
  upload_path: Path.expand("../uploads", __DIR__),
  temp_upload_path: Path.expand("../tmp/uploads", __DIR__)
```

## File Management

### Upload Process

1. **Development**: Files are saved to `priv/static/uploads/` and served via `/uploads/` route
2. **Production**: Files are uploaded to S3 and served via presigned URLs (secure, time-limited access)

### File Organization

Files are organized by date in S3:

```
uploads/
  2024-01-15/
    entry_123_1705123456_AbCdEf.jpg
    entry_456_1705123789_XyZwVu.png
  2024-01-16/
    entry_789_1705210123_QwErTy.jpg
```

### File Deletion

When medicines or batch entries are deleted, the associated files are automatically cleaned up from both local storage and S3.

## URL Handling

The application automatically handles both local paths and S3 presigned URLs:

- **Local**: `/uploads/filename.jpg`
- **S3**: Presigned URLs (e.g., `https://fly.storage.tigris.dev/bucket-name/uploads/2024-01-15/filename.jpg?X-Amz-Expires=3600&...`) that expire after 1 hour for security

## AI Analysis

The OpenAI Vision API can analyze images from both sources:

- **Local files**: Read and base64-encoded for API calls
- **S3 files**: Presigned URLs generated and passed directly to OpenAI (more efficient and secure)

## Troubleshooting

### Common Issues

1. **Missing environment variables**: Check that all required S3 environment variables are set
2. **Bucket permissions**: Ensure your API credentials have read/write access to the bucket
3. **Presigned URL expiration**: URLs expire after 1 hour - this is normal for security
4. **CORS issues**: Configure CORS on your S3 bucket if needed for direct uploads

### Testing S3 Connection

You can test the S3 connection in production using the Elixir console:

```elixir
# Connect to your production app
iex> Medpack.S3FileManager.list_objects("uploads/")
```

### Logs

Check application logs for S3-related errors:

```bash
fly logs
```

## Migration from Local to S3

If you have existing files in local storage that need to be migrated to S3:

1. The files will continue to work as-is (displayed via local URLs)
2. New uploads will automatically use S3
3. For full migration, you would need to:
   - Upload existing files to S3
   - Update database records with new S3 URLs
   - Clean up local files

## Security Considerations

1. **API Keys**: Keep your Tigris API keys secure and never commit them to version control
2. **Bucket Access**: Keep your bucket private - files are accessed via secure presigned URLs
3. **File Validation**: The application validates file types and sizes before upload
4. **Presigned URLs**: URLs automatically expire after 1 hour for enhanced security
5. **Access Control**: Only authenticated users can generate presigned URLs

## Cost Optimization

- Tigris offers generous free tiers
- Presigned URLs are generated on-demand to minimize storage costs
- Consider implementing lifecycle policies for old files if needed
- URLs expire automatically, reducing long-term access costs
