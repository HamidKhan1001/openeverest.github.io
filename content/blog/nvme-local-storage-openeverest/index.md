---
title: "Turbocharge Your Database: Using NVMe Local Storage with OpenEverest"
date: 2026-08-17T10:00:00
draft: false
image:
    url: cover.jpg
    attribution: https://unsplash.com/photos/black-and-gray-computer-hard-drive-FO7JIlwjOtU
authors:
  - Hamid Khan
tags:
  - tutorial
  - kubernetes
  - storage
  - performance
  - postgresql
summary: Network storage is convenient, but when your database needs real speed, nothing beats a locally-attached NVMe. Here is how to wire one up with OpenEverest.
---

I ran into this problem on a project last year. We had a PostgreSQL cluster happily sitting on network-attached storage, and everything was fine — until it wasn't. Write-heavy batch jobs started timing out, pgbench numbers were embarrassing, and every suggestion from the team landed on "maybe just throw more IOPS at it." We did. It helped, but not enough. Eventually someone suggested trying a local NVMe, almost as a joke. The difference was immediate and a little shocking.

This post walks through doing exactly that with OpenEverest. It is not complicated once you know which Kubernetes knobs to turn. I will show you the storage class, the PV, how to point OpenEverest at it, and how to prove it is faster.

# The Setup

You need a Kubernetes node with a locally-attached NVMe drive. The three most common situations are:

- **AWS i3 or i4i instances** — these ship with NVMe instance store disks. An `i4i.xlarge` gives you a 937 GB NVMe SSD ready to go.
- **Bare metal** — any server where you have a drive formatted and mounted at a known path.
- **Local dev with kind** — no hardware needed. Scroll to the appendix at the bottom; a loop device gets you the same configuration experience.

For the rest of this post I will assume:
- One node named `node1`
- An NVMe device at `/dev/nvme0n1`, formatted as ext4 and mounted at `/mnt/nvme`
- OpenEverest is already installed (the [quickstart guide](https://docs.openeverest.io/docs/quickstart-guide/) takes about ten minutes)

Quick sanity check on the node:

```bash
lsblk /dev/nvme0n1
# NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
# nvme0n1     259:0    0 931.5G  0 disk /mnt/nvme
```

Good. Let's wire it up.

# Step 1 — Tell Kubernetes About the Disk

Kubernetes does not discover local disks automatically. You need to create a `StorageClass` that marks this as a local, non-dynamic provisioner, and a `PersistentVolume` that points at your actual mount path.

**StorageClass:**

```yaml
# storageclass-nvme.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nvme-local
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
```

```bash
kubectl apply -f storageclass-nvme.yaml
```

The `WaitForFirstConsumer` binding mode is important. Without it, Kubernetes might bind the PVC to a node that does not actually have the NVMe disk, and your pod will never schedule.

**Create the directory on the node:**

```bash
ssh node1
sudo mkdir -p /mnt/nvme/postgresql
sudo chmod 777 /mnt/nvme/postgresql
```

**PersistentVolume:**

```yaml
# pv-nvme-postgresql.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nvme-pv-postgresql
spec:
  capacity:
    storage: 100Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: nvme-local
  local:
    path: /mnt/nvme/postgresql
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
                - node1   # replace with your actual node name
```

```bash
kubectl apply -f pv-nvme-postgresql.yaml
kubectl get pv nvme-pv-postgresql
# NAME                   CAPACITY   RECLAIM POLICY   STATUS      STORAGECLASS
# nvme-pv-postgresql     100Gi      Delete           Available   nvme-local
```

# Step 2 — Deploy a Database on That Storage

Open the OpenEverest UI, create a new PostgreSQL cluster, and under **Advanced Settings → Storage** select `nvme-local` as the storage class. That is it on the UI side.

If you prefer the command line, patch an existing cluster:

```bash
kubectl patch databasecluster my-pg \
  --type=merge \
  --patch '{"spec":{"engine":{"storage":{"class":"nvme-local","size":"100Gi"}}}}'
```

OpenEverest reconciles immediately. It creates a PVC with `storageClassName: nvme-local`, the scheduler picks `node1` (the only node with a matching PV), and the database pod comes up with its data directory living on `/mnt/nvme/postgresql`.

Confirm the PVC is actually bound to your NVMe volume:

```bash
kubectl get pvc -n everest-db
# NAME      STATUS   VOLUME               CAPACITY   STORAGECLASS
# my-pg-0   Bound    nvme-pv-postgresql   100Gi      nvme-local
```

If you see `Bound` and the right PV name, you are done with the setup.

# Step 3 — Prove It Is Faster

I use `pgbench` for this. It is built into the PostgreSQL image so there is nothing extra to install. Initialize the benchmark schema first:

```bash
kubectl run pgbench --rm -it --image=postgres:16 \
  --env="PGPASSWORD=supersecret" \
  --restart=Never -- \
  pgbench -i -s 50 \
    -h my-pg-rw.everest-db.svc \
    -U myuser mydb
```

Then run the actual benchmark — 60 seconds, 8 clients:

```bash
kubectl run pgbench --rm -it --image=postgres:16 \
  --env="PGPASSWORD=supersecret" \
  --restart=Never -- \
  pgbench -c 8 -j 4 -T 60 \
    -h my-pg-rw.everest-db.svc \
    -U myuser mydb
```

Here are the numbers I got comparing a standard `gp3` EBS volume (the default on AWS) against the NVMe instance store on an `i4i.xlarge`:

| Storage | Transactions/sec | Avg latency |
|---|---|---|
| AWS gp3 (3000 IOPS) | 412 | 19.4 ms |
| **NVMe local (i4i.xlarge)** | **3,847** | **2.1 ms** |

About 9× the throughput, almost a tenth of the latency. Your numbers will vary depending on the workload and hardware, but the gap is real and consistent for write-heavy workloads.

# Cleanup

When you are done, delete the cluster from the OpenEverest UI and then remove the Kubernetes objects:

```bash
kubectl delete pv nvme-pv-postgresql
kubectl delete storageclass nvme-local

# On node1, clear the data directory:
sudo rm -rf /mnt/nvme/postgresql
```

# Appendix: No NVMe? Simulate One with a Loop Device

If you are on a laptop or a dev cluster without local disks, you can still follow the entire setup using a loop device. It will not be fast, but the configuration is identical — which is exactly the point if you are trying to validate your YAML before deploying on real hardware.

```bash
# Create a 10 GB sparse file and attach it
dd if=/dev/zero of=/tmp/fake-nvme.img bs=1 count=0 seek=10G
sudo losetup /dev/loop8 /tmp/fake-nvme.img
sudo mkfs.ext4 /dev/loop8
sudo mkdir -p /mnt/nvme
sudo mount /dev/loop8 /mnt/nvme
```

From here, follow Steps 1 and 2 exactly as written. The storage class and PV do not care whether they are talking to a real NVMe or a loop device — they just see a filesystem path.

---

Storage classes are one of the most underused levers in Kubernetes database management. Because OpenEverest lets you specify a storage class per cluster, you can run cost-optimized network volumes for your dev databases and latency-optimized local NVMe for production — same operator, same workflow, one field difference. If you try this and get interesting numbers, drop them in the [OpenEverest community forum](https://forums.percona.com/c/percona-everest/81). Always curious to see what different hardware looks like.
