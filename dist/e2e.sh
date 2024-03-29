#!/usr/bin/env bash
#
#  This script is primarily intended to be used with the Vagrant definitions in each dist folder
#  A monitor should be setup in the account for which $TEST_API_TOKEN belongs to (testsignal is a good option)
#

# Oddly enough even after yum remove or apt remove the orchestrator is still running. Clean that up
StopAndDisableOrchestrator() {
    sudo systemctl stop metrist-orchestrator
    sudo systemctl disable metrist-orchestrator
    sudo systemctl daemon-reload
}

RemoveOrchestrator(){
    StopAndDisableOrchestrator

    if type apt >/dev/null; then
        sudo apt purge -y metrist-orchestrator
    elif type dnf >/dev/null; then
        sudo dnf remove -y metrist-orchestrator
    elif type yum >/dev/null; then
        sudo yum remove -y metrist-orchestrator
    fi
}

Main() {

# Sanitize DIST env var before using it for instance id - remove forward slashes, hyphens, and periods
DIST=${DIST//[\/\.\-]/}

if [ ! -f /tmp/install.sh ]; then
    curl https://dist.metrist.io/install.sh >/tmp/install.sh
fi

cat <<EOF | bash /tmp/install.sh
$TEST_API_TOKEN
e2e_test_$DIST
EOF

sleep 60

LOGS=$(sudo journalctl --unit metrist-orchestrator --since "1m ago" --no-pager)
echo "$LOGS"
SUCCESS_COUNT=$(echo "$LOGS" | grep -c "All steps done, asking monitor to exit")

if [ $SUCCESS_COUNT -gt 0 ]; then
    RemoveOrchestrator
    echo "e2e successful"
    exit 0
else
    RemoveOrchestrator
    echo "Error during e2e, can't find 'All steps done'"
    exit 1
fi

}

Main
