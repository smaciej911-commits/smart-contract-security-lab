# Contributing

Contributions that improve the explanations, patch models, or regression tests
are welcome.

Before opening a pull request, run from the repository root:

```sh
forge fmt --check
forge build --sizes
forge test -vvv
```

The historical Parity fork test is optional and requires an archive RPC URL;
keep credentials in an ignored environment file or an environment variable.
Never commit RPC credentials, private keys, or wallet files.

When changing a vulnerability or mitigation, update the corresponding case
README and add or adjust a regression or invariant test. Keep vulnerable
examples clearly isolated from fixed models.
