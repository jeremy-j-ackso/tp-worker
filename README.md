# tp-worker

A prototype job worker service that provides an API to run arbitrary Linux
processes. These processes can be any executable program that is available on
the machine running the service, such as `ls -lha`.

## Prototype Goals

### Library

- [ ] Worker library with methods to start/stop/query status of a job.
- [ ] Library should be able to stream the output of a running job.
  - [ ] Discovering new output should be efficient, avoid busy-waiting or
        polling.
  - [ ] Output should be from start of process execution.
  - [ ] Multiple concurrent clients should be supported.
  - [ ] Do not make any assumptions about the process's output - it may be text
        or raw binary data.

### API

- [ ] [GRPC](https://grpc.io) API to start/stop/get status/stream output of a running process.
- [ ] Use mTLS authentication and verify client certificate. Set up strong set
      of cipher suites for TLS and good crypto setup for certificates. Do not
      use any other authentication protocols on top of mTLS.
- [ ] Use a simple authorization scheme.

### Client

- [ ] CLI should be able to connect to worker service and start, stop, get
      status, and stream output of a job.

## Repository Organization & Conventions

The repository follows
[standard Go conventions on module organization](https://go.dev/doc/modules/layout).

```sh
tp-worker/
  go.mod
  go.sum
  cmd/
    tp-worker-server/
      tp-worker-server.go
    tp-worker-client/
      tp-worker-client.go
  internal/
    authn/
      authn.go
      authn_test.go
    authz/
      authz.go
      authz_test.go
    job/
      job.go
      job_test.go
    output-storage/
      output-storage.go
      output-storage_test.go
  job/
    job.go
    job_test.go
```

As much as possible, following [Effective Go](https://go.dev/doc/effective_go)
coding conventions will be adhered to. This should help in avoiding some common
pitfalls such as data races, crashes, concurrency issues, deadlocks, etc.

Testing will focus primarily on happy path, with added tests for intentional
error conditions, such as when a command is not found, output is not found, user
doesn't have authorization, etc. Extensive mocking, table-driven tests, fuzzing,
and mutation testing could be added later as unintentional error conditions are
discovered, but are not within scope at this time.

Since an adequate starting point for gRPC with mTLS is provided as an example in
the
[`grpc-go` repository,](https://github.com/grpc/grpc-go/tree/master/examples/features/encryption/mTLS)
that will be used as an initial base for the server and client implementations
to grow out of.

## Usage Examples

### Environment Variables

#### Server
```sh
TP_WORKER_IP=127.0.0.1                          # --ip-addr
TP_WORKER_PORT=8080                             # --port
TP_WORKER_USER_CERTDIR=/path/to/cert/dir/       # --user-certs
TP_WORKER_PRIVATE_KEY=/path/to/private/key.pem  # --private-key
```

#### Client
```sh
TP_WORKER_IP=127.0.0.1                                # --ip-addr
TP_WORKER_PORT=8080                                   # --port
TP_WORKER_CLIENT_PRIVATE_KEY=/path/to/private/key.pem # --private-key
```

### Start the Server

Starting the server attaches to server log output unless sent to the background.

```sh
tp-worker-server
...
< Logged Output >
...
```

### Client Pings Server

```sh
tp-worker-client ping
Server OK at 127.0.0.1:8080
```

### Client Starts a Job
`ls -lha` used as example.

The `--name` argument can be passed to provide a unique name to the job,
otherwise we assign the job a unique name based on the command and an increment.
Names must start with a letter to prevent confusion with pid's elsewhere. Names
are global. Fails if the name is already taken.

The `-f` or `--follow` argument is equivalent to `tail -f`, which immediately
attaches to the streaming output of the job.

```sh
tp-worker-client start 'ls -lha'
Server 127.0.0.1:8080: Started job 'ls1' at pid 12345: ls -lha
```

### Client Stops a Job

Either a name or pid is required. Since a name must start with a letter we
should be able to do this without requiring either `--name` or `--pid`
arguments, though they could be available to make people feel better.

The `-s` or `--signal` argument is equivalent to `kill -s`, where the user may
select the signal to be sent to the process. Can accept either the signal
name or number, such as `SIGKILL` or equivalently `9`. Defaults to `SIGTERM`
or `15`. See `Signal numbering for standard signals` in `signal(7)` manpage
for the full list of signals.

```sh
tp-worker-client stop ls1

# or

tp-worker-client stop 12345
Server 127.0.0.1:8080: Stopped job 'ls1' at pid 12345: ls -lha
```

### Client Checks Job Status

Possible statuses:
* Queued (after queue tracking has been added to scope)
* Started (the job has been sent to the system, but no output received yet)
* Running (the job is running and output is being received)
* Hung (the job is running, but no new output has been received for some time)
* RunExited (the job stopped normally)
* RunKilled (the job was killed by the user)
* RunFailed (the job stopped abnormally)
* Error (the job could not be run due to a system issue)

The below status command prints a table of all commands run by the user since
server start. Can also be run with multiple `--name` or `--pid` arguments to
get a table of statuses of selected jobs submitted by the user.

```sh
tp-worker-client status
PID   NAME  STATUS  OUTLEN SUBMITTED STARTED  STOPPED   DURATION
12345 ls1   Running 6      15:55:55  15:55:55 15:55:57  2s
```

### Client Streams Output

Requires either a name or pid to be passed, like `stop` commmand does.

```
tp-worker-client output ls1
...
< Streamed Output >
...
```

## Further Development / Product Ideas

These are being outlined to provide potential future directions for the product,
a place to consider where it might be appropriate to provide Interfaces rather
than full implementations in the libraries, and anti-priorities (work that
should be avoided at all costs, for now) for completing the task as outlined
above.

### Scanning and Obfuscating Output

Scanning and Obfuscating potentially sensitive output by default would be an
enormous win. Development of a dictionary of words to trigger obfuscation of
following words based on word boundaries would take time and never truly be
complete though. Also, regex's and even simple text-matching algorithms are a
bit costly, so careful profiling and benchmarking would be necessary to select
the best algorithms to prevent all of the server cycles from being taken up by
scanning and obfuscation.

### Privileged Elevation and Delegation Management (PEDM)

To a bare minimum extent PAM and PASM are part of the above implementation, but
there's an opportunity to do more.

Include a way for a security team, manager, or other users to temporarily grant
scoped, elevated privileges to a specific user for a specified duration. This
could permit a user to perform sensitive, infrequent operations with the
acknowledgement, supervision, and consent of others in the organization.

### Database Storage

Database job lookup pointing to output stored in block/object storage would
help with things like incident root causing and security audits to understand
who did what, when, and what the outcome was. It could potentially also provide
a way for users to issue a large of volume of "fire and forget" commands that
they intend to later retreive output for rather than babysit.

Offloading streaming output to block/object storage would also reduce load on
the server when a user is pulling down a high volume of output.

Obfuscation of sensitive data would need to happen before the output is stored.

### Attractive TUI Experience & JSON Web Tokens

TUI (Terminal User Interface) using `bubbletea` library.

Create an interactive experience in the terminal that users could keep running
in a terminal window and use to send the commands developed for the application
and receive/retreive the relevant outputs. Think like `k9s`.

This would be especially powerful when used with a Bearer token, like a JSON
Web Token (JWT) so that the client could send the user's entitlements to the
server with each request via the JWT. A users's first server access in a session
would issue a JWT that is valid for a specified period of time and contain that
user's entitlements. If the user makes a request while presenting a still-valid
JWT then the server can skip the whole authorization phase and simply use the
claims present in the valid JWT to determine authorization. A Bearer token is
probably a bad idea for one-shot cli usage since it introduces client-side
storage complications and security implications.

### Secure Secrets Usage and Templating

Using a Vault stored secret, a user may start a process on the host using a
string template to stand in for a secret. The string template is matched to a
credential or key/value in Vault and inlined to the command to kick off the
process. It should be impossible to leak secrets back to the client, and the
streaming output should use fuzzy matching to obfuscate anything that looks like
a credential and replace it either with the string template the user originally
gave or the string `**** REDACTED ****`.

#### Market Research / Further development

1. Allow using various cloud services for secure secrets management, like AWS
   Secrets Manager, Google Cloud Secrets Manager, HCP Vault, CyberArk, Azure Key
   Vault, Akeyless, etc.
2. Create our own secure secrets storage and management app that is hosted
   alongside this app.
