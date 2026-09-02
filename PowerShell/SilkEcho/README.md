# SilkEcho

Present a copy of one Silk Echo host's databases on one or more other hosts, and
keep those copies current on a schedule, from plain PowerShell.

It works by reconciliation. The desired state is "these destination hosts present
a copy of the source host's databases". Every run reads the current state of every
host involved from Echo, works out what actually has to change, and does only
that: a database that is missing gets created, a copy that is stale gets refreshed
from a new snapshot. Nothing is copied physically at any point.

Run the same command daily or on demand. It is the same command on the first run
as on the hundredth.

Intended to run unattended, as a SQL Server Agent job step that an external
automation tool starts on demand to refresh an environment. It works just as well
from a console or Task Scheduler.

Nothing but Windows PowerShell 5.1 and network access to Flex is required: no Silk
PowerShell module, no `SqlServer` module, no packages to install. Every call is a
documented Flex REST call.

Treat it as a starting point. Read it, change it, wire it into whatever you
already run.

## Files

| File | Purpose |
|---|---|
| `SilkEcho.psm1` | The module. Authentication, the Echo API surface, and `Copy-SilkEchoDatabase`. |
| `Invoke-EchoDatabaseCopy.ps1` | Single entry point with exit codes, for SQL Server Agent or Task Scheduler. |

## Requirements

- Windows PowerShell 5.1 or PowerShell 7. Verified on both; 5.1 is what SQL
  Server Agent launches, and what the live testing was done on.
- Network access from wherever the script runs to the Flex server. The script does
  not have to run on either database host.
- Both hosts registered in Echo with the Silk Agent connected.
- The source database has to be Echo aware, meaning it lives on Silk volumes that
  Flex can snapshot.

## Install

Copy the folder to the machine that will run the job, for example `C:\Silk\SilkEcho`.
Keep `SilkEcho.psm1` and `Invoke-EchoDatabaseCopy.ps1` together: the wrapper loads
the module from its own directory.

It does not have to be either database host. Anywhere with network access to Flex
will do, including the SQL Server itself if that is convenient.

## Get started

You need three things: the two files above on a machine that can reach Flex, an
application token issued in Flex, and the names of the two hosts as Echo has them
registered. `Get-SilkEchoHost` lists those if you are not sure.

**See what it would do.** This changes nothing and does not take a snapshot:

```powershell
.\Invoke-EchoDatabaseCopy.ps1 -Server flex.contoso.com -Token '<token>' `
    -SourceHost sql-prod -DestinationHost sql-dev -WhatIf
```

```
[INFO ] SilkEcho 1.3.0 loaded from C:\Silk\SilkEcho\SilkEcho.psm1
[INFO ] Discovering the databases Echo can see on 'sql-prod'.
[INFO ] In scope (3): SalesDB, financeDB, inventoryDB
[STEP ] Plan:
[STEP ]   sql-dev
[INFO ]     Clone    SalesDB -> SalesDB  (not present on the destination host)
[INFO ]     Clone    financeDB -> financeDB  (not present on the destination host)
[INFO ]     Clone    inventoryDB -> inventoryDB  (not present on the destination host)
[WARN ] WhatIf: stopping before the snapshot. Nothing has been changed.
```

**Then do it,** by dropping `-WhatIf`. One snapshot of the source, then the
copies are mounted on the destination. Expect a couple of minutes per operation.

**Then run the exact same command again.** The plan flips to `Refresh`, because
the copies now exist: it takes a new snapshot, drops the old volumes and attaches
the new ones under the same names. That is the whole point, and it is why the
scheduled job never needs to know whether it is the first run or the hundredth.

From here:

- [What the caller has to supply](#what-the-caller-has-to-supply) for every
  option, including naming databases explicitly rather than taking them all.
- [Triggering from a SQL Server Agent job](#triggering-from-a-sql-server-agent-job)
  to put it on a schedule.
- [Exit codes](#exit-codes) if something calls this and needs to react.

## Authentication

A **static application token**, generated in Flex, passed in as a parameter:

```powershell
-Token $flexToken
```

or via the `FLEX_TOKEN` environment variable, which is the convention Silk's own
examples use. `FLEX_URL` or `FLEX_IP` supplies the server when `-Server` is
omitted.

The token is used exactly as given and held in memory for the life of the
process. **This is not a secret management tool**: it does not store, encrypt,
cache or write the token anywhere. Supply it however your automation supplies
secrets.

There is no username and password path, deliberately. The Echo API is bearer
token only, and a static application token does not expire, which is what an
unattended job wants.

`Connect-SilkFlex` makes one real API call before returning, so a token that is
revoked or belongs to a different Flex fails there, before anything is touched:

```
Flex rejected the token on /api/v1/hosts (403). It is revoked, belongs to a
different Flex, or lacks access to this endpoint.
```

## Working from the module directly

The wrapper is the thing to schedule, but the module underneath is usable on its
own, which is the quicker way to look around an environment before committing to
anything:

```powershell
Import-Module C:\Silk\SilkEcho\SilkEcho.psm1

