#!/usr/bin/env bash

debug() { if [ "$WERCKER_KUBE_DEPLOY_DEBUG" = "true" ]; then echo "$*"; return 0; else return 1; fi }
#info() { echo "$*"; }
#fail() { echo "$*"; exit 1; }

parse_yaml() {
    local prefix=$2
    local s
    local w
    local fs
    s='[[:space:]]*'
    w='[a-zA-Z0-9_]*'
    fs="$(echo @|tr @ '\034')"
    sed -ne "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" "$1" |
    awk -F"$fs" '{
      indent = length($1)/2;
      if (length($2) == 0) { conj[indent]="+";} else {conj[indent]="";}
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
              vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
              printf("%s%s%s%s=(\"%s\")\n", "'"$prefix"'",vn, $2, conj[indent-1],$3);
      }
    }' | sed 's/_=/+=/g'
}

main() {
  display_version

  if [ -z "$WERCKER_KUBE_DEPLOY_DEPLOYMENT" ]; then
    fail "wercker-kube-deploy: deployment argument cannot be empty"
  fi

  if [ -z "$WERCKER_KUBE_DEPLOY_TAG" ]; then
    fail "wercker-kube-deploy: tag argument cannot be empty"
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
  debug "kubectl command: $kubectl"

  local deployment=$WERCKER_KUBE_DEPLOY_DEPLOYMENT
  local tag=$WERCKER_KUBE_DEPLOY_TAG
  local deployment_script=$(eval "$kubectl get deployment/$deployment -o yaml")
  printf "$deployment_script" > dep.yaml
  debug "parsing yaml"
  local yaml=$(parse_yaml dep.yaml "dep_")
#  debug "created vars:\n\n$yaml"
  eval $yaml

  if (($? > 0)); then
    fail "Something went wrong, aborting..."
  fi
  debug "deployment_script: " && printf "$deployment_script" && echo ""

  local current_tag=$(printf "$deployment_script" | grep 'image: ' | cut -d : -f 4)
  debug "current_tag: $current_tag"

  if [[ $current_tag = $tag ]]; then
    fail "Already running: $tag"
  fi

  local deployment_script_update=$(printf "$deployment_script" | sed "s,\(image: .*\):.*$,\1:$tag,")
  debug "deployment_script_update: " && printf "$deployment_script_update" && echo ""

  local replicas=$dep_status_replicas
  debug "replicas: $replicas"

  local minReadySeconds=$dep_spec_minReadySeconds
  debug "minReadySeconds: $minReadySeconds"

  local readinessTimeout=$dep_spec_template_spec__readinessProbe_periodSeconds
  debug "readinessTimeout: $readinessTimeout"

  local noRollbackMechanism
  [[ -z "$minReadySeconds" && -z "$readinessTimeout" ]] && noRollbackMechanism=true
  debug "noRollbackMechanism: $noRollbackMechanism"

  local timeout=$minReadySeconds
  [ -z "$timeout" ] && timeout=$readinessTimeout
  [ -z "$timeout" ] && timeout=0

  local strategy=$dep_spec_strategy_type
  [ -z "$strategy" ] && strategy="RollingUpdate"
  debug "strategy: $strategy"

  local cmd_update="printf \"\$deployment_script_update\" | $kubectl replace -f -"
  local cmd_rollback="$kubectl rollout undo deployment/$deployment"
  debug "cmd_update: " && printf "$cmd_update" && echo ""

  info "Updating..."
  eval "$cmd_update"

  local deployment_script_now
  if [ "$strategy" != "Recreate" ]; then
    echo "multiplying timeout with # of replicas"
    timeout=$(($timeout * $replicas))
  fi
  # just to be sure we add 10 secs
  timeout=$(($timeout + 10))
  echo "timeout: $timeout"

  local retries=3
  local unavailable
  info "Waiting for a period of $timeout seconds for strategy '$strategy' with $replicas replicas to come up..."
  while ([ "$unavailable" !=  "0" ] && [ "$retries" !=  "0" ]); do
    retries=$((retries - 1))
    eval "sleep $timeout"
    debug "retries: $retries"
    info "Checking status of deployment..."
    deployment_script_now=$(eval "$kubectl get deployment/$deployment -o yaml")
    unavailable=$(eval "$kubectl describe deployments $deployment" | grep 'unavailable' | head -n 1 | awk '{print $11}')
    debug "unavailable: $unavailable"
  done

  if [ "$unavailable" != "0" ]; then
    # only roll back when we're stuck and the config did not specify any timeout after which to rollback
    if [ -e "$noRollbackMechanism" ]; then
      info "Some pods found to be unavailable, rolling back..."
      eval $cmd_rollback
    fi
    fail "Deployment update failed"
  fi

  info "Updating...SUCCESS!"
}

display_version() {
  info "Running kubectl version:"
  $WERCKER_STEP_ROOT/kubectl version --client
  echo ""
}

main;
