# How mayhem.el uses the Mayhem API

mayhem.el talks to the Mayhem REST API directly.  The `mayhem` CLI is a
fallback only for what the API cannot do (none so far).

## Auth

- Reads `url` and `token` from the CLI's config, `~/.config/mayhem/mayhem`
  (`[DEFAULT]` section; `$XDG_CONFIG_HOME` respected).  Override with
  `mayhem-config-file`.
- Sends `X-Mayhem-Token: token <token>` on every request.
- No config or token: `user-error` telling the user to run `mayhem login`.

## Helpers (`mayhem-core.el`)

| Function | Use |
|---|---|
| `mayhem--api-get PATH PARAMS CALLBACK` | one async GET; CALLBACK gets `(OK DATA)` |
| `mayhem--api-get-all PATH KEY CALLBACK` | every page of the list under KEY |
| `mayhem--api-response STATUS` | pure: response buffer to `(OK DATA)` |

- Built on `url.el`; no extra dependency.
- JSON comes back as alists and lists; `null` and `false` are `nil`.
- On failure DATA is a message: `HTTP 404: <message>`, or the url.el error
  (e.g. `connection-failed ...`).
- Shape responses in pure, tested functions, e.g. `mayhem--group-targets`.

## Pagination

- `per_page=100` (the API's max), `offset` stepping by 100.
- Stops on a short page: target lists have no `count` field.

## Endpoints in use

| Endpoint | For |
|---|---|
| `GET /api/v2/user/me` | the user's `slug` |
| `GET /api/v2/user/{slug}/project` | dashboard: every project visible to the user |
| `GET /api/v2/owner/{owner}/target` | dashboard: targets, one request per owner |

- The dashboard groups targets by `owner` + `project_slug` and drops
  targets of projects the user can't see.
- Per owner, not per project: ~23 requests instead of ~90.

## Finding endpoints

- Spec: `/api/v2/api-docs/json` (copy in `docs/mayhem-openapi.json`).
  It lists only 22 paths.
- The web app uses many more; search its JS bundle
  (`/assets/index-*.js`) for `/api/v2/`.  `user/{slug}/project` and
  `user/{slug}/org` come from there.
- Try with curl before writing code:

  ```sh
  tok=$(sed -nE 's/^token[[:space:]]*=[[:space:]]*//p' ~/.config/mayhem/mayhem)
  curl -H "X-Mayhem-Token: token $tok" https://app.mayhem.security/api/v2/user/me
  ```

## Gotchas

- `user/{slug}/project` includes projects you can see but don't own
  (90 for this account), unlike `mayhem list` (none).
- Errors are JSON `{"message": ...}`; 404 for unknown paths and owners.
- `per_page` over 100 is a 400.
