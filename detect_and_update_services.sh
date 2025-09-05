#!/usr/bin/env bash
# Script to detect services and update all repositories

detect_services_for_repo() {
  local repo_dir="$1"
  local init_dir="$repo_dir/rootfs/usr/local/etc/docker/init.d"
  local dockerfile="$repo_dir/Dockerfile"
  local entrypoint="$repo_dir/rootfs/usr/local/bin/entrypoint.sh"
  local services_list=""
  local init_system="tini"
  
  echo "🔍 Analyzing repository: $(basename "$repo_dir")"
  
  # Check if systemd is used instead of tini
  if [ -f "$dockerfile" ] && grep -q "systemd.*enable\|systemctl.*enable" "$dockerfile"; then
    init_system="systemd"
    echo "   📋 Using systemd as init system"
  else
    echo "   📋 Using tini as init system"
  fi
  
  services_list="$init_system"
  
  # Auto-detect services from init.d scripts
  if [ -d "$init_dir" ]; then
    echo "   📂 Scanning init.d directory: $init_dir"
    for script in "$init_dir"/*.sh; do
      if [ -f "$script" ]; then
        # Extract service name (remove number prefix and .sh suffix)
        local service=$(basename "$script" | sed 's/^[0-9]*-//;s|\.sh$||g')
        services_list="$services_list,$service"
        echo "   ✅ Detected service: $service"
      fi
    done
  else
    echo "   ⚠️  No init.d directory found"
  fi
  
  echo "   🎯 Final services list: $services_list"
  echo ""
  
  # Update the entrypoint.sh file if it exists
  if [ -f "$entrypoint" ]; then
    # Update SERVICES_LIST in entrypoint.sh
    sed -i "s/^SERVICES_LIST=.*/SERVICES_LIST=\"$services_list\"/" "$entrypoint"
    echo "   ✏️  Updated SERVICES_LIST in entrypoint.sh"
  else
    echo "   ⚠️  No entrypoint.sh found"
  fi
  
  return 0
}

# Test with bind repo first
echo "🧪 Testing service detection with bind repository"
echo "================================================="
detect_services_for_repo "/root/Projects/github/casjaysdevdocker/bind"

echo ""
echo "🚀 Ready to process all repositories"
echo "===================================="
echo "The script can now:"
echo "1. Auto-detect services from each repo's init.d scripts"  
echo "2. Use tini as default init (or detect systemd if used)"
echo "3. Update each repo's SERVICES_LIST automatically"
echo "4. Apply the enhanced service supervision solution"