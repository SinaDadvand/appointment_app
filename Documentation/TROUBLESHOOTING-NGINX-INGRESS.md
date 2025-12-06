# Troubleshooting NGINX Ingress Controller in KIND

## Issue Summary

When deploying the Embassy Appointment System to a KIND (Kubernetes in Docker) cluster, the application was inaccessible via `http://appointments.local` in the browser, returning an `ERR_EMPTY_RESPONSE` error.

**Symptoms**:
- Browser showed: "This page isn't working right now - ERR_EMPTY_RESPONSE"
- `curl http://appointments.local` returned: "Empty reply from server"
- Application pods were running and healthy
- Ingress resource was created correctly
- NGINX Ingress Controller pods were running

---

## Root Cause

The NGINX Ingress Controller pod was scheduled on a **worker node** (`embassy-appointments-worker2`) instead of the **control-plane node**. 

### Why This Matters in KIND

KIND clusters use Docker containers as Kubernetes nodes. The port mappings that allow traffic from your host machine (localhost:80) to reach the cluster are configured **only on the control-plane node** in the `kind-config.yaml`:

```yaml
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
```

The NGINX Ingress Controller uses `hostPort: 80` and `hostPort: 443` in its pod specification, which means:
- The pod binds directly to ports 80 and 443 on the **node where it's running**
- If the pod runs on a worker node without port mappings, traffic from `localhost:80` cannot reach it
- Only the control-plane node has the Docker port mapping `0.0.0.0:80->80/tcp`

### The Flow (Broken State)

```
Browser: http://appointments.local
         ↓
Host Machine: localhost:80
         ↓
Docker Port Mapping: 0.0.0.0:80 → control-plane:80
         ↓
Control-plane Node: (no ingress controller pod here!)
         ❌ Traffic stops - nowhere to route
         
NGINX Ingress Controller Pod is on worker2 (no port mapping)
         ❌ Cannot receive external traffic
```

---

## Troubleshooting Steps

### Step 1: Verify Application Health

```powershell
# Check if pods are running
kubectl get pods -n embassy-appointments
```

**Result**: ✅ Pods were running (1/1 Ready)

```powershell
# Check application logs
kubectl logs -n embassy-appointments -l app.kubernetes.io/name=embassy-appointments --tail=20
```

**Result**: ✅ Application was healthy, responding to health probes

---

### Step 2: Check Ingress Resource

```powershell
# Verify ingress exists
kubectl get ingress -n embassy-appointments
```

**Result**: ✅ Ingress resource existed with correct host and address

```
NAME                                CLASS   HOSTS                ADDRESS     PORTS   AGE
appointments-embassy-appointments   nginx   appointments.local   localhost   80      22m
```

---

### Step 3: Check NGINX Ingress Controller Service

```powershell
# Check ingress controller service
kubectl get svc -n ingress-nginx
```

**Result**: 
```
NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)
ingress-nginx-controller             LoadBalancer   10.103.249.16   <pending>     80:31187/TCP,443:30509/TCP
```

The service showed `<pending>` for `EXTERNAL-IP`, which is normal for KIND. The NodePorts (31187, 30509) were assigned but not accessible because the pod wasn't on the right node.

---

### Step 4: Check NGINX Ingress Controller Logs

```powershell
# View ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=30
```

**Result**: Found the critical error:

```
W1206 06:08:18.676082 11 controller.go:1232] Service "embassy-appointments/appointments-embassy-appointments" 
does not have any active Endpoint.
```

This warning appeared repeatedly, but endpoints **did exist**:

```powershell
kubectl get endpoints -n embassy-appointments
```

```
NAME                                ENDPOINTS          AGE
appointments-embassy-appointments   10.244.1.21:8080   24m
```

This indicated the ingress controller wasn't receiving traffic to route.

---

### Step 5: Verify Docker Port Mappings

```powershell
# Check KIND container port mappings
docker ps --format "table {{.Names}}\t{{.Ports}}" | Select-String "embassy"
```

**Result**:
```
embassy-appointments-worker
embassy-appointments-worker2
embassy-appointments-control-plane   0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp, 0.0.0.0:30080->30080/tcp
```

✅ Port mappings were correct on control-plane node

---

### Step 6: Check Where Ingress Controller Pod is Running (THE KEY DISCOVERY)

```powershell
# Check which node the ingress controller is on
kubectl get pods -n ingress-nginx -o wide
```

**Result**: 🔴 **FOUND THE PROBLEM!**

```
NAME                                        READY   STATUS    RESTARTS   AGE   NODE
ingress-nginx-controller-78f5b6c96c-w87rk   1/1     Running   0          58m   embassy-appointments-worker2
```

The pod was running on `worker2`, not the `control-plane` node!

---

### Step 7: Verify the Control-Plane Node Has the Required Label

```powershell
# Check if control-plane has the ingress-ready label
kubectl get nodes --show-labels | Select-String "ingress-ready"
```

**Result**: The control-plane node has the label `ingress-ready=true`, which is set automatically by KIND.

---

## The Fix

### Solution: Force Ingress Controller to Run on Control-Plane Node

The NGINX Ingress Controller deployment needs a `nodeSelector` to ensure it runs only on nodes with the `ingress-ready=true` label (which is only the control-plane node in KIND).

#### Step 1: Delete the Existing Pod

