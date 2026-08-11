---
title: "High Availability PostgreSQL: From Zero to Cluster"
date: 2026-08-06T10:00:00
draft: false
# TODO(shivansh): no featured image yet — add a real screenshot (e.g. the
# patronictl list output) to this folder and restore the image block below
# before merging:
# image:
#     url: patroni-list.png
#     attribution:
authors:
 - shivansh-source
tags:
 - postgresql
 - kubernetes
 - high-availability
 - openeverest
 - v2
summary: Deploying a 3-node PostgreSQL cluster on OpenEverest v2 with provider-percona-postgresql, and putting failover to the real test — killing the primary and timing how fast it recovers.
---

PostgreSQL is the workhorse of the web, but running it highly available is where most
setups quietly fall short. I wanted to see whether OpenEverest could actually deliver a
production-grade HA Postgres cluster, and then prove it by breaking it on purpose.

Everything below was run on a local kind cluster with OpenEverest v2 and
`provider-percona-postgresql`, which manages Postgres by driving Percona's own
Kubernetes operator underneath — so the HA logic you're seeing here (leader election,
timeline promotion, replica rejoin) is the same battle-tested Patroni-based mechanism
Percona ships in production, not something OpenEverest reimplemented itself. OpenEverest's
job is orchestration: turning a single `Instance` spec into a correctly-configured,
correctly-sized cluster.

**Environment:** kind v0.30.0 (4 nodes: 1 control-plane + 3 workers, `kindest/node:v1.34.0`),
kubectl v1.32.2, Helm v3.19.0.

## 1. Deploy

Installing the OpenEverest v2 core is a single Helm install:

```bash
helm repo add openeverest https://openeverest.github.io/helm-charts/
helm repo update
helm install everest-core openeverest/openeverest \
    --devel --version "2.0.0-dev.1" \
    --namespace everest-system --create-namespace
```

Two pods, up in about 6 seconds:

```
NAME                                  READY   STATUS    RESTARTS   AGE
everest-controller-5fbbd597dc-jj9rg   1/1     Running   0          60s
everest-server-7c74b67c76-vvg6s       1/1     Running   0          60s
```

**The Postgres provider isn't part of that install, though.** The output above only points
you at the MongoDB provider — that's accurate, not an oversight: the v2.0.0-dev.1 release
notes say plainly that the preview ships with a single reference provider (MongoDB),
chosen intentionally as the first one. `provider-percona-postgresql` exists in the
`openeverest` org, but as of this writing has zero tagged releases — you build and install
it straight from a `main` branch checkout:

```bash
git clone --depth 1 https://github.com/openeverest/provider-percona-postgresql.git
helm repo add percona https://percona.github.io/percona-helm-charts/
helm dependency build charts/provider-percona-postgresql   # pulls Percona's PG Operator chart v3.0.0
helm install provider-percona-postgresql charts/provider-percona-postgresql \
    --namespace everest-system --create-namespace
```

That install reported success, but the tagged core chart's CRDs turned out to already be
stale relative to what the provider expects. Applying the provider repo's own example CR
failed outright:

```
Error from server (BadRequest): error when creating "examples/instance-example.yaml":
Instance in version "v1alpha1" cannot be handled as a Instance:
strict decoding error: unknown field "spec.providerRef"
```

The dev.1-tagged core chart still ships the old `Instance` API (`spec.provider` as a plain
string); the provider's `main` branch already targets the new one
(`spec.providerRef.name`). The two repos drifted apart in the roughly two and a half
months since the dev.1 tag. The fix is the same one the provider's own `Makefile` already
runs (its `install-crds` target) — pull the CRDs from the `release-2.0` branch tip instead
of trusting the tagged chart:

```bash
kubectl apply -f https://raw.githubusercontent.com/openeverest/openeverest/release-2.0/config/crd/bases/core.openeverest.io_providers.yaml
kubectl apply -f https://raw.githubusercontent.com/openeverest/openeverest/release-2.0/config/crd/bases/core.openeverest.io_instances.yaml
```

Even past that, the provider repo's own shipped example CR reconciled straight to
`Failed` — it only declares an `engine` component, and the provider hard-requires a
`proxy` (PgBouncer) component too. So the spec below is one I wrote myself, not the
example.

One more thing worth knowing up front: **the Instance has to live in the same namespace
you installed the provider into.** The bundled Percona PG Operator defaults its watch
scope to its own release namespace, so an Instance created anywhere else just sits there
forever with no pods and no error — nothing in the docs says this. (I found out the slow
way, including a stuck `Terminating` delete that needed a manual finalizer patch to
clear.)

With that sorted, the actual database spec is refreshingly small. This is the whole
definition for a 3-node HA Postgres cluster:

```yaml
apiVersion: core.openeverest.io/v1alpha1
kind: Instance
metadata:
  name: pg-ha-demo
spec:
  providerRef:
    name: provider-percona-postgresql
  topology:
    type: cluster
  components:
    engine:
      type: postgresql
      replicas: 3
      resources:
        requests: { cpu: "250m", memory: 512Mi }
      storage:
        size: 5Gi
    proxy:
      type: pgbouncer
      replicas: 2
```

