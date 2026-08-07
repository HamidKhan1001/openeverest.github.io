---
title: "Building a CloudNativePG Provider with OpenEverest v2"
date: 2026-08-07T06:10:00
draft: true
image:
    url: openeverest_cloudnativepg.png
    attribution:
authors:
  - adityapimpalkar
tags:
  - CloudnativePG
  - v2
  - provider
  - kubernetes
  - databases
  - postgresql
summary: 
  How I built a CloudNativePG provider on OpenEverest v2 from day-one provisioning to backups.
---
## What is CloudNativePG?

[CloudNativePG](https://cloudnative-pg.io/) (CNPG) is an open-source operator designed to manage PostgreSQL workloads on any supported Kubernetes cluster. It fosters cloud-neutrality through seamless deployment in private, public, hybrid, and multi-cloud environments via its distributed topology feature.

Built around DevOps principles, CloudNativePG embraces declarative configuration and immutable infrastructure, ensuring reliability and automation in database management.

At its core, CloudNativePG introduces a custom Kubernetes resource called Cluster, representing a PostgreSQL cluster with:

- A single primary instance for write operations.
- Optional replicas for High Availability and read scaling.

In short: CloudNativePG is the operator layer that turns “I want Postgres on this cluster” into a reconciled, observable Kubernetes workload.


## Why choose CloudNativePG?

OpenEverest v1 baked database-specific logic into the core. Adding a new engine meant touching the server, operator, CLI, and UI. v2 flips that model. A **Provider** is a self-contained plugin with it owns the component catalog, topologies, UI schema, and reconciliation against a real Kubernetes operator. CloudnativePG is a CNCF Sandbox project and it has been gaining some reputable traction over the years, becoming a de facto standard for running PostgreSQL on Kubernetes. Since OpenEverest comes with support for Percona PostgresSQL in v1, a community driven CloudnativePG would make a great alternative alongside Percona's PostgresSQL.

## Implementation journey 

### Day-one operations came quickly

The first slice of the provider was surprisingly smooth.

***Core provisioning***: scaffolding with the [Provider SDK](https://github.com/openeverest/provider-sdk), wiring `Sync` to create a CloudNativePG `Cluster` from the `Instance` engine component, and getting basic status reconciliation working. Once the mental model clicked, day-one create/reconcile felt natural.

***UI and resource settings***: expanding the `replicaSet` UI schema, PostgreSQL parameters, managed roles, and separate CPU/memory requests and limits. The definition-driven UI meant most of this was schema work plus small Go type changes, not a custom frontend.

That early progress was motivating. The harder work started when we moved past from simply spin up a cluster into real CloudNativePG depth.

### Going deeper: bootstrap, platform features, and backup

***Bootstrap (initdb)*** needed careful reading of CloudNativePG’s bootstrap docs - database name, owner, and credential secrets and making sure the provider passed them through correctly without fighting CNPG defaults.

***Certificates, monitoring, and local/CI tooling*** pushed further into operator behavior and cluster lifecycle. Getting cert support, monitoring hooks, Tilt for local loops, and kuttl integration tests in place meant more time in CloudNativePG docs and more careful RBAC/watch wiring than the day-one path.

***Backup*** was the steepest climb. On-demand backups and Barman cloud plugin integration required a lot of digging into CloudNativePG’s documentation and its Go SDK/APIs ObjectStore, plugin configuration, backup/restore status shapes, and how those map cleanly onto OpenEverest’s backup interfaces. That exploration consumed the most time, but its also where the provider started to feel like a real operational surface, not just a thin translator.

### Dogfooding the platform: bugs and UX gaps
Building against a real operator is the fastest way to find platform rough edges.

While implementing `Status()`, I returned human-readable progress messages:

```go
return controller.Provisioning("waiting for CloudNativePG cluster to initialize"), nil
```
The phase showed up. The message did not on the Instance CR, not in logs developers care about, not in the UI. Operators only saw `Provisioning` phase with no hint of if or what the provider was waiting on.

Root cause: `ToV2Alpha1()` silently dropped `Status.Message`. I filed [#2359](https://github.com/openeverest/openeverest/issues/2359) and fixed it upstream in PR [#2366](https://github.com/openeverest/openeverest/pull/2366) by plumbing message through the API/CRD and conversion path.

That fix matters for every provider, not just this one. Status helpers like `Provisioning(...)` and `Initializing(...)` only help if the message survives into the Instance status users actually look at.

Along the way I also filed smaller UX improvements against OpenEverest itself - for example [#2452](https://github.com/openeverest/openeverest/issues/2423), asking the preview form to show resource units (`Gi`, `mi`, etc.) next to CPU, memory, and disk values. Building a provider surfaces both hard bugs and polish opportunities filing them back is part of the job.

Additionally, after giving a coummunity call feedback about wanting a hot-reload developer setup using `tilt` which allows you to get up and running as a developer without running a bunch of commands first was also taken into consideration and later added to the Provider SDK. Building a real provider is how I was able to find platform gaps and address them personally or relay the feedback to the maintainers.

### What's next?
This provider can create and reconcile CloudNativePG clusters from OpenEverest Instance CRs for local development and testing. Core provisioning: replicas, storage, resources, versions, bootstrap, PostgreSQL tuning, managed roles is in place, with kuttl coverage for basic flows. Backup support exists but still needs more hardening; restore, pooling, and production-grade CI/ops polish are still outstanding.

Keep building with OpenEverest provider model and keep improving it to make the platform better with each feedback and fixes.

If you try it:
- Expect sharp edges: [please open an issue](https://github.com/adityapimpalkar/provider-cloudnative-pg)
- Read the SDK guide before forking your own provider: [PROVIDER_DEVELOPMENT.md](https://github.com/openeverest/provider-sdk/blob/main/PROVIDER_DEVELOPMENT.md) and read about the [provider/plugin architechture spec](https://github.com/openeverest/specs/blob/main/specs/001-plugins-architecture.md)
- Contributions and feedback on both the provider and OpenEverest v2 are welcome


## Join the Community

* **Contribute:** If you want to dive in, check out our [Good First Issues](https://github.com/orgs/openeverest/projects/2) and [repositories](https://github.com/openeverest).
* **Chat:** Join the conversation in the CNCF Slack (channel: [#openeverest-users](https://cloud-native.slack.com/archives/C09RRGZL2UX)).
* **Explore:** See how we're simplifying databases at [openeverest.io/#community](https://openeverest.io/#community).
<div style="display:flex;gap:12px;margin-top:24px;flex-wrap:wrap;">
  <a href="https://cloud-native.slack.com/archives/C09RRGZL2UX" target="_blank" rel="noopener noreferrer" style="display:inline-flex;align-items:center;gap:8px;background-color:#4A154B;color:#fff;text-decoration:none;padding:10px 20px;border-radius:6px;font-weight:600;font-size:15px;">
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 122.8 122.8"><path d="M25.8 77.6c0 7.1-5.8 12.9-12.9 12.9S0 84.7 0 77.6s5.8-12.9 12.9-12.9h12.9v12.9zm6.5 0c0-7.1 5.8-12.9 12.9-12.9s12.9 5.8 12.9 12.9v32.3c0 7.1-5.8 12.9-12.9 12.9s-12.9-5.8-12.9-12.9V77.6z" fill="#e01e5a"/><path d="M45.2 25.8c-7.1 0-12.9-5.8-12.9-12.9S38.1 0 45.2 0s12.9 5.8 12.9 12.9v12.9H45.2zm0 6.5c7.1 0 12.9 5.8 12.9 12.9s-5.8 12.9-12.9 12.9H12.9C5.8 58.1 0 52.3 0 45.2s5.8-12.9 12.9-12.9h32.3z" fill="#36c5f0"/><path d="M97 45.2c0-7.1 5.8-12.9 12.9-12.9s12.9 5.8 12.9 12.9-5.8 12.9-12.9 12.9H97V45.2zm-6.5 0c0 7.1-5.8 12.9-12.9 12.9s-12.9-5.8-12.9-12.9V12.9C64.7 5.8 70.5 0 77.6 0s12.9 5.8 12.9 12.9v32.3z" fill="#2eb67d"/><path d="M77.6 97c7.1 0 12.9 5.8 12.9 12.9s-5.8 12.9-12.9 12.9-12.9-5.8-12.9-12.9V97h12.9zm0-6.5c-7.1 0-12.9-5.8-12.9-12.9s5.8-12.9 12.9-12.9h32.3c7.1 0 12.9 5.8 12.9 12.9s-5.8 12.9-12.9 12.9H77.6z" fill="#ecb22e"/></svg>
    Join Slack
  </a>
  <a href="https://github.com/openeverest/openeverest" target="_blank" rel="noopener noreferrer" style="display:inline-flex;align-items:center;gap:8px;background-color:#24292f;color:#fff;text-decoration:none;padding:10px 20px;border-radius:6px;font-weight:600;font-size:15px;">
    <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 16 16" fill="#fff"><path d="M8 .25a7.75 7.75 0 1 0 0 15.5A7.75 7.75 0 0 0 8 .25zm0 1.5a6.25 6.25 0 0 1 1.97 12.18c-.31.06-.42-.13-.42-.3v-1.05c0-.36-.01-1.02-.49-1.4 1.62-.18 2.5-.88 2.5-2.57 0-.57-.2-1.1-.53-1.49.05-.14.23-.7-.05-1.47 0 0-.44-.14-1.44.54a5.02 5.02 0 0 0-2.62 0C5.93 6.6 5.49 6.74 5.49 6.74c-.28.77-.1 1.33-.05 1.47-.33.39-.53.92-.53 1.49 0 1.69.88 2.39 2.5 2.57-.31.27-.43.67-.47 1.04-.42.19-1.5.52-2.16-.62 0 0-.39-.71-1.13-.76 0 0-.72-.01-.05.45 0 0 .48.23.82 1.08 0 0 .43 1.32 2.49.87v.75c0 .17-.11.36-.42.3A6.25 6.25 0 0 1 8 1.75z"/></svg>
    Star the Repo
  </a>
</div>
