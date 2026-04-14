#!/bin/sh

set -eu

log_note() {
  echo "note: $1"
}

log_warning() {
  echo "warning: $1" >&2
}

log_error() {
  echo "error: $1" >&2
}

require_directory() {
  if [ ! -d "$1" ]; then
    log_error "$2"
    exit 1
  fi
}

resolve_source_models_dir() {
  if [ -n "${MOBILECLIP_MODELS_DIR:-}" ]; then
    require_directory "$MOBILECLIP_MODELS_DIR" "MOBILECLIP_MODELS_DIR points to a missing directory: $MOBILECLIP_MODELS_DIR"
    echo "$MOBILECLIP_MODELS_DIR"
    return 0
  fi

  default_dir="$SRCROOT/LocalModels/MobileCLIP"
  legacy_dir="$SRCROOT/Iris-Main/Resources/MobileCLIP"

  if [ -d "$default_dir" ]; then
    echo "$default_dir"
    return 0
  fi

  if [ -d "$legacy_dir" ]; then
    log_warning "Using legacy MobileCLIP source folder at $legacy_dir. Move the models to $default_dir or set MOBILECLIP_MODELS_DIR."
    echo "$legacy_dir"
    return 0
  fi

  return 1
}

if ! source_models_dir="$(resolve_source_models_dir)"; then
  log_warning "MobileCLIP models not found. Expected \$SRCROOT/LocalModels/MobileCLIP or MOBILECLIP_MODELS_DIR. Skipping bundle copy."
  exit 0
fi

image_model_dir="$source_models_dir/mobileclip_s2_image.mlmodelc"
text_model_dir="$source_models_dir/mobileclip_s2_text.mlmodelc"

require_directory "$image_model_dir" "Missing MobileCLIP image model directory: $image_model_dir"
require_directory "$text_model_dir" "Missing MobileCLIP text model directory: $text_model_dir"

destination_root="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
destination_models_dir="$destination_root/MobileCLIP"

mkdir -p "$destination_root"
rm -rf "$destination_models_dir"
ditto "$source_models_dir" "$destination_models_dir"

log_note "Copied MobileCLIP models from $source_models_dir to $destination_models_dir"
