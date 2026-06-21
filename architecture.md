
---

#  2. `docs/architecture.md`


<img width="675" height="598" alt="image" src="https://github.com/user-attachments/assets/b8061c85-9cd1-4298-9239-6a08ee55ea75" />

#  Cluster Architecture

This Kubernetes cluster is composed of 3 main parts.

---

##  Jumpbox

Used as the administration machine:
- Runs kubectl
- Connects to API server
- Manages cluster resources

---

##  Control Plane

The brain of the cluster:

### kube-apiserver
- Entry point of Kubernetes
- Handles all requests

### kube-scheduler
- Assigns pods to nodes

### kube-controller-manager
- Maintains cluster state

---

 Worker Nodes

Responsible for running workloads:

- kubelet → manages pods
- container runtime → runs containers (containerd)

---
 Communication Flow

User → kubectl → API Server → Scheduler → Kubelet → Container Runtime
