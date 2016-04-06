#!/bin/sh

#fail='fail'
#info='info'
fail='echo'
info='echo'

main() {
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
  local raw_global_args="$WERCKER_KUBECTL_RAW_GLOBAL_ARGS"

  # token
  if [ -n "$WERCKER_KUBECTL_TOKEN" ]; then
    global_args="$global_args --token=\"$WERCKER_KUBECTL_TOKEN\""
  fi

  # username
  if [ -n "$WERCKER_KUBECTL_USERNAME" ]; then
    global_args="$global_args --username=\"$WERCKER_KUBECTL_USERNAME\""
  fi

  # password
  if [ -n "$WERCKER_KUBECTL_PASSWORD" ]; then
    global_args="$global_args --password=\"$WERCKER_KUBECTL_PASSWORD\""
  fi

  # server
  if [ -n "$WERCKER_KUBECTL_SERVER" ]; then
    global_args="$global_args --server=\"$WERCKER_KUBECTL_SERVER\""
  fi

  # insecure-skip-tls-verify
  if [ -n "$WERCKER_KUBECTL_INSECURE_SKIP_TLS_VERIFY" ]; then
    global_args="$global_args --insecure-skip-tls-verify=\"$WERCKER_KUBECTL_INSECURE_SKIP_TLS_VERIFY\""
  fi

  local retries
  if [ -n "$WERCKER_KUBE_DEPLOY_RETRIES" ]; then
    retries=$WERCKER_KUBE_DEPLOY_RETRIES
  else
    retries=5
  fi

  local kubectl="$WERCKER_STEP_ROOT/kubectl $global_args $raw_global_args"
  [ "$WERCKER_KUBECTL_DEBUG" = "true" ] && echo "kubectl command: $kubectl"

  $info "Running kubectl version:"
  $kubectl version -c

  local deployment=$WERCKER_KUBE_DEPLOY_DEPLOYMENT
  local tag=$WERCKER_KUBE_DEPLOY_TAG
  local deployment_script=$($kubectl get deployment/$deployment -o yaml)
  [ "$WERCKER_KUBECTL_DEBUG" = "true" ] && echo "deployment_script: " && printf "$deployment_script" && echo ""
  local current_tag=$(printf "$deployment_script" | grep 'image: ' | cut -d : -f 4)
  [ "$WERCKER_KUBECTL_DEBUG" = "true" ] && echo "current_tag: " && echo "$current_tag"

  if [[ $current_tag = $tag ]]; then
    $fail "Already running: $tag"
  fi

  local deployment_script_update=$(printf "$deployment_script" | sed "s,\(image: .*\):.*$,\1:$tag,")
  [ "$WERCKER_KUBECTL_DEBUG" = "true" ] && echo "deployment_script_update: " && printf "$deployment_script_update" && echo ""

  local replicas=$(printf "$deployment_script" | grep 'replicas: ' | awk '{print $2}')
  [ "$WERCKER_KUBECTL_DEBUG" = "true" ] && echo "replicas: $replicas"

  local minReadySeconds=$(printf "$deployment_script" | grep 'minReadySeconds: ' | awk '{print $2}')
  [ "$WERCKER_KUBECTL_DEBUG" = "true" ] && echo "minReadySeconds: $minReadySeconds"

  local strategy=$(printf "$deployment_script" | grep 'strategy: ' | awk '{print $2}')
  [ -z "$strategy" ] && strategy="RollingUpdate"
  [ "$WERCKER_KUBECTL_DEBUG" = "true" ] && echo "strategy: $strategy"

  [ -z "$minReadySeconds" ] && minReadySeconds=0
  local cmd_update='printf "$deployment_script_update" | $kubectl replace -f -'
  local cmd_rollback="$kubectl rollout undo deployment/$deployment"
  [ "$WERCKER_KUBECTL_DEBUG" = "true" ] && printf "$cmd_update"

  $info "Updating..."
  eval $cmd_update
  $info "Updating...DONE"

  local deployment_script_now
  local gen_prev=0
  local gen_now=1
  local timeout=$(($minReadySeconds + 10))
  local total_timeout
  [ "$WERCKER_KUBECTL_DEBUG" = "true" ] && echo "timeout: $timeout"
  if [ "$strategy" != "Recreate" ]; then
    echo "multiplying timeout with # of replicas"
    total_timeout=`expr "$timeout * $replicas" | bc`
  fi
  $info "Waiting for a period of $total_timeout seconds for strategy '$strategy' with $replicas replicas to come up..."
  [ "$WERCKER_KUBECTL_DEBUG" = "true" ] && echo "total_timeout: $total_timeout"
  while ([ "$gen_prev" != "$gen_now" ] && [ "$retries" !=  "0" ]); do
    $info "Checking status of deployment:"
    eval "sleep $total_timeout"
    deployment_script_now=$($kubectl get deployment/$deployment -o yaml)
    gen_prev=$(printf "$deployment_script_now" | grep 'generation: ' | awk '{print $2}')
    gen_now=$(printf "$deployment_script_now" | grep 'observedGeneration: ' | awk '{print $2}')
    [ "$WERCKER_KUBECTL_DEBUG" = "true" ] && echo "prev[$gen_prev] = now[$gen_now]"
    retries=$retries-1
  done

  local unavailable=$($kubectl describe deployments | grep 'unavailable' | awk '{print $11}')
  [ "$WERCKER_KUBECTL_DEBUG" = "true" ] && echo "unavailable: $unavailable"
  if [ "$unavailable" != "0" ]; then
    $info "Some pods found to be unavailable, rolling back to version: $gen_prev"
    $cmd_rollback
    $fail "Deployment update failed"
  fi
}

main;
