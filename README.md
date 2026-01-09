## Fedora post-installation script

A basic Fedora post-installation shell script to bootstrap a fresh workstation installation. Feel free to fork it and tailor it to your own needs.

The script emphasizes **reusability** and **simplicity**: no external libraries, minimal abstraction, and straightforward commands that are easy to review, understand, and modify.

## Features

* Creates a standard user folder structure
* Installs and updates a baseline set of DNF packages and applications
* Installs selected Flatpak applications
* Adds and enables third-party repositories when required
* Performs cleanup (removes unwanted packages and unused dependencies)
* Installs RPM fusion and restricted content (fonts, codecs, ..)
* Installs Nvidia drivers
* Optionally clones repositories and applies dotfiles

## Running the script

```sh
chmod +x fedora-postinstall.sh
./fedora-postinstall.sh
```

## Supported versions

* Fedora Workstation 44

## Notes

* The script is designed to be **interactive** and may prompt for confirmation during execution.
* It requires `sudo` privileges for system-level changes.
* Review the script contents before running it on a production system.

## Credits

Created by Mike Margreve ([mike.margreve@outlook.com](mailto:mike.margreve@outlook.com)) and licensed under the MIT License. The original source can be found here: [https://github.com/margrevm/fedora-post-install](https://github.com/margrevm/fedora-post-install)
