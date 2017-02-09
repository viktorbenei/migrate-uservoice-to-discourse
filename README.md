# Migrate from UserVoice to Discourse

Migrate open feature requests from [UserVoice](https://www.uservoice.com/) to [Discourse](http://www.discourse.org/),
using the UserVoice and Discourse APIs.

## How it works?

Similar to [the Discourse GitHub importer](https://meta.discourse.org/t/introducing-github-issues-to-discourse/46671)
([GitHub](https://github.com/discourse/github-issues-to-discourse)) in that
it uses APIs to do the migration and not backups / through database, but unlike
the official GitHub importer there's no UI for this script,
you have to set the parameters and run the script.

The script:

1. Creates a new Topic on your Discourse forum (in the specified Category) for every open UserVoice feature request.
   Includes a link to the original feature request in the post created on your Discourse.
1. Re-creates all the comments from the UserVoice feature request in the Discourse Topic
1. Then closes the UserVoice feature request, leaving a comment with a link to the new URL (on your Discourse)

__If you set a vote count limit__, the script will close the feature requests on UserVoice which are under
the vote count limit, and won't create a Topic on Discourse for these feature requests (only for those
which have equal or more votes than the limit). It will still leave a comment which mentions
where the user can re-create the feature request (on Discourse).

Couple of highlights / notes:

- only migrates open feature requests, neither "completed" nor "declined" ones are migrated
- it does close the feature requests it migrates, with "completed" state
- if a vote count limit is set, the script will only create Topics on your Discourse
  if the UserVoice fature request has at least as many votes as the limit


## How to run

### Using the [Bitrise CLI](https://github.com/bitrise-io/bitrise)

1. Install the [Bitrise CLI](https://github.com/bitrise-io/bitrise#install-and-setup)
1. Git clone this repo, and `cd` into the directory
1. Create a `.bitrise.secrets.yml` file (in this directory, where the `bitrise.yml` file is located) and fill it out:
```
envs:
# --- USERVOICE
- USERVOICE_SUBDOMAIN_NAME:
- USERVOICE_API_KEY:
- USERVOICE_API_SECRET:
- USERVOICE_MIN_VOTE_COUNT_TO_MIGRATE: 0
# specify this in case you have more than one forums
- USERVOICE_FORUM_ID:

# --- DISCOURSE
- DISCOURSE_DOMAIN: http://your.discourse.domain
- DISCOURSE_USERNAME:
- DISCOURSE_API_KEY:
- DISCOURSE_CATEGORY_TO_MIGRATE_INTO: e.g. "Feature Requests"
```
1. Run the migration with `bitrise run migrate`

### Without the Bitrise CLI

1. Git clone this repo, and `cd` into the directory
1. Set the environment variables listed above (e.g. `export USERVOICE_SUBDOMAIN_NAME=myuservoicedomein USERVOICE_API_KEY=...`)
1. Run: `bundle install && bundle exec ruby migrate.rb`


## Development

### UserVoice infos

- `state` of a feature request ("suggestion"):
    - published: "No status" / requests without any status. E.g. when a user creates the suggestion and admins do not set "status" or "update status" yet.
    - approved: under review + planned + started
    - closed: completed + declined
- `status` of a feature request ("suggestion"):
    - No status (nil)
    - under review
    - planned
    - started
    - completed
    - declined
