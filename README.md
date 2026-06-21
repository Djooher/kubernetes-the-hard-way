# kubernetes-the-hard-way



# Kubernetes The Hard Way — AWS

> Deployed a production-grade Kubernetes v1.32 cluster from scratch on AWS EC2,  
> without using kubeadm or any automation tool.  
> Based on [Kelsey Hightower's Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way).

---

## What This Is

This project documents how I manually bootstrapped a fully functional Kubernetes cluster on AWS EC2 — configuring every component by hand, diagnosing real failures, and fixing them from scratch.

No kubeadm. No Helm. No shortcuts.

---

## Architecture

```
                        ┌─────────────────────────────────┐
                        │         AWS VPC (172.31.0.0/16) │
                        │                                  │
                        │  ┌──────────────────────────┐   │
                        │  │     jumpbox (admin)       │   │
                        │  │     172.31.19.77          │   │
                        │  └────────────┬─────────────┘   │
                        │               │ SSH              │
                        │   ┌───────────▼──────────────┐  │
                        │   │        server             │  │
                        │   │     172.31.37.240         │  │
                        │   │                           │  │
                        │   │  - etcd                   │  │
                        │   │  - kube-apiserver         │  │
                        │   │  - kube-controller-manager│  │
                        │   │  - kube-scheduler         │  │
                        │   └───────────────────────────┘  │
                        │                                   │
                        │   ┌───────────────────────────┐  │
                        │   │        node-0             │  │
                        │   │     172.31.28.246         │  │
                        │   │   podCIDR: 10.200.0.0/24  │  │
                        │   │                           │  │
                        │   │  - containerd             │  │
                        │   │  - kubelet                │  │
                        │   │  - kube-proxy             │  │
                        │   └───────────────────────────┘  │
                        │                                   │
                        │   ┌───────────────────────────┐  │
                        │   │        node-1             │  │
                        │   │     172.31.20.138         │  │
                        │   │   podCIDR: 10.200.1.0/24  │  │
                        │   │                           │  │
                        │   │  - containerd             │  │
                        │   │  - kubelet                │  │
                        │   │  - kube-proxy             │  │
                        │   └───────────────────────────┘  │
                        └─────────────────────────────────┘
```

---

## Stack

| Component | Version |
|---|---|
| Kubernetes | v1.32.3 |
| etcd | v3.x |
| containerd | v2.1.0 |
| OS | Debian 13 (trixie) |
| Cloud | AWS EC2 |

---

## What I Built — Step by Step

### 1. PKI & TLS Certificates
Generated all certificates manually using OpenSSL:
- CA certificate and key
- API server certificate (with SANs for all hostnames and IPs)
- kubelet client certificates (per node)
- kube-controller-manager, kube-scheduler, kube-proxy certificates
- admin client certificate
- Service account key pair

### 2. Kubeconfig Files
Generated kubeconfig files for every component:
- `admin.kubeconfig`
- `kube-controller-manager.kubeconfig`
- `kube-scheduler.kubeconfig`
- `kube-proxy.kubeconfig`
- Per-node `kubeconfig` for kubelets

### 3. Encryption at Rest
Configured `EncryptionConfiguration` for etcd using AES-CBC with a randomly generated 256-bit key. Verified secrets are encrypted in etcd:

```
k8s:enc:aescbc:v1:key1:...
```

### 4. etcd Cluster
Bootstrapped etcd as a single-node cluster on the control plane server.

### 5. Kubernetes Control Plane
Deployed and configured as systemd services:
- `kube-apiserver` — with RBAC, Node authorization, TLS, audit logging
- `kube-controller-manager` — with node CIDR allocation
- `kube-scheduler` — with kubeconfig-based config file

### 6. Worker Nodes
Configured both worker nodes with:
- `containerd` as the container runtime
- `kubelet` with TLS bootstrap and webhook auth
- `kube-proxy` for service networking
- CNI bridge plugin for pod networking

### 7. Pod Network Routes
Added static IP routes on each node so pods across different nodes can communicate:
- server → node-0 (10.200.0.0/24) and node-1 (10.200.1.0/24)
- node-0 → node-1
- node-1 → node-0

### 8. Smoke Tests
Verified the cluster with:
- Secret encryption at rest
- nginx deployment and pod scheduling
- kubectl port-forward
- kubectl logs and exec
- NodePort service access

---

## Real Problems I Diagnosed and Fixed

This is what makes this project real. I didn't just follow a tutorial — I hit actual failures and debugged them.

### Problem 1 — Unsubstituted encryption key placeholder
**Symptom:** `kube-apiserver` crashed on every start with:
```
secrets must be base64 encoded
```
**Root cause:** The `encryption-config.yaml` template was never rendered — it contained a literal `${ENCRYPTION_KEY}` placeholder instead of a real base64 key.

**Fix:** Generated a proper 256-bit random key and wrote it into the config:
```bash
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
```

---

### Problem 2 — Missing kubeconfig files for control plane components
**Symptom:** `kube-scheduler` and `kube-controller-manager` crashed immediately with:
```
stat /var/lib/kubernetes/kube-scheduler.kubeconfig: no such file or directory
```
**Root cause:** The kubeconfig files were transferred to `~/` on the server but never moved to `/var/lib/kubernetes/` where the service unit files expected them.

**Fix:**
```bash
mv ~/kube-controller-manager.kubeconfig /var/lib/kubernetes/
mv ~/kube-scheduler.kubeconfig /var/lib/kubernetes/
```

---

### Problem 3 — admin.kubeconfig pointing to wrong server
**Symptom:** Every `kubectl` command returned:
```
dial tcp [::1]:8080: connect: connection refused
```
**Root cause:** The `admin.kubeconfig` had `clusters: null` — no server was set. kubectl was defaulting to the old insecure `http://localhost:8080` endpoint instead of `https://127.0.0.1:6443`.

**Fix:**
```bash
kubectl config set-cluster kubernetes-the-hard-way \
  --server=https://127.0.0.1:6443 \
  --certificate-authority=/var/lib/kubernetes/ca.crt \
  --embed-certs=true \
  --kubeconfig=/root/admin.kubeconfig
```

---

### Problem 4 — Nodes couldn't reach the API server (DNS)
**Symptom:** kubelets on worker nodes logged:
```
dial tcp: lookup server.kubernetes.local: Temporary failure in name resolution
```
**Root cause:** The `/etc/hosts` file was missing from the worker nodes — they had no way to resolve `server.kubernetes.local`.

**Fix:** Copied the hosts file to both nodes:
```bash
scp hosts root@node-0:/etc/hosts
scp hosts root@node-1:/etc/hosts
```

---

### Problem 5 — AWS Security Groups blocking cluster traffic
**Symptom:** Even after DNS was fixed, nodes still couldn't reach the API server — connection timed out to `172.31.37.240:6443`.

**Root cause:** AWS Security Groups were blocking inbound traffic on ports 6443 (API server), 10250 (kubelet), and 30000-32767 (NodePorts) between instances.

**Fix:** Added inbound rules to all instance security groups:
- TCP 6443 — source `172.31.0.0/16`
- TCP 10250 — source `172.31.0.0/16`
- TCP 30000-32767 — source `172.31.0.0/16`

---

### Problem 6 — CNI bridge plugin failing with empty subnet
**Symptom:** Pods stuck in `Pending` with:
```
plugin type="bridge" failed (add): invalid CIDR address:
```
**Root cause:** The `10-bridge.conf` CNI config had `"subnet": ""` — an unfilled template. The controller manager was also missing `--allocate-node-cidrs=true` so nodes never got a `podCIDR` assigned.

**Fix:**
1. Added `--allocate-node-cidrs=true` to `kube-controller-manager.service`
2. Manually wrote the correct subnet into each node's CNI config:
   - node-0: `10.200.0.0/24`
   - node-1: `10.200.1.0/24`

---

## Verification

```bash
$ kubectl get nodes
NAME     STATUS   ROLES    AGE   VERSION
node-0   Ready    <none>   40m   v1.32.3
node-1   Ready    <none>   40m   v1.32.3

$ kubectl get pods -l app=nginx
NAME                     READY   STATUS    RESTARTS   AGE
nginx-54c98b4f84-77nfc   1/1     Running   0          18m

$ curl -I http://node-0:32377
HTTP/1.1 200 OK
Server: nginx/1.31.2
```

Encryption verified in etcd:
```
00000030  79 0a 6b 38 73 3a 65 6e  63 3a 61 65 73 63 62 63  |y.k8s:enc:aescbc|
00000040  3a 76 31 3a 6b 65 79 31  3a ...                   |:v1:key1:...|
```

---

## Key Learnings

- Every Kubernetes component is just a binary + a systemd service + a kubeconfig. Once you've done it by hand, you understand what kubeadm is actually doing.
- TLS is everywhere — every component authenticates to every other component with certificates.
- AWS Security Groups are implicit firewalls — ports between EC2 instances are blocked by default even within the same VPC.
- The CNI plugin is what actually gives pods IP addresses — without a valid subnet configured, nothing can run.
- Debugging `systemctl` + `journalctl` is the core skill for Kubernetes operations.

---

## Credits

Based on [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way) by Kelsey Hightower.  
All deployment, debugging, and fixes were done independently on AWS EC2.
