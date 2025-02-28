#!/bin/bash

# Ensure VERSION is set
if [ -z "$VERSION" ]; then
  echo "You must set the VERSION environment variable" >&2
  exit 1
fi

# Determine whether we're running a nightly build
IS_NIGHTLY=false
if [[ "$VERSION" == nightly-* ]]; then
  IS_NIGHTLY=true
fi

TEMPLATES=${TEMPLATES:-}

set -euo pipefail

setup_venv() {
  echo "Setting up virtual environment..."
  uv venv -p python3.10
  source .venv/bin/activate
}

install_dependencies() {
  if $IS_NIGHTLY; then
    echo "Installing dependencies for nightly build..."
    pip install -U .
  else
    echo "Installing dependencies from PyPI..."
    local PYPI_SOURCE=""
    if release_exists "test.pypi"; then
      PYPI_SOURCE="testpypi"
    elif release_exists "pypi"; then
      PYPI_SOURCE="pypi"
    else
      echo "Version $VERSION not found in either test.pypi or pypi" >&2
      exit 1
    fi

    uv pip install --index-url https://test.pypi.org/simple/ \
      --extra-index-url https://pypi.org/simple \
      --index-strategy unsafe-best-match \
      llama-stack==${VERSION} llama-models==${VERSION} llama-stack-client==${VERSION}
  fi
}

release_exists() {
  local source=$1
  releases=$(curl -s https://${source}.org/pypi/llama-stack/json | jq -r '.releases | keys[]')
  for release in $releases; do
    if [ "x$release" = "x$VERSION" ]; then
      return 0
    fi
  done
  return 1
}

build_and_push_docker() {
  local template=$1
  echo "Building and pushing docker for template $template"

  if $IS_NIGHTLY; then
    USE_COPY_NOT_MOUNT=true LLAMA_STACK_DIR=. llama stack build --template "$template" --image-type container
    docker tag "distribution-$template:dev" "llamastack/distribution-$template:${VERSION}"
  else
    if [ "$PYPI_SOURCE" = "testpypi" ]; then
      TEST_PYPI_VERSION=${VERSION} llama stack build --template "$template" --image-type container
    else
      PYPI_VERSION=${VERSION} llama stack build --template "$template" --image-type container
    fi

    if [ "$PYPI_SOURCE" = "testpypi" ]; then
      docker tag "distribution-$template:test-${VERSION}" "llamastack/distribution-$template:test-${VERSION}"
      docker push "llamastack/distribution-$template:test-${VERSION}"
    else
      docker tag "distribution-$template:${VERSION}" "llamastack/distribution-$template:${VERSION}"
      docker tag "distribution-$template:${VERSION}" "llamastack/distribution-$template:latest"
      docker push "llamastack/distribution-$template:${VERSION}"
      docker push "llamastack/distribution-$template:latest"
    fi
  fi

  docker push "llamastack/distribution-$template:${VERSION}"
}

main() {
  set -x

  # Create and enter temporary directory for non-nightly builds
  if ! $IS_NIGHTLY; then
    TMPDIR=$(mktemp -d)
    cd "$TMPDIR"
  else
    cd llama-stack
  fi

  setup_venv
  install_dependencies
  which llama
  llama stack list-apis

  # Convert TEMPLATES into an array if it's a comma-separated string
  if [ -z "$TEMPLATES" ]; then
    TEMPLATES=(ollama together fireworks bedrock remote-vllm tgi meta-reference-gpu)
  else
    IFS=',' read -r -a TEMPLATES <<< "$TEMPLATES"
  fi

  for template in "${TEMPLATES[@]}"; do
    build_and_push_docker "$template"
  done

  echo "Done"
}

main
