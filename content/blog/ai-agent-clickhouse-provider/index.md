---
title: "How an AI Agent Shipped a ClickHouse Provider for OpenEverest — and What That Says About the Abstraction"
date: 2026-07-06T10:00:00
draft: false
authors:
  - jtomaszon
tags:
  - blog
  - clickhouse
  - providers
  - kubernetes
  - databases
  - ai
summary: "A field report on building a ClickHouse provider for OpenEverest — how little we actually had to build, and how far an AI agent could carry it because the abstraction did the hard part."
---

I came to OpenEverest as an outside contributor with one goal: stand up a working ClickHouse provider wrapping the Altinity operator. The provider lives here: [openeverest/provider-altinity-clickhouse](https://github.com/openeverest/provider-altinity-clickhouse). The part worth writing about isn't that it worked — it's how little we actually had to build, and that a big chunk of the implementation was driven by an AI agent running as part of ScaleDB's ops stack. The abstraction was clean enough that the agent could pick the path of least resistance and land a real provider.

### What "ready to start" actually looks like

You're not building a database orchestrator from scratch. OpenEverest hands you the hard parts as a contract:

- The **Provider CRD** and reconcile loop — the lifecycle is defined, you implement against it.
- **RBAC, health probes, and the Helm-subchart wrap** — the Kubernetes plumbing is scaffolded.
- A **Tilt dev flow + kuttl harness** — a working local loop and a way to prove your reconcile does what you think.

So the surface area you actually own is small: wrap an existing operator (Altinity), fill in the ClickHouse-specific reconcile logic, and let the platform carry the rest. The provider you ship is mostly a thin domain layer on top of a chassis that already exists. That's the whole point of the abstraction, and it holds up in practice.

### Why an AI agent could carry it

An AI agent thrives when the loop is tight and the contract is clear: change → deploy → observe → correct, with a deterministic signal at each step. OpenEverest's dev flow gives exactly that — Tilt live-reloads onto a local k3d cluster, and kuttl tells you objectively whether the reconcile passed. Bounded surface area plus a fast, honest feedback loop is precisely the environment where an agent can iterate without a human babysitting every step.

We ran the full path end-to-end: the provider builds, the pod comes up Ready, the controller reconciles, and a `ClickHouseInstallation` gets provisioned for real. Most of that iteration was agent-driven, with me steering the decisions. The abstraction is what made that division of labor possible — the platform absorbed the complexity that would otherwise have needed a human in the loop constantly.

### The first-run friction

To be fair, there were a handful of first-run gotchas — none hard, all nameable, and each one a one-line fix once you know it. The one that cost us the most time: the health probes defaulted to the wrong endpoint. The provider runtime serves `/healthz` (liveness) and `/readyz` (readiness), but the probes were pointed at a path that 404s — so the process was healthy and the pod never went Ready. Classic "everything's up but nothing's green."

The rest were the usual first-run tax: an RBAC group that needs to be present, keeping the Provider CR name in sync with the provider's identity constant in code, and k3d's 33-character cluster-name limit (small, dumb, real — a long name silently fails to create).

None of these are hard. All of them cost time when you don't know them yet. So we folded them back into the provider SDK — fixing the defaults at the source and adding a short "first-run gotchas" section to the development guide — so the next contributor skips the hour we spent.

### What made it click

Get one provider right and the shape carries. The Provider contract, the scaffolded plumbing, the dev loop — that's a chassis you stamp new data engines onto, not a pile of bespoke integrations. That reusability is what turns "contribute a provider" from a research project into a repeatable job.

### Where we're headed

We're now extending the same pattern to streaming — Redpanda and Strimzi/Kafka broker providers with Debezium-based CDC as the payoff — to close the gap toward end-to-end change-data-capture pipelines provisioned the same way as a database.

### Closing note

If you're thinking about contributing a provider: the lift is smaller than it looks, because the platform already did the hard part. The abstraction is clean enough that we could hand a lot of the build to an AI agent and get a working provider out the other side — and once the first one is green, the second is dramatically faster.
