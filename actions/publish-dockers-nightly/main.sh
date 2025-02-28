#!/bin/bash

# Version will be nightly + timestamp
VERSION=nightly-$(date +%Y%m%d)
TEMPLATES=${TEMPLATES:-}

set -euo pipefail

cd llama-stack
set -x
uv venv -p python3.10
source .venv/bin/activate
pip install -U .
which llama
llama stack list-apis

build_and_push_docker() {
  template=$1

  USE_COPY_NOT_MOUNT=true LLAMA_STACK_DIR=. llama stack build --template $template --image-type container
  docker images

  echo "Pushing docker image"
  docker tag distribution-$template:dev cooktheryan/distribution-$template:${VERSION}
  docker push cooktheryan/distribution-$template:${VERSION}
}


if [ -z "$TEMPLATES" ]; then
  TEMPLATES=(ollama together fireworks bedrock remote-vllm tgi meta-reference-gpu)
else
  TEMPLATES=(${TEMPLATES//,/ })
fi

for template in "${TEMPLATES[@]}"; do
  build_and_push_docker $template
done

echo "Done"