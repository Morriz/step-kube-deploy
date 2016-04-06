#!/bin/sh

fail='fail'
info='info'
#fail='echo'
#info='echo'

main() {
  display_version

  if [ -z "$WERCKER_KUBE_DEPLOY_DEPLOYMENT" ]; then
    $fail "wercker-kube-deploy: deployment argument cannot be empty"
    exit
  fi

  if [ -z "$WERCKER_KUBE_DEPLOY_TAG" ]; then
    $fail "wercker-kube-deploy: tag argument cannot be empty"
    exit
  fi

  # Global args
  local global_args
  local raw_global_args="$WERCKER_KUBE_DEPLOY_RAW_GLOBAL_ARGS"

  # token
  if [ -n "$WERCKER_KUBE_DEPLOY_TOKEN" ]; then
    global_args="$global_args --token=\"$WERCKER_KUBE_DEPLOY_TOKEN\""
  fi

  # username
  if [ -n "$WERCKER_KUBE_DEPLOY_USERNAME" ]; then
    global_args="$global_args --username=\"$WERCKER_KUBE_DEPLOY_USERNAME\""
  fi

  # password
  if [ -n "$WERCKER_KUBE_DEPLOY_PASSWORD" ]; then
    global_args="$global_args --password=\"$WERCKER_KUBE_DEPLOY_PASSWORD\""
  fi

  # server
  if [ -n "$WERCKER_KUBE_DEPLOY_SERVER" ]; then
    global_args="$global_args --server=\"$WERCKER_KUBE_DEPLOY_SERVER\""
  fi

  # insecure-skip-tls-verify
  if [ -n "$WERCKER_KUBE_DEPLOY_INSECURE_SKIP_TLS_VERIFY" ]; then
    global_args="$global_args --insecure-skip-tls-verify=\"$WERCKER_KUBE_DEPLOY_INSECURE_SKIP_TLS_VERIFY\""
  fi

  local kubectl=`echo "$WERCKER_STEP_ROOT/kubectl $global_args $raw_global_args"`
  [ "$WERCKER_KUBE_DEPLOY_DEBUG" = "true" ] && echo "kubectl command: $kubectl"

  local deployment=$WERCKER_KUBE_DEPLOY_DEPLOYMENT
  local tag=$WERCKER_KUBE_DEPLOY_TAG
  local deployment_script=$(eval "$kubectl get deployment/$deployment -o yaml")
  [ "$WERCKER_KUBE_DEPLOY_DEBUG" = "true" ] && echo "deployment_script: " && printf "$deployment_script" && echo ""

  local current_tag=$(printf "$deployment_script" | grep 'image: ' | cut -d : -f 4)
  [ "$WERCKER_KUBE_DEPLOY_DEBUG" = "true" ] && echo "current_tag: " && echo "$current_tag"

  if [[ $current_tag = $tag ]]; then
    $fail "Already running: $tag"
  fi

  local deployment_script_update=$(printf "$deployment_script" | sed "s,\(image: .*\):.*$,\1:$tag,")
  [ "$WERCKER_KUBE_DEPLOY_DEBUG" = "true" ] && echo "deployment_script_update: " && printf "$deployment_script_update" && echo ""

  local replicas=$(printf "$deployment_script" | grep -e '^  replicas: ' | head -n 1 | awk '{print $2}')
  [ "$WERCKER_KUBE_DEPLOY_DEBUG" = "true" ] && echo "replicas: $replicas"

  local minReadySeconds=$(printf "$deployment_script" | grep 'minReadySeconds: ' | awk '{print $2}')
  [ "$WERCKER_KUBE_DEPLOY_DEBUG" = "true" ] && echo "minReadySeconds: $minReadySeconds"

  local strategy=$(printf "$deployment_script" | grep 'strategy: ' | awk '{print $2}')
  [ -z "$strategy" ] && strategy="RollingUpdate"
  [ "$WERCKER_KUBE_DEPLOY_DEBUG" = "true" ] && echo "strategy: $strategy"

  [ -z "$minReadySeconds" ] && minReadySeconds=0
  local cmd_update="printf \"\$deployment_script_update\" | $kubectl replace -f -"
  local cmd_rollback="$kubectl rollout undo deployment/$deployment"
  [ "$WERCKER_KUBE_DEPLOY_DEBUG" = "true" ] && echo "cmd_update: " && printf "$cmd_update" && echo ""

  $info "Updating..."
  eval "$cmd_update"

  local deployment_script_now
  local timeout=$(($minReadySeconds + 10))
  if [ "$strategy" != "Recreate" ]; then
    echo "multiplying timeout with # of replicas"
    timeout=$(($timeout * $replicas))
  fi

  local retries=3
  local unavailable
  $info "Waiting for a period of $timeout seconds for strategy '$strategy' with $replicas replicas to come up..."
  while ([ "$unavailable" !=  "0" ] && [ "$retries" !=  "0" ]); do
    retries=$((retries - 1))
    eval "sleep $timeout"
    $info "Checking status of deployment..."
    deployment_script_now=$(eval "$kubectl get deployment/$deployment -o yaml")
    unavailable=$(eval "$kubectl describe deployments" | grep 'unavailable' | awk '{print $11}')
    [ "$WERCKER_KUBE_DEPLOY_DEBUG" = "true" ] && echo "unavailable: $unavailable"
    [ "$WERCKER_KUBE_DEPLOY_DEBUG" = "true" ] && echo "retries: $retries"
  done

  if [ "$unavailable" != "0" ]; then
    $info "Some pods found to be unavailable, rolling back to version: $gen_prev"
    eval $cmd_rollback
    $fail "Deployment update failed"
  fi

  $info "Updating...SUCCESS!"
}

display_version() {
  $info "Running kubectl version:"
  $WERCKER_STEP_ROOT/kubectl version --client
  echo ""
}

main;
