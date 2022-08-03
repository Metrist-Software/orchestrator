# Installation

## Ubuntu packages

We have Ubuntu packages for the latest two LTS releases. Here is how you install them (example for 20.04,
22.04 will work the same).

### Downloading and verifying the Debian package

#### Bash shell download and verification instructions

The following steps will download and verify the debian package

```
    sudo apt install wget gnupg
    cd /tmp
    wget -nc http://dist.metrist.io/orchestrator/ubuntu/ubuntu-20.04.latest.txt
    wget -nc http://dist.metrist.io/orchestrator/ubuntu/$(cat ubuntu-20.04.latest.txt)
    wget -nc http://dist.metrist.io/orchestrator/ubuntu/$(cat ubuntu-20.04.latest.txt).asc
    wget -nc https://github.com/Metrist-Software/orchestrator/main/dist/trustedkeys.gpg
    gpg --keyring ./trustedkeys.gpg --verify $(cat ubuntu-20.04.latest.txt).asc
```

#### Fish shell downloand and verification instructions

```
    sudo apt install wget gnupg
    cd /tmp
    wget -nc http://dist.metrist.io/orchestrator/ubuntu/ubuntu-20.04.latest.txt
    wget -nc http://dist.metrist.io/orchestrator/ubuntu/(cat ubuntu-20.04.latest.txt)
    wget -nc http://dist.metrist.io/orchestrator/ubuntu/(cat ubuntu-20.04.latest.txt).asc
    wget -nc https://github.com/Metrist-Software/orchestrator/main/dist/trustedkeys.gpg
    gpg --keyring ./trustedkeys.gpg --verify (cat ubuntu-20.04.latest.txt).asc
```

### Installing the Debian package

Note that it is important to use `apt` and not `dpkg` here - Apt will download dependencies that the
package needs.

   sudo apt install ./$(cat ubuntu-20.04.latest.txt)

### Configuring Orchestrator

Orchestrator runs as a Systemd-controlled service. The canonical way to edit a systemd unit is to
use the following command:

    systemctl edit metrist-orchestrator

### Running Orchestrator

When all is well, you can enable and start Orchestrator as a regular systemd service:

	  systemctl enable metrist-orchestrator
    systemctl start metrist-orchestrator

and use `journalctl` to see whether things are starting as expected.
