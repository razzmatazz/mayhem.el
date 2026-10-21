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
| `GET /api/v2/user/me` | the user's `slug`; their name and username on the dashboard |
| `GET /api/v2/user/{slug}/project` | every project visible to the user: dashboard (workspaces) and workspace pages |
| `GET /api/v2/owner/{owner}/target` | a workspace page's targets |
| `GET /api/v2/owner/{owner}/project/{project}` | project page |
| `GET /api/v2/owner/{owner}/project/{project}/target?include_archived=true` | project page's targets, archived ones too |
| `GET /api/v2/owner/{owner}/project/{project}/project-total` | project page's run count and targets passing their tests |
| `GET /api/v2/owner/{owner}/project/{project}/target/{target}` | target page |
| `GET .../target/{target}/run?per_page=5` | target page's latest runs; every page of it, a target's run list |
| `GET /api/v2/owner/{owner}/project/{project}/defect?target_slug={target}&sorted_by=-severity` | target page's defects, most severe first; every page of it, a target's defect list |
| `GET /api/v2/owner/{owner}/defect-trend?project=&target=&window_start_timestamp_seconds=&window_end_timestamp_seconds=&window_step_seconds=` | target page's defect trend |
| `GET .../target/{target}/run/{number}` | run page |
| `GET /api/v2/owner/{owner}/project/{project}/defect?run={run_id}` | run page's defects |
| `GET .../run/{number}/endpoints` | an API run page's endpoints |
| `GET .../run/{number}/event` | run page's event log |
| `GET .../run/{number}/testcase_over_time`, `.../defect_over_time` | code run page's progress chart |
| `GET .../run/{number}/testcase-result` | code run page's failing tests; a run's test cases |
| `GET .../run/{number}/testcase_report/{sha256}` | test case page |
| `GET .../target/{target}/testsuite.tar?run_number={number}&optimized_only=true` | test suite page: the run's suite, a tarball of the files, each named by its sha256 |
| `GET .../target/{target}/testcase` | test suite page: each test case's `source` and `created_at` |
| `GET .../target/{target}/defect/{number}` | defect page |
| `GET .../target/{target}/run/{run}/api/rest/issue/{defect}` | API defect's stack trace, request and response (base64) |
| `GET .../target/{target}/defect/{number}/testcase_report?per_page=100` | code defect's test cases (run, time), and the first's crash, backtrace and reproducer, as the web app's "Example Backtrace" |

- The defect list's `run` filter takes the run's `run_id`, not its
  number; with a number it silently returns nothing.
- The project defect list filters on `target_slug`; a `target`
  parameter is ignored.  `defect-trend`, though, takes `target`, and
  without one gives the whole project's.
- `defect-trend` answers only members of the workspace, as the owner's
  project list does: a 404 shows as a notice, not an error.
- A target's `latest_active_run` is its latest run, whole.
- A run's coverage counts (`n_lines_covered` and the like) are under its
  `run_attributes`.
- `testcase-result` reports are large (the target's memory maps, ~4 KB
  each), so the run page fetches only the failing ones.
- No JSON endpoint lists a test suite: `optimized_only` works only on
  `testsuite.tar` (the CLI's `mayhem download` and the web app's
  "Download Test Suite" use it), and other lists ignore it.  The
  target's `testcase` list is every test case of every run.  The
  tarball pads names with spaces, not NULs.
- A run's `n_optimized_set_testcases` is not the size of its suite: it
  matches `n_testcase_reports` (105) where the suite holds fewer (94),
  and can be 0 where the suite holds every test case.

- `GET /api/v2/owner/{owner}/project` answers only members of the
  workspace (404 "No resource found ... has access to"), so workspace
  pages filter the list of every visible project instead.  The
  owner's target list has no such limit.
- A workspace page groups targets by `owner` + `project_slug` and drops
  targets of projects the user can't see.
- There is no search endpoint: `mayhem-jump` completes on the cached
  project list and each workspace's targets (`mayhem-search.el`).
- Results are cached by `mayhem-sync.el`, so pages paint from the store
  and these requests run behind; see docs/using-vui.md.

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

- `url-http-end-of-headers` is before the blank line ending the
  headers, so a body starts one newline after it: it matters for
  bytes (`mayhem--api-get` with RAW), not for JSON.
- `user/{slug}/project` includes projects you can see but don't own
  (90 for this account), unlike `mayhem list` (none).
- Errors are JSON `{"message": ...}`; 404 for unknown paths and owners.
- `per_page` over 100 is a 400.
