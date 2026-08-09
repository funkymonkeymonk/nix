---
name: infra-investigation
description: Use when investigating errors, incidents, or performance issues that span Datadog logs/metrics, AWS infrastructure, Terraform/terrasaur config, and Kubernetes Helm values. Use when diagnosing root causes that require correlating multiple sources. Use when infrastructure facts need to be verified before being used in analysis.
---

# Infrastructure Investigation

## Overview

Investigations across Datadog, AWS, Terraform, and Helm fail when infrastructure facts are inferred from indirect signals rather than verified from ground-truth sources. Every factual claim about infrastructure MUST be verified before being used in diagnosis or communicated to the user.

**Core principle:** Hypothesis → Verify → Conclude. Never Hypothesis → Conclude → Verify.

## The Primary Failure Mode

**Inferring facts from indirect signals and treating them as verified.**

This happens in two forms:

**Form 1 — Pattern inference:** Drawing a conclusion from a pattern without verifying it.
- Hostname suffix `cuckbfwsdzq3` appears in multiple env hostnames → "they share an instance"
- Reality: Same subnet group ID appears in all instances in the same VPC. Verified with `aws rds describe-db-instances`.

**Form 2 — Config drift:** Reading a config value and assuming it reflects deployed reality, or misreading it and not catching the error because the downstream reasoning felt coherent.
- Read `variables.tf` for staging instance class, stated `db.t4g.medium`
- Reality: staging `variables.tf` says `db.r5.xlarge`. The misread propagated through connection math, ticket content, and sizing recommendations before being caught.

**The defense against both:** Verify primary sources before building any analysis on top of them. A coherent-sounding argument built on an unverified premise is the most dangerous kind — it feels credible.

## Verification Sources by Fact Type

| Fact | Wrong source | Right source |
|---|---|---|
| RDS instance class | `variables.tf` default | `aws rds describe-db-instances` |
| RDS instances are shared | Hostname suffix similarity | `aws rds describe-db-instances` — compare endpoint addresses |
| DB connection count | Calculated from config | CloudWatch `DatabaseConnections` metric |
| Pod resource limits | values.yaml | `kubectl describe pod` or Datadog K8s infra |
| Active DB connections | `maxConns` × pods | `aws cloudwatch get-metric-statistics` |
| Error root cause | Error message text | Correlated metrics + logs at same timestamp |
| Config is deployed | Source file contents | Running pod env vars or deployed configmap |

## Investigation Protocol

### 1. Separate symptoms from causes

When Datadog shows errors, the error message describes the **symptom**, not the cause.

```
SYMPTOM:  "context deadline exceeded on DeleteWorkflowExecution"
CAUSE:    Unknown until verified — could be:
          - DB connection exhaustion
          - DB performance/I/O
          - Network timeout
          - Lock contention
          - RDS instance overloaded
```

State hypotheses explicitly as hypotheses. Never present a hypothesis as a finding.

### 2. Build a verification checklist before concluding

Before stating any infrastructure fact, ask: "Have I verified this from a primary source?"

For each hypothesis, list what evidence would confirm or refute it, then gather that evidence:

```
Hypothesis: Connection pool exhaustion
Confirms if: DatabaseConnections metric approaches max_connections ceiling
Refutes if:  DatabaseConnections << max_connections during error window
Action:      aws cloudwatch get-metric-statistics --metric-name DatabaseConnections
```

### 3. Verify config is what you think it is

Config files in the repo may not reflect what is actually deployed. Check:
- Is the Helm chart deployed from this values file?
- Has Terraform been applied recently?
- Are there environment-specific overrides?

When in doubt, verify the running state, not the source file.

### 4. State confidence levels explicitly

Use explicit markers when presenting findings:

- **Verified:** "AWS RDS confirms staging is `db.r5.xlarge`"
- **Unverified hypothesis:** "The hostname suffix suggests shared instance — needs AWS verification"
- **Speculation:** "This pattern sometimes indicates X, but we haven't checked"

Never omit the confidence level. Never present speculation as fact.

## Datadog Investigation Sequence

1. **Identify error patterns** — use log patterns view, not individual logs
2. **Get error volume over time** — is this a spike or sustained?
3. **Correlate with metrics** — what changed at the same timestamp?
4. **Identify the failing component** — which service, which operation, which shard?
5. **Form hypotheses** — list 2-3 possible causes
6. **Verify each hypothesis** — use AWS/kubectl/Datadog metrics as appropriate
7. **Conclude** — state which hypothesis the evidence supports

## Common Infrastructure Investigation Mistakes

| Mistake | Example | Fix |
|---|---|---|
| Pattern-matching hostnames | Same suffix → same instance | Run `aws rds describe-db-instances` |
| Reading defaults as deployed values | `variables.tf` default = actual instance class | Check TFE workspace output or `aws rds describe` |
| Treating symptoms as causes | "context deadline exceeded" = connection exhaustion | Check connection count metrics independently |
| Building analysis on unverified premises | Connection math on wrong instance class | Verify instance class first, then calculate |
| Anchoring on first hypothesis | First guess shapes all subsequent reasoning | Explicitly list alternative hypotheses |
| Config file = deployed state | values.yaml says X = cluster runs X | Verify with kubectl or AWS API |

## Red Flags — Stop and Verify

If you catch yourself doing any of these, stop and verify before continuing:

- "The hostname pattern suggests..." → verify with AWS API
- "Based on the config file..." → verify the config is actually deployed
- "This probably means..." → state it as a hypothesis, not a finding
- "This confirms that..." → list what evidence would refute it too
- Building connection math / capacity calculations before verifying instance specs
- Updating a Jira ticket with a finding you haven't verified from a primary source

## Toolchain Quick Reference

```bash
# Verify RDS instances (class, endpoint, status)
aws rds describe-db-instances \
  --query "DBInstances[?contains(DBInstanceIdentifier, 'your-app')].{ID:DBInstanceIdentifier,Endpoint:Endpoint.Address,Class:DBInstanceClass}" \
  --output table --profile <profile>

# Check active DB connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=<instance-id> \
  --start-time <iso> --end-time <iso> --period 300 --statistics Average \
  --profile <profile>

# Verify what's actually deployed in a pod
kubectl exec -n <namespace> <pod> -- env | grep TEMPORAL
kubectl describe pod -n <namespace> <pod> | grep -A5 Limits
```

For Datadog: always check metrics at the same timestamp as the error spike — correlation in time is the primary signal for causation hypotheses.
