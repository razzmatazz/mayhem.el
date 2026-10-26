# The sync layer

`mayhem-sync.el` sits between pages and the Mayhem API.  Pages never
fetch: they read **resources** from a local SQLite store, so they paint
at once, and the store refetches behind them.  This page covers how it
works, the store's schema, and how to add a resource.

The design follows octocat.el's `plans/github-sync-mechanism.md`, but
only its basics are here: one row per resource, and files kept by
their hash.  Entities shared between resources, mutations and prefetch
come when pages need them.

## The idea

1. A page renders, and asks for a resource by its **spec**, such as
   `(run "owner" "project" "target" 1)`.
2. It gets a **snapshot** from the store at once: the data from the
   last fetch, if any, so the page paints without waiting.
3. If that data is stale, a fetch starts in the background, and the
   mode line shows `:loading`.
4. The fetch writes the store.  If the data changed, every page reading
   the resource re-renders; if it didn't, nothing happens.
5. If the fetch failed, the old data stays and the header line says
   `Refresh failed: MSG; g to retry`.  With no data yet, the page shows
   the error in place of the data.

The store is a cache: deleting it loses nothing but speed.

## Resources

A resource is defined beside the page that shows it:

```elisp
(mayhem-sync-define-resource run (owner project target number)
  :fetch (lambda (done) (mayhem--fetch-run owner project target number done))
  :max-age (lambda (data)
             (if (mayhem-run--live-p (alist-get 'run data))
                 mayhem-sync-fresh-for
               mayhem-sync-settled-for)))
```

- The spec is `(NAME . ARGS)`; the properties are evaluated with ARGS
  bound.
- `:fetch` is a function of DONE.  It fetches, usually through
  `mayhem--api-get`, and calls DONE with `(OK DATA)`: the data, or an
  error message.
- DATA must be **plain Lisp data** that prints readably (alists, lists,
  strings, numbers, symbols), since it is stored printed.  Trim it to
  what the page shows (`mayhem--pick`): API objects carry large fields
  pages never use.
- `:max-age` is how long a fetch is reused before opening the page
  refetches it: seconds, or a function of the stored data returning
  them.  The default is `mayhem-sync-fresh-for` (30 s).  `t` means for
  good: data that can no longer change is not refetched, not even by
  `g`.  Keep it for data that is costly to fetch, and make sure a bad
  fetch fails rather than storing something wrong: nothing replaces it.

### Freshness

| Data | `:max-age` | Why |
|---|---|---|
| Most | `mayhem-sync-fresh-for` (30 s) | it changes as runs come and go |
| A workspace's targets | 5 minutes | they come and go rarely, and every `mayhem-jump` asks for each workspace's |
| A finished run (ended, failed or stopped) | `mayhem-sync-settled-for` (a day) | it no longer changes |
| A running run | 30 s, and the page refetches every `mayhem-run-refresh-interval` (10 s) | it is changing |
| A defect, a test case | a day | they change rarely, if ever |
| A finished run's test suite | `t`: for good | it cannot change, and each fetch downloads every file |
| A going run's test suite | 10 minutes | it changes, but each fetch downloads every file |

### Test suites: fetched once, kept by hash

A test suite comes only as a tarball of every file in it, so it is the
costliest thing a page fetches, and the policy is built around not
fetching it again:

- The `testsuite` resource is keyed by run.  A finished run's suite
  can no longer change, so its `:max-age` is `t`: it is downloaded
  once, and neither reopening the page nor `g` downloads it again.  A
  newer run is another key, so its suite is fetched when its page
  first opens.
- While the run is still going, the suite changes as Mayhem optimizes
  it, so it is refetched at most every 10 minutes.
- The tarball is unpacked as it lands.  Each test case goes to the
  `file` table under the sha256 of its bytes (checked against its
  name), and the resource keeps only each one's sha256, size and
  first bytes: a page of 232 test cases reads a few KB, not the files.
  Saving a test case (`w`) reads that one file.
- A fetch that unpacks nothing from a non-empty tarball fails rather
  than storing an empty suite, as one stored for good is never
  replaced.  To fetch suites afresh anyway, delete the store.
- The run's `run-testcases` gives each test case's status (passing or
  failing), type (new or regression), source and age.  The API sends
  each one's full report, about 15 KB, so only those fields are kept,
  and it is refetched no more often than the suite.

`g` (`mayhem-sync-refresh`) refetches every resource on the page,
however fresh, except data kept for good.  Opening a page that is already open refetches only
what is stale.

### The resources

| Resource | Spec arguments | Page |
|---|---|---|
| `me` | | dashboard |
| `projects` | | dashboard, workspace, `mayhem-jump` |
| `workspace-targets` | owner | workspace, `mayhem-jump` |
| `project` | owner project | project |
| `target` | owner project target | target |
| `defect-trend` | owner project target window | project, target (target nil for a project) |
| `run` | owner project target number | run |
| `defect` | owner project target number run | defect |
| `testcase` | owner project target run sha256 | test case |
| `testsuite` | owner project target run | test suite; its files go to the `file` table |
| `run-testcases` | owner project target run | run's Tests (failing tests), test suite (each test case's status, type, source and age), run's test cases |

