# Ubuntu 24.04 Workshop Environments

This directory contains scripts, configuration files and supporting material for building technical workshop environments on Ubuntu 24.04 LTS.

The workshop material is intended primarily for instructor-led networking and Internet infrastructure training. Each workshop is maintained as a self-contained environment with its own installation instructions, dependencies, configuration and troubleshooting information.

## Using the Workshop Material

Before installing a workshop environment, read the `README.md` contained within the relevant workshop directory.

Individual workshops may have different requirements. These can include:

* additional Ubuntu packages
* Docker containers
* network configuration
* virtual routers or other network devices
* software images that cannot be distributed through this repository
* workshop-specific configuration files
* browser-based or command-line access methods

The installation script within each workshop directory should be used to prepare a new Ubuntu 24.04 workshop VM.

Where possible, installation scripts are designed to automate the complete setup while keeping workshop-specific runtime files under:

```text
~/virtual_labs/
```

## Workshop VMs

A dedicated Ubuntu 24.04 LTS virtual machine is recommended for each workshop environment.

Before running an installation script, ensure that:

* Ubuntu 24.04 LTS is installed and updated as required
* the VM has Internet access for downloading required packages
* sufficient CPU, memory and disk space have been allocated
* any required software images or licensed software are available
* you have `sudo` access to the VM

Some workshop installation scripts may perform a system upgrade, install Docker, modify network settings, enable IP forwarding, install firewall rules or install additional system services. Review the workshop README and installation script before running it on an existing system.

## Installation

Installation commands vary between workshops.

Typically, change to the required workshop directory, review its README, make the installation script executable and run it with `sudo`.

For example:

```bash
chmod +x setup_*.sh
sudo ./setup_*.sh
```

Do not assume that options or requirements documented for one workshop apply to another.

## Workshop Files

Installation scripts may copy workshop files from the repository into the user's runtime environment.

The standard location for these runtime files is:

```text
~/virtual_labs/
```

This separates the source material in the GitHub repository from the working lab environment.

Changes made while running a workshop should therefore not normally modify the original files in the cloned repository.

## Licensed Software and Images

Some workshops may require software or virtual device images that cannot be distributed through this repository.

These files are **not included** unless redistribution is permitted.

Examples may include network operating system images such as Cisco IOS.

Users are responsible for obtaining required software from an authorised source and complying with the applicable software licence.

Refer to the individual workshop README for the required filename and installation location.

## Starting and Stopping Workshops

The method used to start, check and stop a workshop depends on the environment.

Where provided, use the workshop's helper scripts rather than manually starting or terminating individual processes.

Refer to the workshop README for:

* starting the lab
* stopping the lab
* checking lab status
* accessing virtual devices
* recovering a failed lab
* troubleshooting

## Network and Firewall Configuration

Some workshop environments require IP forwarding, listening network services, Docker networking or firewall configuration.

Workshop installation scripts may provide optional firewall configuration using `iptables` and `ip6tables`.

Review the firewall requirements before exposing a workshop VM to an untrusted network or the Internet.

Existing firewall policies should also be reviewed before enabling workshop-provided rules, particularly on remotely administered systems.

## Security

Workshop environments are designed for controlled technical training rather than general-purpose production hosting.

Before making a workshop VM accessible outside the training network:

* review listening services and ports
* review firewall rules
* replace self-signed certificates where appropriate
* change default or generated workshop credentials where necessary
* restrict administrative access
* remove unnecessary services
* ensure licensed software and configuration files are not unintentionally exposed

Individual workshop READMEs may contain additional security requirements.

## Troubleshooting

Start with the `README.md` in the relevant workshop directory.

Installation scripts may also create log files or provide status and diagnostic commands. These are documented within the individual workshop instructions.

When troubleshooting, check the workshop components separately rather than reinstalling the entire VM unless the workshop documentation specifically recommends doing so.

## Previous Ubuntu 18.04 Workshops

These workshop environments are being migrated from an earlier Ubuntu 18.04 workshop repository.

The previous material is retained for reference at:

https://github.com/waz-here/Ubuntu18.04/tree/master/workshops

The Ubuntu 18.04 documentation should not be assumed to apply to the Ubuntu 24.04 environments. Dependencies, installation methods, package availability and workshop access methods may have changed.

Where a workshop has been migrated, use the documentation supplied with the Ubuntu 24.04 version.

## Contributions and Updates

Workshop environments should remain self-contained so that changes to one workshop do not require changes to unrelated workshop documentation.

When adding or updating a workshop:

* include a workshop-specific `README.md`
* document operating system and software requirements
* document any external or licensed files required
* provide installation instructions
* document how to start and stop the environment
* include appropriate troubleshooting information
* avoid committing passwords, private keys or licensed software images

Test installation scripts on a clean Ubuntu 24.04 LTS VM before using them for a workshop.

## Previous Workshop Repository

Ubuntu 18.04 workshop material:

https://github.com/waz-here/Ubuntu18.04/tree/master/workshops
