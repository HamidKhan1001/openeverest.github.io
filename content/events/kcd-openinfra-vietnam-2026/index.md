---
title: "Beyond Built-in Engines: Extending OpenEverest into a Universal Database Control Plane"
date: 2026-07-20
draft: false
summary: "Tan Huy Nguyen and Vinh Bui Hoang show how they built a unified database control plane on top of OpenEverest at KCD & OpenInfra Days Vietnam 2026 in Hanoi."
event_name: "KCD & OpenInfra Days Vietnam 2026"
event_url: "https://2026.vietopeninfra.org/en/"
event_date: 2026-07-25
location: "Hanoi, Vietnam — Sheraton Hanoi Hotel"
date_range: "July 25, 2026"

# Session details
schedule:
  - label: "Session"
    value: "Beyond Built-in Engines: Extending OpenEverest into a Universal Database Control Plane"
  - label: "When"
    value: "Saturday, July 25 · 8:00 AM – 8:30 AM"
  - label: "Room"
    value: "Room 3"

# Speakers presenting the session
representatives:
  - name: "Tan Huy Nguyen"
    role: "Cloud Engineer at Viettel"
  - name: "Vinh Bui Hoang"
    role: "Cloud Engineer at Viettel"
---

Running a DBaaS platform on Kubernetes means dealing with a fragmented operator
ecosystem — each engine ships its own Operator, CRDs, backup and monitoring
setup. No shared API. Platform teams write separate integration code per engine,
maintain separate runbooks, and re-solve the same problems each time a new engine
is added.

This session walks through how the presenters built a unified control plane on
top of OpenEverest — a custom adapter layer with CRD translation, a lifecycle
bridge for engine-specific behaviors, and a status aggregation layer normalizing
everything back to a single `DatabaseCluster` API. Any engine with a Kubernetes
Operator can be plugged in.

In the staging environment, multiple engines across different workload types are
provisioned through the same pipeline — same backup, monitoring, upgrades, no
engine-specific tooling. The talk covers what the adapter looks like in practice,
where it got complicated, and how Day 2 ops work across a heterogeneous fleet.