```bash
kubectl apply -f pg-ha-demo.yaml -n everest-system
```

The provider translates this into a `PerconaPGCluster` and the operator brings up five
pods — three Postgres engines, two PgBouncer proxies:

```
NAME                                    READY   STATUS    RESTARTS   AGE
pg-ha-demo-instance1-2jfq-0             2/2     Running   0          ...
pg-ha-demo-instance1-gqgt-0             2/2     Running   0          ...
pg-ha-demo-instance1-r9cw-0             2/2     Running   0          ...
pg-ha-demo-pgbouncer-...-bvbm6          2/2     Running   0          ...
pg-ha-demo-pgbouncer-...-df4zd          2/2     Running   0          ...

$ kubectl get instances -n everest-system
NAME         PROVIDER                      VERSION   PHASE   AGE
pg-ha-demo   provider-percona-postgresql   18.4-1    Ready   ...
```

Credentials are minted automatically by the operator and land in a Kubernetes Secret —
no manual wiring:

```
host           : pg-ha-demo-primary.everest-system.svc
pgbouncer-host : pg-ha-demo-pgbouncer.everest-system.svc
dbname         : pg-ha-demo
user           : pg-ha-demo
password       : <generated>
```

## 2. Configure

The only setting I actually tuned for this demo was replica count and storage size —
`engine.replicas: 3` and `storage.size: 5Gi` are the two knobs that matter for an HA
layout. The provider's `cluster` topology defaults to exactly this shape: one primary,
two replicas, fronted by a two-node PgBouncer proxy tier — a connection-pooling layer
clients connect to instead of the Postgres pods directly, so pod churn during a failover
doesn't require any client-side reconnect logic. For a heavier workload you'd raise the
resource requests; for this demo, minimal was plenty.

## 3. Verify HA

"Pods are Running" isn't proof of HA — so here's the actual replication state, queried
directly through Patroni, which the operator runs as the coordination layer:

```
$ kubectl get pods -l postgres-operator.crunchydata.com/cluster=pg-ha-demo \
    -L postgres-operator.crunchydata.com/role
NAME                           ROLE
pg-ha-demo-instance1-gqgt-0    primary
pg-ha-demo-instance1-2jfq-0    replica
pg-ha-demo-instance1-r9cw-0    replica
```

(Those labels really do say `crunchydata.com`, not a Percona one — that's not a typo in
this post. Percona's PostgreSQL Operator v3.0.0, which the provider bundles, is itself
built on top of CrunchyData's PGO, and hasn't renamed the CRD group or pod labels away
from it. Worth knowing if you go looking for "percona" in your own cluster's labels and
come up empty.)

```
$ kubectl exec pg-ha-demo-instance1-gqgt-0 -c database -- \
    psql -U postgres -d postgres -c \
    "select application_name, state, sync_state, replay_lag from pg_stat_replication;"

      application_name       |   state   | sync_state | replay_lag
-----------------------------+-----------+------------+------------
 pg-ha-demo-instance1-r9cw-0 | streaming | async      |
 pg-ha-demo-instance1-2jfq-0 | streaming | async      |
```

And Patroni's own cluster view, zero lag across the board:

```
$ kubectl exec ...gqgt-0 -- patronictl list
+ Cluster: pg-ha-demo-ha --------------------+---------+-----------+----+------------+-----+
|            Member           |     Role  |   State   | TL | Replay LSN | Lag |
+------------------------------+---------+-----------+----+------------+-----+
| pg-ha-demo-instance1-2jfq-0  | Replica | streaming |  1 |  0/A032A58 |   0 |
| pg-ha-demo-instance1-gqgt-0  | Leader  | running   |  1 |            |     |
| pg-ha-demo-instance1-r9cw-0  | Replica | streaming |  1 |  0/A032A58 |   0 |
```

To be extra sure, I wrote a row on the primary and read it back on both replicas
immediately — no delay, no manual sync:

```
$ kubectl exec ...gqgt-0 -- psql -c "INSERT INTO ha_demo_test (note) VALUES ('written on primary');"
INSERT 0 1
$ kubectl exec ...r9cw-0 -- psql -c "SELECT * FROM ha_demo_test;"
 id |         note
----+-----------------------
  1 | written on primary
$ kubectl exec ...2jfq-0 -- psql -c "SELECT * FROM ha_demo_test;"
 id |         note
----+-----------------------
  1 | written on primary
```

## 4. Chaos test — killing the primary

This is the real test of "is HA actually here." I hard-killed the primary pod with zero
grace period, then watched Patroni's leader-lock object for the failover:

```bash
kubectl delete pod pg-ha-demo-instance1-gqgt-0 --grace-period=0 --force
```