`mayhem-jump` reads `projects` and `workspace-targets` straight from
the store (`mayhem-sync-read`) and requests them behind its prompt.
Targets are stored with only the fields read (`mayhem--target-summary`),
as projects are, so the prompt opens without reading every target's
whole API alist.  `M-x mayhem-doctor` times these reads on your store,
and `make bench` on a large made-up one.

A resource that needs several requests makes them in one `:fetch`,
at once, with `mayhem--fetch-each`, and stores one alist: `run` holds
the run, its defects, events and progress.

## Reading a resource

```elisp
(vui-defcomponent mayhem-run-page (owner project target number)
  :render
  (let ((snapshot (mayhem-sync-use-resource (list 'run owner project target number))))
    (mayhem-snapshot-view snapshot "run" (mayhem-run--skeleton)
                          (lambda (data) (mayhem-run--render ... data)))))
```

- `mayhem-sync-use-resource` is a hook: call it during render.  On
  mount it subscribes the page to the resource and requests it; on
  unmount it unsubscribes.
- A snapshot is a plist: `:data`, `:fetched-at` (nil until the first
  success), `:error` (the last failure) and `:loading`.
- `mayhem-snapshot-view` shows the data, else a skeleton while
  loading, else the error.  Tell "no data yet" from "empty" by
  `:fetched-at`, not by `:data`.
- A component reading a resource must not be `:memo`: a change
  re-renders the page from its root.
- `mayhem-sync-combine` merges snapshots for a part that needs several.

## Requests

`mayhem-sync-request SPEC &optional FORCE` starts a fetch unless one is
already running for SPEC (requests join it), the stored data is kept
for good (`:max-age` `t`), or, without FORCE, it is fresh.  It returns
at once.  When the fetch calls back:

- success: the data is printed, hashed and written with the time;
  any earlier error is cleared;
- failure: the error is written, the data kept;
- either way, if the snapshot changed (a new hash, or an error set or
  cleared), `mayhem-sync-change-functions` runs with the key, which
  re-renders the subscribed pages, each once.

Which resources are loading is kept in memory only
(`mayhem-sync--loading`), and reported through
`mayhem-sync-loading-functions`, which update the mode lines.

## The store

One SQLite file per Mayhem host:
`mayhem-sync-directory/sync-HOST.sqlite` (by default
`~/.emacs.d/mayhem/sync-app.mayhem.security.sqlite`), opened on first
use in WAL mode with a 2 s busy timeout, so two Emacsen can share it.

### Schema

```sql
CREATE TABLE resource (
  key        TEXT PRIMARY KEY,  -- the spec, printed: (run "o" "p" "t" 1)
  body       TEXT,              -- the data, printed; NULL if never fetched
  hash       TEXT,              -- SHA-1 of body, to tell a change cheaply
  fetched_at REAL,              -- float-time of the last successful fetch
  error      TEXT               -- the last fetch's error, NULL after a success
);

CREATE TABLE file (
  sha256 TEXT PRIMARY KEY,      -- the sha256 of bytes
  bytes  BLOB NOT NULL          -- a test case's file
);
```

- A row with an `error` but no `body` is a resource whose every fetch
  failed.
- Rows are never deleted: a resource no page reads any more just stays.
  Deleting the store's SQLite file is the way to clear it.
- `file` holds files by the sha256 of their bytes, so a row never
  goes stale, and runs and targets share it.  A resource that brings
  files stores them there (`mayhem-sync-put-files`) and keeps only
  their names in its data, so a page reads one file
  (`mayhem-sync-file`) without loading them all.  The `testsuite`
  resource unpacks the suite's tarball as it lands; the tarball
  itself is not kept.
- Emacs binds a string as a BLOB only when it has the `coding-system`
  property `binary`; else it is stored as text, and bytes are lost.

### Versions

The schema version is SQLite's `user_version`, compared with
`mayhem-sync--schema` on opening:

- **Older**: the tables are dropped and created afresh.  The store is a
  cache, so there are no migrations.
- **Newer**: a `user-error`, since an older mayhem.el must not read data
  shaped for a newer one; restart Emacs.

**Bump `mayhem-sync--schema` whenever a resource's data changes shape**
(a field added, renamed or restructured), not only when the table
does.  Otherwise pages read old data in the new shape until it is
refetched.

## Adding a resource

1. Write the fetch in `mayhem-core.el`: `mayhem--fetch-THING`, calling
   back with `(OK DATA)`, DATA trimmed to what the page shows.  Test
   the trimming there if it is not trivial.
2. Define the resource beside its page, with a `:max-age` if its data
   settles.
3. Read it with `mayhem-sync-use-resource` in the page's component.
4. Bump `mayhem-sync--schema` if you changed the shape of an existing
   resource.  A running Emacs applies a bump only when it next opens
   the store.
5. If it brings files, put them in the `file` table and keep their
   sha256s in its data, as `testsuite` does.
6. List any new endpoint in [mayhem-api-usage.md](mayhem-api-usage.md).
