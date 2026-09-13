# GPG signing

Place exported private keys ending in `.asc` or `.gpg` in the ignored
`gpg-keys/` directory. Compose mounts that directory read-only at
`/run/gpg-keys`, and the entrypoint imports matching files into the sandbox
user's keyring at startup. It configures loopback pinentry for non-GUI container
use.

Prefer a dedicated signing key without a passphrase, then configure the desired
repository:

```bash
git config commit.gpgsign true
git config user.signingkey YOUR_KEY_ID
```

Never commit an exported key. Every process in the sandbox can potentially read
material imported into the user's keyring, so do not reuse a high-value identity
key when a narrowly scoped signing key will do.
