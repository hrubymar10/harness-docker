# AWS credential proxy

The entrypoint can generate AWS CLI profiles that retrieve short-lived
credentials from an independently managed host proxy. The sandbox does not
start or own that service.

Set `AWS_AI_PROXY_PROFILE_CONFIG` to a comma-separated list of profile mappings.
For each entry, startup writes an AWS `credential_process` stanza under the
sandbox user's `~/.aws/config`. `AWS_AI_PROXY_URL` selects the proxy endpoint and
defaults to `http://host.docker.internal:9998`.

The generated configuration exposes only what the external proxy authorizes.
Refresh expired authentication on the host, and do not treat this integration as
a substitute for least-privilege AWS policy.
