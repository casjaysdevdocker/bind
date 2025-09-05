#!/usr/bin/env bash
# Enhanced functions for proper service supervision

# Enhanced __no_exit function with service monitoring
__no_exit() {
  local monitor_services="${SERVICES_LIST:-tini,named,nginx,php-fpm}"
  local check_interval="${SERVICE_CHECK_INTERVAL:-30}"
  local max_failures="${MAX_SERVICE_FAILURES:-3}"
  local failure_counts=""
  
  # Initialize failure counters
  IFS=',' read -ra services <<< "$monitor_services"
  for service in "${services[@]}"; do
    failure_counts["$service"]=0
  done
  
  echo "Starting service supervisor - monitoring: $monitor_services"
  echo "Check interval: ${check_interval}s, Max failures: $max_failures"
  
  # Set up trap to handle termination
  trap 'echo "🛑 Container terminating - cleaning up services"; kill $(jobs -p) 2>/dev/null; rm -f /run/*.pid /run/init.d/*.pid; exit 0' TERM INT
  
  # Main supervision loop
  while true; do
    local failed_services=""
    local running_services=""
    
    # Check each service
    IFS=',' read -ra services <<< "$monitor_services"
    for service in "${services[@]}"; do
      service="${service// /}" # trim whitespace
      [ -z "$service" ] && continue
      
      if __pgrep "$service" >/dev/null 2>&1; then
        running_services="$running_services $service"
        failure_counts["$service"]=0  # reset failure count on success
      else
        failed_services="$failed_services $service"
        failure_counts["$service"]=$((${failure_counts["$service"]:-0} + 1))
        
        echo "⚠️  Service '$service' not running (failure ${failure_counts["$service"]}/$max_failures)"
        
        # Check if we've exceeded max failures for this service
        if [ ${failure_counts["$service"]} -ge $max_failures ]; then
          echo "💥 Service '$service' failed $max_failures times - terminating container"
          echo "Failed services: $failed_services"
          echo "Running services: $running_services"
          kill -TERM 1  # Send TERM to init process (PID 1)
          exit 1
        fi
      fi
    done
    
    # Log status every 10 checks (5 minutes with 30s interval)
    if [ $(($(date +%s) % 300)) -lt $check_interval ]; then
      echo "📊 Service status - Running:$running_services Failed:$failed_services"
      # Write to start.log for backward compatibility
      echo "$(date): Services running:$running_services failed:$failed_services" >> "/data/logs/start.log"
    fi
    
    sleep "$check_interval"
  done &
  
  # Keep the original behavior for log tailing
  [ -f "/data/logs/start.log" ] && tail -f "/data/logs/start.log" >/dev/null 2>&1 &
  
  wait
}

# Enhanced __start_init_scripts function with better error handling
__start_init_scripts() {
  set -e
  trap 'echo "❌ Fatal error in service startup - killing container"; rm -f /run/__start_init_scripts.pid; kill -TERM 1' ERR
  
  [ "$1" = " " ] && shift 1
  [ "$DEBUGGER" = "on" ] && echo "Enabling debugging" && set -o pipefail -x$DEBUGGER_OPTIONS || set -o pipefail
  
  local basename=""
  local init_pids=""
  local retstatus="0"
  local initStatus="0"
  local failed_services=""
  local successful_services=""
  local init_dir="${1:-/usr/local/etc/docker/init.d}"
  local init_count="$(find "$init_dir" -name "*.sh" 2>/dev/null | wc -l)"
  
  if [ -n "$SERVICE_DISABLED" ]; then
    echo "$SERVICE_DISABLED is disabled"
    unset SERVICE_DISABLED
    return 0
  fi
  
  echo "🚀 Starting container services initialization"
  echo "Init directory: $init_dir"
  echo "Services to start: $init_count"
  
  # Create a new PID file to track this startup session
  echo $$ > /run/__start_init_scripts.pid
  
  mkdir -p "/tmp" "/run" "/run/init.d" "/usr/local/etc/docker/exec" "/data/logs/init"
  chmod -R 777 "/tmp" "/run" "/run/init.d" "/usr/local/etc/docker/exec" "/data/logs/init"
  
  if [ "$init_count" -eq 0 ] || [ ! -d "$init_dir" ]; then
    echo "⚠️  No init scripts found in $init_dir"
    # Still create a minimal keep-alive for containers without services
    while true; do 
      echo "$(date): No services - container keep-alive" >> "/data/logs/start.log"
      sleep 3600
    done &
  else
    echo "📋 Found $init_count service scripts to execute"
    
    if [ -d "$init_dir" ]; then
      # Remove sample files
      find "$init_dir" -name "*.sample" -delete 2>/dev/null
      
      # Make scripts executable
      find "$init_dir" -name "*.sh" -exec chmod 755 {} \; 2>/dev/null
      
      # Execute scripts in order
      for init in "$init_dir"/*.sh; do
        if [ -x "$init" ]; then
          basename="$(basename "$init")"
          service="$(printf '%s' "$basename" | sed 's/^[0-9]*-//;s|\.sh$||g')"
          
          printf '\n🔧 Executing service script: %s (service: %s)\n' "$init" "$service"
          
          # Execute the init script
          if eval "$init"; then
            sleep 3  # Give service time to start
            
            # Verify the service actually started
            retPID=$(__get_pid "$service")
            if [ -n "$retPID" ]; then
              initStatus="0"
              successful_services="$successful_services $service"
              printf '✅ Service %s started successfully - PID: %s\n' "$service" "$retPID"
            else
              initStatus="1"
              failed_services="$failed_services $service"
              printf '❌ Service %s failed to start (no PID found)\n' "$service"
            fi
          else
            initStatus="1" 
            failed_services="$failed_services $service"
            printf '💥 Init script %s failed with exit code %s\n' "$init" "$?"
          fi
        else
          printf '⚠️  Script %s is not executable, skipping\n' "$init"
        fi
        
        retstatus=$(($retstatus + $initStatus))
      done
      
      echo ""
      printf '📊 Service startup summary:\n'
      printf '   ✅ Successful: %s\n' "${successful_services:-none}"
      printf '   ❌ Failed: %s\n' "${failed_services:-none}"
      printf '   📈 Total status code: %s\n' "$retstatus"
      
      # If any critical services failed, exit the container
      if [ $retstatus -gt 0 ]; then
        echo "💥 Service startup failures detected - container will terminate"
        echo "This allows the orchestrator (Docker/Kubernetes) to restart the container"
        rm -f /run/__start_init_scripts.pid
        exit $retstatus
      fi
    fi
  fi
  
  # Write startup completion status
  {
    echo "$(date): Container startup completed"
    echo "Successful services: $successful_services"
    [ -n "$failed_services" ] && echo "Failed services: $failed_services" 
    echo "Status code: $retstatus"
  } >> "/data/logs/start.log"
  
  printf '🎉 Service initialization completed successfully\n\n'
  return $retstatus
}

# Export the enhanced functions
export -f __no_exit __start_init_scripts