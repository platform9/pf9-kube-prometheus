#!/bin/bash

GENERATOR_FILE=${1:-'main.jsonnet'}
MANIFESTS_DIR=${2:-'deployments'}

# set up environment
echo "--> Setting up environment"
PATH=$PATH:$(pwd)/go/bin:$(pwd)/gopath/bin

echo "--> Cleaning output directory"
rm -rf $MANIFESTS_DIR
mkdir -p $MANIFESTS_DIR/

echo "--> Generating Manifests"
generators=(
    "$GENERATOR_FILE"
)
for generator in ${generators[@]}; do
    echo "----> $generator"
    for template in $(jsonnet -J vendor -m $MANIFESTS_DIR $generator); do
        cat $template | gojsontoyaml > $template.yaml
        rm -f $template
    done
done
