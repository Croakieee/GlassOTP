# TODO

## Features

* Separate Import and Export buttons in the UI
* Add a "Delete All" button for tokens
* Remove redundant UI elements (e.g. duplicate close button in Add Token window)
* Add a log message for successful backup import
* Implement internal automatic backup:

  * Store backups in a fixed absolute path
  * On reinstall, prompt user to restore from auto-backup

## Known Issues

* Thread priority issue:

  * File: `UI/AddTokenSheet.swift:486`
  * Description: A thread running at User-interactive QoS is waiting on a lower QoS thread (Default)
  * Status: Investigation ongoing to prevent priority inversion

* Minor UI issue:

  * Timer slider may shift out of position

* Update process issues:

  * Repeated password prompts requesting access to write to the keychain
  * Work in progress

* Token refresh delay:

  * Minor delays after system wake from sleep
  * Needs optimization
