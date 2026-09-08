# Optional AWS protection and recovery

Companion to [the observability operations guide](OBSERVABILITY.md). None of these
optional services is provisioned automatically. Select an RPO (acceptable data
loss), RTO (restoration time), retention policy, account boundary and budget before
implementation. Obtain security/change approval before adding destinations or
network paths. Keep GovCloud data and encryption keys in approved GovCloud accounts.

## Three different protection problems

| Asset | Protection approach | What it does not protect |
| --- | --- | --- |
| Terraform/GitOps, dashboards, rules, receiver references | Reviewed Git plus encrypted state and recovery documentation; optional OADP for owned app resources | Historical metric/log data and external IAM/KMS |
| Loki S3 chunks AND indexes, schema history, WAL/PVC state | S3 replication/versioning or AWS Backup, plus a coordinated recovery point for stateful data | A continuously running, independently writable second Loki cluster |
| Prometheus history | Supported remote-write to a durable metrics service; separately protect configuration | Dashboard/rule definitions, alert silences, or automatic local TSDB restore |

S3 buckets created by this layer have versioning, encryption, public-access blocks
and TLS-only access. CloudFormation retains the bucket on deletion/replacement.
The IAM role uses audience- and subject-scoped OIDC tokens, not stored AWS keys.
Retaining a bucket does not retain the deleted role, cluster, KMS key or a working
query service. Protect required KMS keys against premature deletion.

## Option A: independent S3 log copy

1. Provision a separate destination bucket in an approved account/region, with
   versioning, encryption, public-access blocks, ownership controls and restrictive
   bucket policy. Use a dedicated replication role—not Loki's runtime role—with
   source-version read, destination replication and required KMS permissions.
2. Add replication to the **existing CloudFormation-owned** source bucket through
   its template under Terraform review. Do not introduce an `aws_s3_bucket`
   resource that also owns the same bucket. Include all Loki object keys, not a
   guessed `chunks/` prefix. For SSE-KMS, explicitly configure encrypted-object
   replication and destination-key permissions. New rules cover new objects;
   plan S3 Batch Replication for existing objects.
3. Decide delete-marker behavior and destination retention deliberately. An
   independent recovery copy should not blindly mirror every source deletion.
   Replication is asynchronous and propagates some unwanted writes too; maintain
   versions/recovery points. Monitor replication failure and pending bytes/time.
4. Record source/destination ARNs, role, key IDs, schema history and restore
   permissions in the recovery inventory. Test with non-sensitive log markers
   and verify destination object versions, not just a successful IAM plan.

