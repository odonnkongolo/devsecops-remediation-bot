# 1. Provide an S3 Bucket for AWS Config to store history
resource "random_id" "bucket_id" {
  byte_length = 4
}

resource "aws_s3_bucket" "config_bucket" {
  bucket        = "devsecops-config-history-${random_id.bucket_id.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "config_bucket_pab" {
  bucket = aws_s3_bucket.config_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_kms_key" "config_bucket_key" {
  description             = "KMS key for Config bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_bucket_encryption" {
  bucket = aws_s3_bucket.config_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.config_bucket_key.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# 2. Grant AWS Config permission to read your account and write to the bucket
resource "aws_iam_role" "config_role" {
  name = "devsecops-aws-config-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_attach" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}
# Grant the Config Role explicit permission to write to our specific S3 bucket
resource "aws_iam_role_policy" "config_s3_policy" {
  name = "devsecops-config-s3-policy"
  role = aws_iam_role.config_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject"]
        # Allow writing to the AWSLogs directory inside our bucket
        Resource = "${aws_s3_bucket.config_bucket.arn}/AWSLogs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketAcl"]
        Resource = aws_s3_bucket.config_bucket.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.config_bucket_key.arn
      }
    ]
  })
}

# 3. Turn on the AWS Config Recorder (The Security Camera)
resource "aws_config_configuration_recorder" "main" {
  name     = "default"
  role_arn = aws_iam_role.config_role.arn
}

# 4. Attach the Delivery Channel (The Tape Drive)
resource "aws_config_delivery_channel" "main" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config_bucket.bucket
  # Tell Terraform to wait for both the recorder AND the new S3 policy
  depends_on = [
    aws_config_configuration_recorder.main,
    aws_iam_role_policy.config_s3_policy
  ]
}

# 5. Ensure the camera is actively recording
resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}