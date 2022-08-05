# How Metrist.io signs distribution packages

All distribution packages are always signed using GnuPG or compatible software. The signature is made
available on dist.metrist.io as a detached, ASCII-armoured signature (`.asc` file).

## Valid keys

This document is the only document that contains a list of valid keys. All keys can be found on the
OpenPGP key server (keys.openpgp.org).

* [C165F320536F922A23CF8E8FDC4C7142A47C86BC](https://keys.openpgp.org/vks/v1/by-fingerprint/C165F320536F922A23CF8E8FDC4C7142A47C86BC)
* [35BE7BF674B27EC1791809D6DC1322606170AD04](https://keys.openpgp.org/vks/v1/by-fingerprint/35BE7BF674B27EC1791809D6DC1322606170AD04)
* [D9E15C9F6ABD85E92BD83B4A9F42A287A4BFCD05](https://keys.openpgp.org/vks/v1/by-fingerprint/D9E15C9F6ABD85E92BD83B4A9F42A287A4BFCD05)

For your convenience, these keys are all collected in (a keyring)[trustedkeys.gpg].

## Commit signing

In order to ensure that you can trace back the history of this document, all commits affecting this document
are signed using the Git `--gpg-sign` option.