```
[+15s] leader=pg-ha-demo-instance1-2jfq-0   <- new leader elected
[+17s] leader=pg-ha-demo-instance1-2jfq-0   <- confirmed stable
```

**A new primary was elected and stable in 15–17 seconds, with zero manual
intervention.** Worth being precise about what that number actually measures: this is a
hard-killed *pod* that Kubernetes can reschedule straight onto already-healthy nodes.
Losing an entire node, or a network partition, exercises different timeouts entirely
(kubelet node-not-ready detection, pod eviction grace periods) and would very likely take
longer. Treat 15–17s as what a pod-level failure looks like here, not as a general
failover SLA.

The PostgreSQL timeline advanced correctly (TL 1 → 2), confirming this was a real
promotion, not just a label swap:

```
$ kubectl exec ...2jfq-0 -- patronictl list
| pg-ha-demo-instance1-2jfq-0 | Leader  | running   |  2 | ...
| pg-ha-demo-instance1-r9cw-0 | Replica | streaming |  2 | 0/B0002B0 | 0 |
```

The surviving replica followed the new timeline immediately, at zero lag.

**The connection endpoint updated automatically.** No secret changed, no DNS changed —
I connected through the exact same service name used before the kill and landed
straight on the new primary:

```
$ kubectl run pg-client-test --rm -i --image=percona/percona-distribution-postgresql:18.4-1 -- \
    psql -h pg-ha-demo-primary.everest-system.svc -U pg-ha-demo -d pg-ha-demo \
    -c "select pg_is_in_recovery(), inet_server_addr();"

 pg_is_in_recovery | inet_server_addr
--------------------+------------------
 f                  | 10.244.1.6        <- the new leader
```

**Zero data loss.** The row written before the kill was intact on the new leader, and a
fresh write after failover replicated immediately to the surviving replica:

```
$ kubectl exec ...2jfq-0 -- psql -c "SELECT * FROM ha_demo_test ORDER BY id;"
 id |                   note
----+-------------------------------------------
  1 | written on primary
 34 | written on new primary after failover
```

Worth stating plainly rather than glossing over: replication here is async — visible
back in the `pg_stat_replication` output earlier (`sync_state: async`) — and there was
exactly one in-flight transaction at kill time. Async replication *can* lose the most
recently committed transaction(s) if the primary dies before they ship to a replica; this
run just didn't land in that window. "Zero data loss" describes this specific test, not a
guarantee the setup gives you by default — if you need a stronger guarantee, that's a
`synchronous_commit` / synchronous-replica configuration question for the provider, not
something this test proves either way.

The old primary rejoined automatically once its pod restarted — Patroni detected the
timeline divergence and re-synced it as a replica, catching up to zero lag in under 30
seconds:

```
$ kubectl exec ...2jfq-0 -- patronictl list
| pg-ha-demo-instance1-2jfq-0 | Leader  | running   |  2 | ...
| pg-ha-demo-instance1-gqgt-0 | Replica | streaming |  2 | 0 lag
| pg-ha-demo-instance1-r9cw-0 | Replica | streaming |  2 | 0 lag
```

## Takeaway

The core HA behavior held up under an actual kill: automatic leader election, a real
timeline promotion rather than a label swap, a connection endpoint that followed the new
primary with no manual DNS or secret change, and no lost data in this particular run.
That's Percona's own production-grade PostgreSQL Operator and Patroni doing what they
already do in production — OpenEverest's job here is correctly turning a small
declarative `Instance` spec into that cluster, not reimplementing any of the HA logic
itself.

Getting there was rougher than the walkthrough above makes it look, though, and since
this is a developer preview it's worth being specific about where, rather than smoothing
it over:

- Postgres isn't part of the officially shipped v2.0.0-dev.1 preview —
  `provider-percona-postgresql` has no tagged releases yet, so you're building from
  `main`, not installing a supported artifact.
- The tagged core chart's CRDs are already out of sync with what the provider's `main`
  branch expects (`spec.provider` vs `spec.providerRef`) — a stock install plus the
  provider's own example fails on a schema error until you manually pull newer CRDs.
- The provider's own shipped example CR is itself broken (missing a required `proxy`
  component).
- The provider and its Instances have to share a namespace — undocumented, and getting it
  wrong fails silently instead of with an error.

None of that is a knock on the HA design itself — it's exactly the kind of rough edge
you'd expect from a provider repo that's still pre-release, and it's the kind of thing
that gets smoothed out fast once it's visible.

Also worth being upfront about: OpenEverest isn't tied to Percona specifically. It's
built to be provider-agnostic, and CloudNativePG is already available as a
community-contributed provider alongside Percona's. Both (and other extensions) are
listed in the [OpenEverest Hub](https://github.com/openeverest/hub) — the community
catalog of installable providers and plugins, itself currently in developer preview.
`provider-percona-postgresql` is just the one this post happened to test.

If you want to try this yourself, the provider repo has setup instructions at
[openeverest/provider-percona-postgresql](https://github.com/openeverest/provider-percona-postgresql).
