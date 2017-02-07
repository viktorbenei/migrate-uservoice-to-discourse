# Migrate from UserVoice to Discourse

## How to run

1. Create a `.bitrise.secrets.yml` file and fill it out:
```
envs:
- USERVOICE_SUBDOMAIN_NAME:
- USERVOICE_API_KEY:
- USERVOICE_API_SECRET:
```
1. Run it with `bitrise run uv`
