 Troubleshooting Log

This file contains real issues encountered during setup.

---

There were 3 problems that stacked on top of each other:
1. The encryption config had an unsubstituted placeholder

This was the root cause of everything. The file had secret: ${ENCRYPTION_KEY} literally — the template variable was never replaced with a real base64 key. This caused kube-apiserver to crash on every start with "secrets must be base64 encoded".
2. Missing kubeconfig files for kube-scheduler and kube-controller-manager

The files kube-scheduler.kubeconfig and kube-controller-manager.kubeconfig were never moved from ~/ into /var/lib/kubernetes/ where the service unit files expected them. So those two services crashed immediately on start.
3. The admin.kubeconfig had no cluster server defined

The kubeconfig on server had clusters: null — it was pointing to http://localhost:8080 (the old insecure default) instead of https://127.0.0.1:6443. That's why every kubectl command said "connection refused" even when the API server was actually running fine earlier in the session.
Why it was hard to spot: Problem 1 kept killing kube-apiserver before it could bind to port 6443, so it looked like a networking or kubeconfig problem. Problems 2 and 3 were real but were masking the actual blocker underneath.

##  kubelet inactive

### Problem
Nodes were not registering.


systemctl is-active kubelet
# inactive



also
