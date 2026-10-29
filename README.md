# gh-watch — herdr plugin

Get told when something happens on your GitHub PRs, without an agent polling for it.

A small webhook receiver (Python standard library only) listens on `127.0.0.1:8787/github`. For a repo you list, it reacts to:

- a submitted review, a new PR comment or inline code comment,
- a finished CI run (`workflow_run`),
- a merged PR.

Each event shows a herdr notification. If an agent pane is idle in a checkout (or any worktree) of that repo, preferring the one on the PR's branch, it also gets one line:

```
[gh-watch, automated] new review (changes_requested) on PR #7 in acme/app. Rules: look with `gh pr checks 7` ...
```

The agent then reads the PR itself with `gh`. Events from the same PR are debounced for 20 seconds.

## Install

Needs herdr ≥ 0.9.1, Linux, `python3`, `git`, and the `gh` CLI (logged in) for your agents.

```sh
herdr plugin install thientrile/herdr-gh-watch
```

The receiver starts with herdr. On first start it writes a random webhook secret to the plugin config dir:

```sh
cfg="$(herdr plugin config-dir thientrile.gh-watch)"
```

Actions: `herdr plugin action invoke thientrile.gh-watch.status` and `thientrile.gh-watch.restart`. Logs: `$HERDR_PLUGIN_STATE_DIR/receiver.log` (usually `~/.local/state/herdr/plugins/thientrile.gh-watch/`).

## Configure

All files live in `$cfg`; see [`examples/`](examples). Only `repos.tsv` is needed. Files other than `secret` are re-read on every event, so editing them needs no restart.

| File | What it holds |
| --- | --- |
| `secret` | Webhook secret, created on first start (mode 600). Paste it into GitHub; never commit it. |
| `repos.tsv` | `owner/name<TAB>/local/path`, one per line. Events for other repos are ignored. |
| `ignore_users` | GitHub logins, one per line. Reviews and comments they write are skipped (CI results and merges are not). Put your own login here. |
| `notify_cmd` | Optional. A command that gets `GitHub: <title>` as its last argument, e.g. a Telegram sender. Skipped when the file is missing or the command fails. |
| `review_repos` | Optional. Repos (`owner/name`, one per line) that get one automated review when a PR is opened or marked ready. |
| `review_cmd` | Optional, needed for reviews. The reviewer command, e.g. `claude -p`. An argument containing `{prompt}` gets the prompt; otherwise the prompt goes to stdin. Its output is posted as a PR review comment starting with `gh-watch-review:`. |
| `review_prompt.txt` | Optional. Replaces the default review prompt, e.g. to describe your project's conventions or ask for another language. The diff is appended after it. |
| `tunnel_cmd` | Optional. A tunnel command (e.g. `cloudflared tunnel run gh-watch`) started with the receiver and stopped with it; its output goes to `receiver.log`. Read at start only, so restart after editing. Leave it out if you run your tunnel some other way. |

Lines starting with `#` are comments. The port is `GH_WATCH_PORT` (default 8787); `GH_WATCH_DRY_RUN=1` logs what would be sent instead of sending it.

## Expose the receiver

The receiver binds to `127.0.0.1` only. Put a tunnel in front of it, for example:

```sh
cloudflared tunnel --url http://127.0.0.1:8787     # quick tunnel; see below for a stable URL
ngrok http 8787
```

Any reverse proxy works as long as it forwards `POST /github` with its headers.

### Stable custom domain

Quick tunnels change URL on every start, so the webhook breaks. For a fixed hostname:

**cloudflared named tunnel** (domain on Cloudflare):

```sh
cloudflared tunnel login
cloudflared tunnel create gh-watch
cloudflared tunnel route dns gh-watch gh-watch.example.com
```

`~/.cloudflared/config.yml`:

```yaml
tunnel: gh-watch
credentials-file: /home/you/.cloudflared/<tunnel-id>.json
ingress:
  - hostname: gh-watch.example.com
    service: http://127.0.0.1:8787
  - service: http_status:404
```

Run it with `cloudflared tunnel run gh-watch`.

**ngrok reserved domain**: reserve a domain in the ngrok dashboard, then run `ngrok http --url=gh-watch.example.com 8787`.

The webhook Payload URL is then `https://gh-watch.example.com/github`. To have the plugin start and stop the tunnel, put the run command in `$cfg/tunnel_cmd` (see [`examples/tunnel_cmd`](examples/tunnel_cmd)).

## Create the GitHub webhook

In the repo (or org): Settings → Webhooks → Add webhook.

- Payload URL: `https://<your-tunnel-host>/github`
- Content type: `application/json`
- Secret: the contents of `$cfg/secret` (e.g. `xclip -sel clip < "$cfg/secret"`)
- Events: "Let me select individual events" → Pull requests, Pull request reviews, Pull request review comments, Issue comments, Workflow runs.

GitHub sends a `ping` first; a green check means the signature matched. Then add the repo to `repos.tsv`.

## Security

- Every request must carry a valid `X-Hub-Signature-256` HMAC for the secret, or it gets 401. Only `/github` is served; bodies over 1 MB are refused.
- Webhook payload text never reaches an agent prompt. PR titles, comments, review bodies and branch names are attacker-controlled; the line sent to an agent is fixed text built from event types, numbers and sanitized identifiers (`[A-Za-z0-9._/-]` only). The agent is told that text read through `gh` is data, not instructions, never to push to the default branch, and to merge only when its project explicitly allows it.
- The automated review sends the PR diff, which is untrusted, to `review_cmd`. It runs in an empty temp directory, and the prompt tells the model the diff is data, but use a reviewer mode without tools or shell access anyway. Its output is posted publicly on the PR.
- Anyone who can open a PR or comment on a listed repo can trigger notifications. For public repos, keep `review_repos` to repos where that is acceptable.

## Develop

```sh
herdr plugin link "$PWD"
python3 test_receiver.py     # describe(), the workflow_run PR lookup, the signature check, herdr failures and tunnel_cmd; no herdr needed
HERDR_PLUGIN_CONFIG_DIR="$cfg" python3 receiver.py --review-once owner/repo 12   # print a review without posting it (add --post to post)
```

## License

MIT
