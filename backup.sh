#!/bin/bash

set -o errexit -o nounset -o pipefail

export AWS_PAGER=""

s3() {
    aws s3 --region "$AWS_REGION" "$@"
}

s3api() {
    aws s3api "$1" --region "$AWS_REGION" --bucket "$S3_BUCKET_NAME" "${@:2}"
}

bucket_exists() {
    s3api head-bucket 2>/dev/null
}

create_bucket() {
    echo "Bucket $S3_BUCKET_NAME doesn't exist. Creating it now..."

    # create bucket
    s3api create-bucket \
        --create-bucket-configuration LocationConstraint="$AWS_REGION" \
        --object-ownership BucketOwnerEnforced

    # block public access
    s3api put-public-access-block \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    # enable versioning for objects in the bucket 
    s3api put-bucket-versioning --versioning-configuration Status=Enabled

    # encrypt objects in the bucket
    s3api put-bucket-encryption \
      --server-side-encryption-configuration \
      '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
}

ensure_bucket_exists() {
    if bucket_exists; then
        return
    fi    
    create_bucket
}

pg_dump_database() {
    pg_dump --format=custom --no-owner --no-privileges --clean --if-exists --quote-all-identifiers "$DATABASE_URL"
}

get_database_size() {
    local size
    size=$(psql "$DATABASE_URL" -t -A -c "SELECT pg_database_size(current_database())") || {
        echo "Failed to get database size" >&2
        exit 1
    }
    echo "$size"
}

upload_to_bucket() {
    local expected_size="$1"
    local s3_path="s3://$S3_BUCKET_NAME/$(date +%Y/%m/backup-%Y-%m-%d-%H-%M-%S.dump)"
    log "Uploading to $s3_path..."
    s3 cp - "$s3_path" --expected-size "$expected_size"
    log "Upload complete"
}

main() {
    log "Starting backup"
    ensure_bucket_exists
    
    log "Getting database size..."
    local db_size
    db_size=$(get_database_size)
    log "Database size: $(format_bytes "$db_size")"
    
    log "Starting pg_dump and upload..."
    pg_dump_database | upload_to_bucket "$db_size"
    
    log "Backup complete"
}

main