Connect-SilkFlex -Server flex.contoso.com -Token $flexToken

# See what is registered
Get-SilkEchoHost | Format-Table host_id, host_name, is_connected, db_engine_version
Get-SilkEchoDatabase -HostName sql-prod | Format-Table id, name, status

# Show what would change, without changing anything
Copy-SilkEchoDatabase -SourceHost sql-prod -DestinationHost sql-dev -WhatIf

# Do it. Every database on sql-prod, presented on sql-dev under the same names.
Copy-SilkEchoDatabase -SourceHost sql-prod -DestinationHost sql-dev

# Or name the databases explicitly, and suffix the copies.
Copy-SilkEchoDatabase -SourceHost sql-prod -DestinationHost sql-dev `
                      -SourceDatabase SalesDB,Inventory -DestinationSuffix _Dev
```

**Certificates.** Flex ships with a self signed certificate, so validation is off
by default and there is no flag to remember. Pass `-RequireValidCertificate`
where Flex has a certificate that actually chains. TLS 1.2 is forced regardless,
because Windows PowerShell still offers 1.0 on some builds and Flex refuses it.

## What each run does

**1. Work out the desired state.** By default that is every database Echo can see
on the source host, read fresh from Echo on this run. See
[Which databases](#which-databases) to pin it to a fixed list instead.

**2. Read the current state** of every destination from the Echo topology, which
is what carries clone lineage.

**3. Decide, per database, per destination.** Intent comes from the comparison,
not from a flag:

| Current state on the destination | Action | Effect |
|---|---|---|
| Not present | **Clone** | Net new volumes. A new Echo database is mounted from the snapshot. |
| Already there | **Refresh** | Stale data. Flex detaches the old volumes and attaches new ones from the snapshot. Same name, new contents. |
| A copy whose source database is gone | **Orphan** | Reported and left alone. `-RemoveOrphaned` deletes it instead. |

Whether Flex will actually accept an operation is Flex's call, not this script's.
Every mutation goes through the matching `__validate` endpoint first, so anything
Flex will not do is reported in its own words before anything changes.

**4. Snapshot the source once**, covering every database in scope and serving
every destination.

**5. Apply.** One clone call covering every host that needs new databases, and
one refresh call per host that needs existing ones replaced.

The plan is printed and checked **before the snapshot is taken**. `-WhatIf` prints
it and stops there, which makes it a dry run of the reconciliation:

```
[INFO ] Discovering the databases Echo can see on 'sql-prod'.
[INFO ] In scope (2): SalesDB, Payroll
[STEP ] Plan:
[STEP ]   sql-dev
[INFO ]     Refresh  SalesDB -> SalesDB  (already on the destination host)
[INFO ]     Clone    Payroll -> Payroll  (not present on the destination host)
[WARN ]     Orphan   Inventory  (source database is gone, leaving it alone)
[STEP ]   sql-qa
[INFO ]     Clone    SalesDB -> SalesDB  (not present on the destination host)
[INFO ]     Clone    Payroll -> Payroll  (not present on the destination host)
```

## Which databases

**Leave `-SourceDatabase` out** and the source host's database list is read from
Echo on every run. A database added to the source gets picked up on the next run,
one dropped from the source stops being copied, and there is no job definition to
maintain. This is what a scheduled environment refresh usually wants.

**The scope is whatever Echo reports**, and nothing else. If Echo can see it, it
is on Silk volumes and Echo can manage it, so it is a candidate. This script does
not second guess that list: it applies no name based rules of its own and has no
opinion about what a database is for. `-ExcludeDatabase` is the operator's filter,
and the only one.

Every exclusion is logged with its reason, so a run says what it considered.

**Name databases explicitly** with `-SourceDatabase` to pin the job to exactly
those. A run then fails if one of them has been dropped, which is the point: you
asked for it by name. Explicit mode also leaves everything else on the
destinations alone, so it never reports orphans.

The two are mutually exclusive and **that is enforced by parameter sets**, not by
a runtime check: `-SourceDatabase` with `-ExcludeDatabase` fails to bind rather
than accepting both and quietly ignoring one, and so does `-DestinationDatabase`
with `-DestinationSuffix`.

`-DestinationDatabase` without `-SourceDatabase` is the one exception. It binds
and then fails with a message, because making it a binding failure would mean
marking `-SourceDatabase` mandatory, and PowerShell *prompts* for a missing
mandatory parameter. A prompt in a scheduled job hangs it forever, so nothing a
caller might plausibly omit is mandatory anywhere in this module.

## Many destinations, one snapshot

`-DestinationHost` takes a list. Every host is served from a **single snapshot of
the source**:

```powershell
Copy-SilkEchoDatabase -SourceHost sql-prod -DestinationHost sql-dev,sql-qa,sql-uat
```

Each destination is reconciled on its own, so one can be getting brand new
databases while another is refreshing existing ones, from the same point in time.

This matters more than convenience. Running the script once per host instead
would take one snapshot per host, at a different moment each, hold all of them
open at once, and quiesce the source once per host. With one call you pay for one
snapshot and one quiesce, and every destination lands on identical data.

Duplicate hosts in the list are collapsed.

### Consistency level

Three states, and `-ConsistencyLevel` is an exhaustive set, so they cannot
contradict each other:

| Value | What Flex is asked for |
|---|---|
| `application` *(default)* | Quiesced through the Silk VSS provider. The copy comes up immediately usable. Sends `consistency_level=application`, `use_vss=true`. |
| `application-novss` | Application consistent without the VSS provider, which SQL Server 2022 and later support. Sends `consistency_level=application`, `use_vss=false`. |
| `crash` | No quiesce, nothing asked of the database engine. The copy may come up in recovery on first attach. Sends `consistency_level=crash`; VSS does not apply. |

`use_vss` is **sent explicitly** for the application levels rather than left to
the API's default. Whether a copy comes up usable or in recovery matters too much
to inherit from a server side default that could differ between Flex builds: the
request says what it wants, and the run logs it:

```
[STEP ] Creating a snapshot of SalesDB on sql-prod (application consistent, using VSS, prefix 'salesdb')
```

Flex reports which path it actually took in the task `command_type`, so a
completed run can be checked after the fact:

| `command_type` | Means |
|---|---|
| `CreateVssDbSnapshotCommand` | application consistent via VSS |
| `CreateGenericDBSnapshotCommand` | application consistent without VSS |
| `CreateDBSnapshotCrashLevelCommand` | crash consistent |

Either way the agent does the work and already holds the credentials it needs.

### Snapshots

Every run leaves its snapshot in place, because the destination copy depends on
it. Cleaning them up afterwards is the Flex retention policy's job. This script
never deletes one.

## Concurrency

**Flex runs one operation at a time.** It does not refuse a second one: it
accepts the job, starts it, and the job then fails on a resource lock. Losing a
race therefore costs a burned job rather than a cheap rejection, which makes
waiting the whole defence rather than a nicety.

**Before every operation, the script waits for the Flex task queue to clear.**
Not just Echo work: `GET /api/echo/v1/tasks` returns everything running on the
Flex, SDP operations included, and they take the same locks. So the wait is on
*any* activity, and the filtering happens here rather than in the request.

```
[INFO ] Flex is busy, so the snapshot of sql-prod is waiting:
        SomeSdpCommand [Fj3U7QTsDD] running
[INFO ] Flex is idle. Continuing with the snapshot of sql-prod.
```

**The wait is a continuous poll, never a sleep.** That distinction matters: a
fixed backoff means not watching during the exact window the slot frees up, so
the same caller loses the same race repeatedly. The queue is checked every
`-PollSeconds` (default 2), and the moment it empties the operation is submitted.
The interval carries a little randomness so two jobs waiting on the same busy
Flex drift apart instead of sampling together and colliding on every tick.

**An operation that fails anyway is resubmitted**, up to `-StepAttempts` times
(default 3), and between attempts it goes straight back to watching the queue.
A failure is retried unless it is provably permanent, which is the deliberate
direction for something nobody is watching: giving up on a transient failure
costs the whole cycle, while retrying a genuinely broken operation costs a couple
of minutes and then reports the same error. Flex's `__validate` call already
rejects most permanent problems before submission, so what reaches this point has
usually earned another go.

The permanent list lives in `$script:PermanentFailurePatterns`. Every failure
that does not match it is logged with the full task object, so a real lock
collision hands you its exact wording to add.

**Reads are not gated.** Fetching the topology or the task list is support work,
and putting it behind the queue would add a wait to every trivial lookup. They
get their own retry instead: any failure that is not a settled answer is retried
up to four times, because a momentary blip while reading the topology must never
end a scheduled refresh.

**Writes are never replayed blindly at the HTTP layer.** A POST that failed with a
dropped connection may have reached Flex, so it surfaces to the operation loop,
which waits for the queue to settle before deciding.

If the queue is still busy when `-IdleWaitMinutes` (default 15) expires, the
script exits **4** having changed nothing.

## When one destination fails

Destination hosts are independent. One that cannot be served is recorded and the
others still get refreshed, so a single bad host does not leave every other
environment stale.

- A host that **fails** is recorded with the reason and the run continues with
  the rest.
- If the combined clone call fails, it is retried **one host at a time** so a
  single bad destination does not take the others down with it.
- Only a failure to **snapshot the source** stops everything, since no destination
  can proceed without it.

The result reports `Success`, `Partial`, `FailedHosts`, and a per host breakdown
in `Destinations`. The wrapper exits **5** for a partial failure, distinct from
**3** for a total one.

## What the caller has to supply

Four values. That is the whole contract:

| | |
|---|---|
| `-Server` | Flex hostname, FQDN or IP |
| `-Token` | A static Flex application token |
| `-SourceHost` | The host whose databases are being copied |
| `-DestinationHost` | One or more hosts presenting the copies, comma separated |

That is a complete invocation. Everything else has a default chosen for
unattended operation.

```powershell
.\Invoke-EchoDatabaseCopy.ps1 -Server flex.contoso.com -Token $token `
    -SourceHost sql-prod -DestinationHost sql-dev
```

Choosing which databases:

| Parameter | Effect |
|---|---|
| *(neither)* | Every database Echo can see on the source host, rediscovered every run |
| `-SourceDatabase A,B` | Exactly these, by name. The run fails if one is not on the source host |
| `-ExcludeDatabase A,B` | Everything except these. Only valid when `-SourceDatabase` is omitted |

Naming the copies:

| Parameter | Effect |
|---|---|
| *(neither)* | The copies keep the source names, which is fine on a different host |
| `-DestinationSuffix _Dev` | `SalesDB` becomes `SalesDB_Dev` on every destination |
| `-DestinationDatabase X,Y` | Exact names, in the same order as `-SourceDatabase`. Requires it |

Everything else:

| Parameter | When |
|---|---|
| `-RemoveOrphaned` | Mirror source drops onto the destination, instead of reporting them |
| `-ConsistencyLevel application-novss` | Application consistent without the VSS provider |
| `-ConsistencyLevel crash` | No quiesce. The copy may come up in recovery |
| `-TargetState recovery` | Leave the copies in recovery rather than online |
| `-SnapshotPrefix name` | Name the snapshot yourself instead of deriving it |
| `-RequireValidCertificate` | Where Flex has a certificate that chains |
| `-SkipValidation` | Skip the `__validate` pre-flight before each mutation |
| `-SkipIdleCheck` | Do not wait for the Flex queue at all. Only safe when nothing else uses this Flex |
| `-WhatIf` | Print the plan and stop before the snapshot |

Timings, all tuned for operations that take a couple of minutes:

| Parameter | Default | Effect |
|---|---|---|
| `-PollSeconds` | 2 | How often the task queue is checked |
| `-TimeoutMinutes` | 15 | How long one operation may run before it is called hung |
| `-IdleWaitMinutes` | 15 | How long to wait for the queue to clear before giving up with exit 4 |
| `-StepAttempts` | 3 | How many times to submit an operation before giving up on it |

## Exit codes

`Invoke-EchoDatabaseCopy.ps1` exits with a code any caller can branch on. A SQL
Server Agent step fails on anything non-zero.

| Code | Meaning |
|---|---|
| 0 | Every destination succeeded |
| 1 | Bad parameters or a missing prerequisite |
| 2 | Could not reach or authenticate to Flex |
| 3 | The copy failed and no destination was updated |
| 4 | Flex stayed busy with other work, so nothing was attempted |
| 5 | Partial: some destinations were updated, some failed |

Codes 1, 2 and 4 leave everything untouched, so they are safe to retry as is.
Code 5 means the run did real work: re-running it is safe, since reconciliation
is idempotent, and it will pick up whatever failed last time if the cause has
cleared.

The script writes to standard output and opens no files. Capture it however you
capture job output.

## Triggering from a SQL Server Agent job

The job step runs `Invoke-EchoDatabaseCopy.ps1` through **CmdExec**, not the
PowerShell subsystem. The PowerShell subsystem hosts an old, restricted
PowerShell that this script does not need and does not want.

### 1. Create a proxy for the CmdExec step

A CmdExec step run by a non `sysadmin` owner needs a proxy.

```sql
USE msdb;
GO

CREATE CREDENTIAL [SilkEchoCredential]
    WITH IDENTITY = N'DOMAIN\svc_silkecho',
         SECRET   = N'<the Windows password for that account>';
GO

EXEC msdb.dbo.sp_add_proxy
     @proxy_name      = N'SilkEchoProxy',
     @credential_name = N'SilkEchoCredential',
     @enabled         = 1;

-- 3 is the CmdExec subsystem
EXEC msdb.dbo.sp_grant_proxy_to_subsystem
     @proxy_name = N'SilkEchoProxy',
     @subsystem_id = 3;
GO
```

If the job owner is already `sysadmin`, skip the proxy and drop `@proxy_name`
from the job step below.

### 2. Create the job

```sql
USE msdb;
GO

EXEC msdb.dbo.sp_add_job
     @job_name = N'Silk Echo - Refresh SalesDB_Dev',
     @description = N'Snapshots sql-prod.SalesDB and refreshes sql-dev.SalesDB_Dev from it.',
     @enabled = 1;

EXEC msdb.dbo.sp_add_jobstep
     @job_name   = N'Silk Echo - Refresh SalesDB_Dev',
     @step_name  = N'Copy database',
     @subsystem  = N'CmdExec',
     @proxy_name = N'SilkEchoProxy',
     @command    = N'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\Silk\SilkEcho\Invoke-EchoDatabaseCopy.ps1" -Server flex.contoso.com -Token "<flex application token>" -SourceHost sql-prod -DestinationHost sql-dev,sql-qa',
     @output_file_name = N'C:\Silk\logs\sqlagent-step.txt',
     @flags = 2,   -- append to the output file
     @on_success_action = 1,
     @on_fail_action = 2,
     @retry_attempts = 0;

EXEC msdb.dbo.sp_add_jobserver @job_name = N'Silk Echo - Refresh SalesDB_Dev';
GO
```

Add a schedule if it should run on its own:

```sql
EXEC msdb.dbo.sp_add_jobschedule
     @job_name = N'Silk Echo - Refresh SalesDB_Dev',
     @name = N'Nightly 0200',
     @freq_type = 4,             -- daily
     @freq_interval = 1,
     @active_start_time = 020000;
```

### 3. Trigger it on demand from T-SQL

`sp_start_job` returns as soon as the job is queued, and needs no `xp_cmdshell`.
This is how an application, a stored procedure or another job kicks off a refresh:

```sql
EXEC msdb.dbo.sp_start_job N'Silk Echo - Refresh SalesDB_Dev';
```

To wait for it and check the result:

```sql
DECLARE @status INT = 1;
WHILE @status = 1
BEGIN
    WAITFOR DELAY '00:00:10';
    SELECT @status = ja.run_requested_date IS NOT NULL AND ja.stop_execution_date IS NULL
    FROM msdb.dbo.sysjobactivity AS ja
    JOIN msdb.dbo.sysjobs AS j ON j.job_id = ja.job_id
    WHERE j.name = N'Silk Echo - Refresh SalesDB_Dev'
      AND ja.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions);
