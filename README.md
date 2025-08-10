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

```
tp-worker/
  go.mod
  go.sum
  cmd/
    tp-worker-server/
    tp-worker-client/
  internal/
  job/
  proto/
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

## Authorization

For example user authorization the server will read a JSON file that implements
a basic user schema with two roles and three users.

```
[
  { user: "may", roles: ["admin", "user"] },
  { user: "susan", roles: ["user"] },
  { user: "toby", roles: ["user"] },
]
```

`admin` role will be able to view processes from all users.

`user` role will only be able to view their own processes.

Outside of scope is providing an Interface for library users to utilize an
external system for user authorization. See the `Further Development` section.

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

Environment variables may be passed using the `-e` option as many times as is
necessary.

The `--` convention is used to signal the end of options being provided to
`start` and the beginning of operands being passed as outlined in
[Guideline 10 of Section 12.2 of POSIX conventions.](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html)

ID's assigned to jobs are (psuedo) random, but need not be cryptographically
secure since they are not encoding or hashing anything. A random enough sequence
of 12 letters and numbers should be sufficient at this stage.

```sh
# auth'd as user `bob`
tp-worker-client start -e FOO=bar -- ls -lha
Server 127.0.0.1:8080: Started job 1a2b3c1a2b3c: FOO=bar ls -lha

# or if supplied with a command that does not exist
tp-worker-client start -- foo
Server 127.0.0.1:8080: ERROR: Command `foo` not present in $PATH on this system
```

### Client Stops a Job

Requires the ID of the process to be passed.

Defaults to `SIGKILL`. Addition of other signals is outside of scope.

```sh
tp-worker-client stop 1a2b3c1a2b3c
Server 127.0.0.1:8080: Stopped job 1a2b3c1a2b3c: FOO=bar ls -lha
```

### Client Checks Job Status

Possible statuses:
* Started (the job has been sent to the system)
* Exited (the job stopped with an exit code)
* Killed (the job was killed by the user)
* Error (the job could not be run due to an error with the server)

The below status command prints a table of all commands run by the user since
server start. If the user has `admin` role, it prints a table of all commands
run on the system since server start.

```sh
tp-worker-client status
ID            USER COMMAND          STATUS EXITCODE  STARTED             STOPPED             DURATION
1a2b3c1a2b3c  bob  FOO=bar ls -lha  Exited 0         2025-08-10T15:55:55 2025-08-10T15:55:56 1s
```

### Client Streams Output

Requires ID to be passed, like `stop` commmand does.

```sh
tp-worker-client output 1a2b3c1a2b3c
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

### Interface for User Authorizations

Provide an Interface that library users may satisfy to interface with an
external system for User Authorizations such as LDAP, SSO/SAML, or a custom
solution.

### Addtional command options

#### Client

`start`
* Option to pass `-f` or `--follow` so the user may start a process and
  immediately attach to the output.
* User supplied process names. This is subject to more research to determine
  security implications.

`stop`
* Option of different signals to stop the process with, such as `SIGTERM` or
  `SIGABRT`.

`status`
* Option to filter by command name, pid, or (if admin) by user.
