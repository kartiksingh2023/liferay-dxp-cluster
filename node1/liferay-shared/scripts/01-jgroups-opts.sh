#!/bin/bash
# Appends JGroups args to the existing setenv.sh inside the container.
# Runs before Tomcat starts via Liferay's /mnt/liferay/scripts/ hook.

SETENV="/opt/liferay/tomcat/bin/setenv.sh"

if ! grep -q "jgroups.tcpping.initial_hosts" "$SETENV"; then
  echo '' >> "$SETENV"
  echo 'CATALINA_OPTS="$CATALINA_OPTS -Djgroups.bind_addr=liferay-node1"' >> "$SETENV"
  echo 'CATALINA_OPTS="$CATALINA_OPTS -Djgroups.tcpping.initial_hosts=liferay-node1[7800]"' >> "$SETENV"
  echo "export CATALINA_OPTS" >> "$SETENV"
  echo "[cluster-init] JGroups opts appended to setenv.sh (Node 1)"
else
  echo "[cluster-init] JGroups opts already present, skipping."
fi
