#!/usr/bin/env bash

# -e	errexit		Exits the script immediately if any command returns a non-zero (error) exit status.

# -E	errtrace	Ensures ERR traps (custom error-handling functions) also trigger 
# inside functions, subshells, and command substitutions, not just the top-level script.

# -u	nounset		Treats unset or misspelled variables as an error and exits immediately instead 
# of silently expanding them to an empty string ("").

# -o pipefail		Makes a pipeline (cmd1 | cmd2) fail if any command in the pipe fails, rather than only checking the exit status of the very last command.

set -Eeuo pipefail

# ShopLite shutdown automation
# Usage:
#   ./scripts/down.sh
#   ./scripts/down.sh --purge

echo "=================================="
echo "       Stopping ShopLite"
echo "=================================="

# In this script, we'll be giving it a flag as an argument named "--purge", if the arguments exceeds 1
# or is not the --purge, then the variable purge, which'll be responsible for initiating the loop of network
# and containers stopping; will be setted to false

if [[ "$#" -gt 1 ]]; then
	echo -e "Invalid arguments: $*\nUse --purge as an argument only"
	exit 1
fi

PURGE=false

if [[ "$#" -eq 1 ]]; then
	if [[ "$1"  == "--purge" ]]; then
		PURGE=true
	else
		echo "ERROR: Unknown option: $1"
		echo "Usage: $0 [--purge]"
		exit 1
	fi
fi

# Remove only ShopLite containers
echo "Removing ShopLite containers..."

for container in frontend orders inventory catalog postgres; do
    if docker container inspect "$container" >/dev/null 2>&1; then
        docker rm -f "$container"
    else
        echo "$container does not exist; skipping."
    fi
done

# Remove only ShopLite networks
echo "Removing ShopLite networks..."

for network in frontend-net backend-net; do
    if docker network inspect "$network" >/dev/null 2>&1; then
        docker network rm "$network"
    else
        echo "$network does not exist; skipping."
    fi
done

# Preserve or purge database volume
if [[ "$PURGE" == true ]]; then
    echo "PURGE requested: removing pgdata volume..."

    if docker volume inspect pgdata >/dev/null 2>&1; then
        docker volume rm pgdata
        echo "Database volume removed."
    else
        echo "pgdata does not exist; skipping."
    fi
else
    echo "Database volume pgdata has been preserved."
fi

echo "=================================="
echo "ShopLite stopped successfully!"
echo "=================================="
