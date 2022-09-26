# How Metrist.io signs distribution packages

All distribution packages are always signed using GnuPG or compatible software. The signature is made
available on dist.metrist.io as a detached, ASCII-armoured signature (`.asc` file).

## Valid keys

The keys that are allowed to sign distribution packages are listed in (the distribution keyring)[trustedkeys.gpg]. You can download
this keyring and point GnuPG at it using the `--keyring` option for verification purposes.

## Commit signing

In order to ensure that you can trace back the history of this document, all commits affecting this document
are signed using the Git `--gpg-sign` option.
