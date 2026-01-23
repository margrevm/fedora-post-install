# Fedora post-launch script

A basic Fedora post-installation shell script to bootstrap a fresh workstation installation. Feel free to fork it and tailor it to your own needs.

The script emphasizes **reusability** and **simplicity**: no external libraries, minimal abstraction, and straightforward commands that are easy to review, understand, and modify. Think of it as a small, readable and executable "mission checklist" for a new workstation .

## Features

* Creates a standard user folder structure
* Installs and updates a set of `dnf` & `Flatpak` packages
* Adds and enables third-party repositories when required
* Performs cleanup (removes unwanted packages and unused dependencies)
* Installs RPM fusion and restricted content (fonts, codecs, ..)
* Installs Nvidia drivers
* Optionally clones repositories and applies dotfiles
* Applies a series of GNOME settings & enables extensions
* Custom steps

## Running the script

You can either fork this repo and adapt the `template.cfg` configuration to your needs...

```sh
chmod +x fedora-post-install.bash
./fedora-post-install.bash template.cfg
```

## Use as a submodule in your own repo

... or you can use it as a submodule in your own repo with your custom config file like I did [here](https://github.com/margrevm/gnome-tv-post-install).

```sh
cd YOUR_REPO
git submodule add git@github.com:margrevm/fedora-post-install.git post-install
cp post-install/template.cfg config.cfg
# Now edit your config files according to your needs... 
# ... and execute it
bash post-install/fedora-post-install.bash config.cfg
```

## Notes

* The script is designed to be **interactive** and may prompt for confirmation during execution.
* It requires `sudo` privileges for system-level changes.
* As with any "flight plan", validate your config and run through it once before trusting it for repeatable setups.

## Credits

Created by Mike Margreve and licensed under the MIT License. The original source can be found here: <https://github.com/margrevm/fedora-post-install> - Made with love from 🇧🇪
