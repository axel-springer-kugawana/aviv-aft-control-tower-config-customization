#!/usr/bin/env bash
#
# Deploys template.yaml as an independent CloudFormation stack for a given
# environment, using the matching parameter file in configs/<env>.json.
#
# Each environment gets its own stack (its own Producer/Consumer Lambdas and
# SQS queue), so environments never interfere with each other. The Lambda
# code and template.yaml itself are never modified by this script.
#
# Usage:
#   ./deploy.sh <environment>
#
# Example:
#   ./deploy.sh dev
#   ./deploy.sh preview

set -euo pipefail

# Maps each environment to its own, independent CloudFormation stack name.
# "dev" is the stack already running in production today - do not rename it.
declare -A STACK_NAMES=(
  [dev]="aviv-aft-ct-cfg-customization"
  [preview]="aviv-aft-ct-cfg-customization-preview"
)

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <environment>   (e.g. dev, preview)" >&2
  exit 1
fi

ENVIRONMENT="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/template.yaml"
CONFIG_FILE="${SCRIPT_DIR}/configs/${ENVIRONMENT}.json"
STACK_NAME="${STACK_NAMES[$ENVIRONMENT]:-}"

if [[ -z "$STACK_NAME" ]]; then
  echo "Unknown environment '${ENVIRONMENT}'. Known environments: ${!STACK_NAMES[*]}" >&2
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "No config file found at ${CONFIG_FILE}" >&2
  exit 1
fi

if aws cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1; then
  ACTION="update-stack"
else
  ACTION="create-stack"
fi

if [[ "$ACTION" == "update-stack" && "$ENVIRONMENT" == "dev" ]]; then
  echo "WARNING: this updates the existing production stack '${STACK_NAME}'." >&2
  echo "configs/dev.json was generated from template.yaml's current Default values -" >&2
  echo "if the live stack's actual parameters have drifted from those defaults, this" >&2
  echo "update could change more than intended. Consider running with --no-execute-changeset" >&2
  echo "or reviewing a change set before applying, if you haven't verified there's no drift." >&2
fi

echo "About to run: aws cloudformation ${ACTION} --stack-name ${STACK_NAME} --parameters file://${CONFIG_FILE}"
read -r -p "Continue? [y/N] " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted."
  exit 1
fi

aws cloudformation "$ACTION" \
  --stack-name "$STACK_NAME" \
  --template-body "file://${TEMPLATE_FILE}" \
  --parameters "file://${CONFIG_FILE}" \
  --capabilities CAPABILITY_IAM

echo "Waiting for stack ${ACTION%-stack} to complete..."
aws cloudformation wait "stack-${ACTION%-stack}-complete" --stack-name "$STACK_NAME"
echo "Done: ${STACK_NAME}"
