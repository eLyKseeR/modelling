# Distribution

The _Distribution_ copies the chunks of assemblies to (PUT) or from (GET) one or more _sinks_, e.g. a second disk or an S3 object store. The chunks are encrypted and the _Distribution_ never sees keys.

## Sinks

![Sinks](./out/services.uml/distribution/distribution%20sinks.png)

A `sink` has a name, credentials, a connection, the local chunk directory (a key `K` resolves to `localchunks/K`) and a `retrypolicy`.

Implementations of the `SINK` interface:

* `FSSink`: copies chunk files to a directory (`fsbasepath`).
* `S3Sink`: uses an S3 compatible object store (`protocol`, `host`, `port`, `bucket`, `prefix`; the access keys are the credentials). The low-level access (`s3_put_object`, `s3_get_object`, `s3_list_objects`) is axiomatic; the decisions are Rocq code.

`put` and `get` return a `copy_result`:

| result | meaning |
|---|---|
| `Copied` | the chunk was copied |
| `Present` | the chunk was already at the target |
| `Retry code` | transient failure, worth another attempt |
| `Failed code` | permanent failure |

## Plan

![Plan](./out/services.uml/distribution/distribution%20plan.png)

The chunk keys of an assembly are `ab/cd/<cid>.lxr` (`enumerate_chunk_keys`). `plan` distributes them over the sinks according to weights (`distribute_by_weight`; the weights must be valid for the number of sinks and chunks): e.g. weights 4 and 8 give the first sink 4 chunks and the second one the next 8.

## Schedule

![Run](./out/services.uml/distribution/distribution%20run.png)

`run` tries every planned (sink, chunk) pair, and retries transient failures with an exponential backoff: `delay = min(max_delay_ms, base_delay_ms * 2^attempt)`.

![Retry](./out/services.uml/distribution/distribution%20retry.png)

The `retrypolicy` has `max_attempts` (at least one attempt is always made), `base_delay_ms`, `max_delay_ms` and `deadline_ms` (time budget per chunk, counted from its first attempt). The scheduler is a pure function, parameterised over the copy function and the clock.

`run_ok` decides the outcome: a **PUT** has to reach every planned sink, a **GET** needs every chunk from at least one sink (`restore_ok`).

## Proved properties

The Rocq sources prove among others: the plan covers all chunks (`plan_covers`), the number of attempts is bounded (`attempts_bounded`), the deadline is respected (`deadline_respected`), every entry is tried at least once (`tried_at_least_once`), a reported success is the result of `put`/`get` (`run_ok_was_copied`), and a successful restore is complete (`restore_ok_complete`).

## Configuration

The sinks are configured in a JSON file (`sinks.json`): a list of sinks with `type` (`S3` or `FS`), `name`, `credentials`, `access`, and an optional `retry`. Remote protocols must be `https` (`http` only for localhost), and a file with inline secrets must have mode 600.
