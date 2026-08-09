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

**Environment:** kind v0.30.0 (1 control-plane + 3 workers), kubectl v1.32.2, Helm v3.19.0.

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

With the provider installed and registered (I installed it into the same `everest-system`
namespace as the core — worth doing consistently since the provider watches its own
release namespace), the actual database spec is refreshingly small. This is the whole
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

Credentials come out the other side automatically, no manual wiring:

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
two replicas, fronted by a two-node PgBouncer proxy tier. For a heavier workload you'd
raise the resource requests; for this demo, minimal was plenty.

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
intervention.** The PostgreSQL timeline advanced correctly (TL 1 → 2), confirming this
was a real promotion, not just a label swap:

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

The core promise held up: define a small, declarative `Instance` spec, and get a real
3-node HA PostgreSQL cluster with automatic leader election, sub-20-second failover, zero
data loss, and a connection endpoint that follows the leader without any manual DNS or
secret updates. That reliability isn't OpenEverest reinventing database internals — it's
OpenEverest correctly orchestrating Percona's own production-grade operator, which is
exactly the kind of separation of concerns you want from a provider model: OpenEverest
handles the declarative interface and lifecycle, the operator handles the hard
distributed-systems part it's already proven at scale.

A couple of rough edges are worth a quick note since this is a v2 developer preview: the
Postgres provider isn't bundled in the dev.1 release yet (it's a separate, actively
developed repo), and I had to apply a couple of CRD updates by hand to match the
provider's current API. Nothing that affected the HA behavior itself — just setup
friction you should expect from software still labeled "developer preview."

If you want to try this yourself, the provider repo has setup instructions at
[openeverest/provider-percona-postgresql](https://github.com/openeverest/provider-percona-postgresql).