See [AWS S3 replication setup](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication-walkthrough1.html).
Cross-Region Replication is confined to an AWS partition: GovCloud-to-commercial
replication is not supported by that mechanism. See [AWS partition boundaries](https://docs.aws.amazon.com/whitepapers/latest/aws-fault-isolation-boundaries/partitions.html).

Example read-only checks (substitute approved names/region):

~~~sh
aws s3api get-bucket-versioning --bucket SOURCE_BUCKET --region us-gov-west-1
aws s3api get-bucket-replication --bucket SOURCE_BUCKET --region us-gov-west-1
aws s3api get-bucket-lifecycle-configuration --bucket SOURCE_BUCKET --region us-gov-west-1
aws s3api head-object --bucket SOURCE_BUCKET --key KNOWN_LOKI_OBJECT --region us-gov-west-1
~~~

Do not put Glacier transitions or Object Lock on live Loki chunks/indexes:
queries need online objects and the compactor needs deletion rights. If immutable
evidence retention is required, use a separately governed archive with its own
restore process. Version expiration here occurs after a version becomes noncurrent,
not at the log event's timestamp; budget and document the extended physical lifetime.

## Option B: managed backup and Kubernetes recovery

Evaluate [AWS Backup for S3](https://docs.aws.amazon.com/aws-backup/latest/devguide/s3-backups.html)
for periodic or continuous recovery points. Confirm regional availability,
supported feature combinations, IAM, encryption and costs before implementation;
do not assume commercial feature parity in GovCloud. Use a separate backup vault,
access boundary, alerts and restore drill. A schedule without a successful restore
is not acceptance evidence.

For Kubernetes-owned application resources/PVCs, assess this repository's OADP
layer and the selected Red Hat OADP support matrix. Do not back up/restore an entire
ROSA managed control plane or overwrite SRE-owned monitoring resources. Explicitly
scope owned namespaces and objects, capture consistent stateful data, and preserve
dashboard/rule manifests in Git. Protect receiver secrets through the approved
secret system instead of committing exported plaintext Secrets. Terraform state
also contains sensitive data and must have encrypted, access-controlled backups.

## Option C: long-term metrics in AWS

Amazon Managed Service for Prometheus (AMP) can receive Prometheus remote-write.
This is a separate design decision, not a Loki S3 backup or an enabled default.
Check AMP availability, endpoints, quotas, pricing and compliance scope in the
target region; if unavailable, select an approved supported alternative.

Use the documented user-workload `remoteWrite` configuration under the **same
Terraform owner** as `user-workload-monitoring-config`, or a separately managed
supported collector/monitoring stack. This repository does not currently expose
remote-write credentials/configuration as root variables: extend the desired
configuration and tests before enabling it, rather than hand-editing the ConfigMap
and losing it on the next apply. Do not patch ROSA platform Prometheus pods or
install a Helm chart over the managed stack.

The sender needs SigV4 signing and a short-lived IAM identity authorized only for
`aps:RemoteWrite` on the destination workspace. Supplying a `roleArn` alone does
not create the initial web-identity credential chain. Verify the actual managed
component's supported authentication fields and service-account identity path;
if unavailable, use an approved independently managed sender. Avoid static keys
in ConfigMaps/tfvars. Add an approved private endpoint/network path on zero-egress
clusters; do not open general internet access to make remote-write work.

Configure replica/cluster labels and the destination's supported HA deduplication
so two Prometheus replicas do not double-count data. Measure sample rate and
cardinality; filter unnecessary series, monitor queue backlog/retries/drops and
bound memory. Validate both ingestion and authenticated queries in the destination.
Retention and local storage need independent sizing. Remote-write only exports
new samples; it does not automatically backfill existing history or restore local
TSDB blocks. See [AWS's existing-Prometheus ingestion guide](https://docs.aws.amazon.com/prometheus/latest/userguide/AMP-onboard-ingest-metrics-existing-Prometheus.html)
and [cross-region metric destinations](https://docs.aws.amazon.com/prometheus/latest/userguide/AMP-send-to-multiple-workspaces.html).

## Recovery rehearsal: never test on the live bucket

1. Record the incident/recovery timestamp and freeze destructive lifecycle or
   compactor changes through an approved procedure. Preserve evidence. Select a
   coherent recovery point for **indexes and chunks**, including schema history;
   acknowledge unflushed ingester/WAL loss within the measured RPO.
2. Restore/copy into an isolated recovery bucket. Do not point two independent
   active Loki stacks at the production bucket. Restore the required external
   IAM/OIDC/KMS dependencies with the recovery cluster's identity—not the old
   cluster's trust subject alone. Recreate the matching supported operator stack,
   tenant configuration and storage schema history from reviewed manifests.
3. Follow the release-specific Loki recovery procedure with Red Hat for PVC/WAL
   consistency. Do not assume restoring an S3 prefix alone is sufficient or that
   the source bucket's live state was transactionally captured by replication.
4. Validate known log markers across the selected time range and each authorized
   tenant; test unauthorized access is denied. Rebuild application dashboards,
   rules and receivers from Git/secrets. Query retained metrics in their external
   service; a new user Prometheus starts with new local history unless separately
   recovered by a supported process.
5. Measure actual RPO/RTO and cost. Test fresh ingestion, queries and firing/resolved
   alert delivery before any approved traffic cutover. Document gaps and rollback.
   Keep the original recovery point intact until the rehearsal is accepted.

## FedRAMP considerations

This architecture can support evidence for AU-9 (protection of audit information),
AU-11 (audit retention), CP-9/CP-10 (backup/recovery) and SC-7 (boundary protection).
It is not a control implementation or ATO by itself. Get retention/deletion rules,
key custody, personnel access, replication boundaries and notification destinations
approved by the system owner. Zero egress reduces unsolicited external paths but
does not replace bucket/IAM/endpoint policy restrictions or recovery exercises.
See [the repository FedRAMP guidance](FEDRAMP.md).