END

SELECT TOP (1) run_status, run_duration, message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'Silk Echo - Refresh SalesDB_Dev' AND h.step_id = 1
ORDER BY h.instance_id DESC;
```

### Follow up T-SQL

None is needed for the copy itself. The Silk Agent detaches the old database,
attaches the new volumes and brings the database online, using credentials it
already has. This script issues no T-SQL.

Anything you want *on top* of the copy, such as recreating logins, setting the
recovery model or masking data, belongs in a **second job step** running against
the destination instance.

## Known caveats

- **The database side belongs to the Silk Agent.** Quiescing, detaching, attaching
  and bringing the database online are all done by the agent, which already holds
  the credentials it needs. This script only calls the Echo API: it issues no
  T-SQL, holds no database credentials, and never touches either host directly.
  When something on a host does block an operation, Flex's own `__validate` call
  reports it before anything is changed.
- **Overlapping schedules.** Several of these jobs pointed at the same Flex will
  wait for each other rather than collide, which is correct but makes each run
  take longer. Stagger the schedules, or set `-IdleWaitMinutes 0` on the less
  important ones so they skip instead of queue.
- **Token scope.** A token is tied to the Flex that issued it. Point the job at a
  different Flex and it fails at connect time, having changed nothing.

## Function reference

| Function | Purpose |
|---|---|
| `Connect-SilkFlex` | Open a session with an application token, and set up TLS. |
| `Disconnect-SilkFlex` | Drop the cached session and token. |
| `Get-SilkFlexSession` | Show the current session. Never includes the token. |
| `Get-SilkEchoHost` | List every registered host, or resolve one by name. |
| `Resolve-SilkEchoHost` | Resolve one name to exactly one host, or throw. Never a list. |
| `Get-SilkEchoDatabase` | List the databases Echo can see on a host. |
| `Get-SilkEchoTopology` | Full host, database and snapshot tree, including clone lineage. |
| `Get-SilkEchoSnapshot` | List snapshots, filtered by id or source host. |
| `Get-SilkEchoTask` | List tasks on the Flex, or just the ones still running. |
| `Wait-SilkEchoIdle` | Block until the Flex task queue is empty. |
| `Wait-SilkEchoTask` | Poll one task to completion, or throw on its failure. |
| `Invoke-EchoOperation` | Run one operation: wait for the queue, submit, track it, resubmit if it did not stick. |
| `New-SilkEchoSnapshot` | Snapshot one or more databases on a host. |
| `New-SilkEchoClone` | Mount a new Echo database from a snapshot. |
| `Update-SilkEchoClone` | Refresh existing Echo databases in place from a snapshot. |
| `Remove-SilkEchoClone` | Detach and delete an Echo copy and its thin volumes. |
| `Remove-SilkEchoSnapshot` | Delete a snapshot. |
| `Copy-SilkEchoDatabase` | The orchestrator. Plans, snapshots, then clones or refreshes. |
| `Invoke-SilkFlexApi` | Raw Flex call, for anything not wrapped above. |
| `ConvertTo-EchoNamePrefix` | Coerce a string into a legal snapshot name prefix. |

Every function has comment based help: `Get-Help Copy-SilkEchoDatabase -Full`.

## Endpoints used

All documented at <https://github.com/Kaminario/echo-public-docs>.

| Endpoint | Used for |
|---|---|
| `GET /api/v1/hosts` | Host resolution and connectivity checks. |
| `GET /api/v1/hosts/{id}/databases` | The databases Echo can see on a host. |
| `GET /api/echo/v1/topology` | What is already on each destination, and the lineage behind orphan detection. |
| `GET /api/echo/v1/tasks` | The whole task queue, filtered here, to know when Flex is free. |
| `GET /api/echo/v1/tasks/{id}` | Polling one operation to completion. |
| `POST /api/echo/v1/db_snapshots` | Taking the snapshot. |
| `GET /api/echo/v1/db_snapshots` | Reading the snapshot back for the database ids a clone needs. |
| `POST /api/echo/v1/db_snapshots/{id}/echo_db` | Cloning to one or more destinations. |
| `POST /api/echo/v1/hosts/{id}/databases/_refresh` | Refreshing in place, per host. |
| `DELETE /api/echo/v1/echo_dbs` | Removing an orphaned copy, only with `-RemoveOrphaned`. |
| `DELETE /api/echo/v1/db_snapshots/{id}` | `Remove-SilkEchoSnapshot` only. The copy flow never deletes a snapshot. |
| `.../__validate` | Pre-flight check before each mutation. Skipped with `-SkipValidation`. |