```powershell
kubectl delete pod -n ingress-nginx -l app.kubernetes.io/component=controller
```

This forces Kubernetes to create a new pod.

#### Step 2: Patch the Deployment with NodeSelector

```powershell
$patch = @'
{
  "spec": {
    "template": {
      "spec": {
        "nodeSelector": {
          "ingress-ready": "true"
        }
      }
    }
  }
}
'@

kubectl patch deployment -n ingress-nginx ingress-nginx-controller -p $patch --type=strategic
```

**Alternative (single-line JSON patch)**:
```powershell
kubectl patch deployment -n ingress-nginx ingress-nginx-controller --type=json `
  -p '[{"op":"add","path":"/spec/template/spec/nodeSelector","value":{"ingress-ready":"true"}}]'
```

#### Step 3: Wait for New Pod to Start

```powershell
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=controller -n ingress-nginx --timeout=120s
```

#### Step 4: Verify the Pod is on Control-Plane

```powershell
kubectl get pods -n ingress-nginx -o wide
```

**Result**: ✅ **FIXED!**

```
NAME                                        READY   STATUS    RESTARTS   AGE   NODE
ingress-nginx-controller-6577698b54-5qhdp   1/1     Running   0          30s   embassy-appointments-control-plane
```

---

## Verification

### Test with curl

```powershell
curl http://appointments.local --max-time 5 -I
```

**Result**: ✅ **SUCCESS!**

```
HTTP/1.1 200 OK
Date: Sat, 06 Dec 2025 06:45:29 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 11559
Connection: keep-alive
```

### Test in Browser

Navigate to `http://appointments.local`

**Result**: ✅ Application loads successfully!

---

## The Flow (Fixed State)

```
Browser: http://appointments.local
         ↓
Host Machine: localhost:80
         ↓
Docker Port Mapping: 0.0.0.0:80 → control-plane:80
         ↓
Control-plane Node Port 80
         ↓
NGINX Ingress Controller Pod (hostPort: 80)
         ✅ Pod running on control-plane with nodeSelector
         ↓
Reads Ingress Resource
         ↓
Routes to Service: appointments-embassy-appointments
         ↓
Service Routes to Pod: 10.244.1.21:8080
         ↓
Application Responds
```

---

## Prevention: Update Installation Steps

To prevent this issue in the future, the NGINX Ingress Controller installation should include the nodeSelector patch immediately after deployment:

```powershell
# Install NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Wait for deployment to be created
Start-Sleep -Seconds 5

# Patch to ensure it runs on control-plane
kubectl patch deployment -n ingress-nginx ingress-nginx-controller --type=json `
  -p '[{"op":"add","path":"/spec/template/spec/nodeSelector","value":{"ingress-ready":"true"}}]'

# Wait for the pod to be ready
kubectl wait --namespace ingress-nginx `
  --for=condition=ready pod `
  --selector=app.kubernetes.io/component=controller `
  --timeout=300s
```

This has been updated in the [09-KIND-SETUP-WALKTHROUGH.md](09-KIND-SETUP-WALKTHROUGH.md) documentation.

---

## Why the Official Manifest Doesn't Include This

The official KIND-specific NGINX Ingress manifest **does** include the nodeSelector, but it's possible that:

1. **Timing Issue**: If the deployment is created and pods start before tolerations/node selectors are fully processed
2. **Manifest Version**: Different versions of the manifest may have different configurations
3. **Race Condition**: In some cases, pods may be scheduled before the nodeSelector is applied

The patch we applied ensures the deployment spec is explicitly updated with the nodeSelector.

---

## Key Learnings

### 1. KIND Port Mappings are Node-Specific
- Port mappings in `kind-config.yaml` apply **only to the specified node**
- `extraPortMappings` on control-plane don't automatically apply to workers

### 2. hostPort vs NodePort
- **hostPort**: Binds directly to the node's network interface (requires specific node)
- **NodePort**: Exposes on all nodes (but still needs port mappings in KIND)

### 3. NodeSelectors are Critical for KIND
- Use `nodeSelector` to ensure pods requiring host ports run on correct nodes
- KIND sets `ingress-ready=true` label on nodes with port mappings

### 4. Troubleshooting Process
1. Start with application (pods, logs)
2. Check networking layer (services, endpoints)
3. Check ingress resources
4. Check ingress controller
5. **Check pod placement** (which node is it on?)
6. Verify infrastructure (Docker port mappings)

### 5. The Importance of Wide Output
```powershell
kubectl get pods -o wide
```
Shows the **NODE** column, which is critical for diagnosing placement issues.

---

## Related Issues

This issue is specific to KIND but similar problems can occur in other environments:

- **On-premises clusters**: If certain nodes have specific network configurations
- **Cloud providers**: If using specific instance types with local storage or network interfaces
- **Hybrid clusters**: Mixing nodes with different capabilities

The solution is always the same: Use **nodeSelectors**, **node affinity**, or **taints/tolerations** to ensure pods run on nodes with the required capabilities.

---

## Additional Resources

- [KIND Ingress Documentation](https://kind.sigs.k8s.io/docs/user/ingress/)
- [NGINX Ingress Controller Documentation](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes NodeSelector](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#nodeselector)
- [KIND Configuration](https://kind.sigs.k8s.io/docs/user/configuration/)

---

**Document Version**: 1.0  
**Last Updated**: December 5, 2025  
**Author**: DevOps Team
