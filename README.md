#  Kubeadm Setup Prerequisites

Following are the prerequisites for Kubeadm Kubernetes cluster setup.

1.Minimum two Ubuntu x22.04 nodes [One master and one worker node]. You can have more worker nodes as per your requirement.

2.The master node should have a minimum of 2 vCPU and 2GB RAM.

3.For the worker nodes, a minimum of 1vCPU and 2 GB RAM is needed but the workload is deployed in the worker nodes so its better to have higher configuration than the master node.

4.10.X.X.X/X network range with static IPs for master and worker nodes. We will be using the 192.x.x.x series as the pod network range that will be used by the Calico network plugin. Make sure the Node IP range and pod IP range don’t overlap


# Kubeadm kubernetes cluster port requirements
If You are setting up the kubernetes cluster in a cloud platform then follow this firewall table

Control-plane node(s)

| Protocol | Direction | Port Range  | Purpose                      | Used By                |
|----------|-----------|-------------|------------------------------|------------------------|
| TCP      | Inbound   | 6443*       | Kubernetes API server        | All                    |
| TCP      | Inbound   | 2379-2380   | etcd server client API       | kube-apiserver, etcd   |
| TCP      | Inbound   | 10250       | Kubelet API                  | Self, Control plane    |
| TCP      | Inbound   | 10251       | kube-scheduler               | Self                   |
| TCP      | Inbound   | 10252       | kube-controller-manager      | Self                   |

### Worker node(s)

| Protocol | Direction | Port Range     | Purpose             | Used By              |
|----------|-----------|----------------|---------------------|----------------------|
| TCP      | Inbound   | 10250          | Kubelet API         | Self, Control plane  |
| TCP      | Inbound   | 30000-32767    | NodePort Services** | All                  |

If you are setting up in on prem servers then you  can disable the complete firewall (not recommended ) or do this 
   
    sudo ufw disable

or for master node:

    sudo ufw allow 6443/tcp
    sudo ufw allow 2379:2380/tcp
    sudo ufw allow 10250/tcp
    sudo ufw allow 10251/tcp
    sudo ufw allow 10252/tcp

for worker node:

    sudo ufw allow 10250/tcp
    sudo ufw allow 30000:32767/tcp

# Following are the high-level steps involved in setting up a kubeadm-based Kubernetes cluster.

1. Install container runtime on all nodes- We will be using cri-o.

2. Install Kubeadm, Kubelet, and kubectl on all the nodes.

3. Initiate Kubeadm control plane configuration on the master node.

4. Save the node join command with the token.

5. Install the Calico network plugin (operator).

6. Join the worker node to the master node (control plane) using the join command.

7. Validate all cluster components and nodes.

8. Install Kubernetes Metrics Server

9. Deploy a sample app and validate the app




# Step 1: Enable iptables Bridged Traffic on all the Nodes

Execute the following commands on all the nodes for IPtables to see bridged traffic. Here we are tweaking some kernel parameters and setting them using sysctl.

    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
    overlay
    br_netfilter
    EOF

    sudo modprobe overlay
    sudo modprobe br_netfilter

sysctl params required by setup, params persist across reboots

    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables  = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward                 = 1
    EOF

Apply sysctl params without reboot

    sudo sysctl --system



# Step 2: Disable swap on all the Nodes

For kubeadm to work properly, you need to disable swap on all the nodes using the following command.

    sudo swapoff -a
    (crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true

For kubeadm to work properly, you need to disable apparmor on all the nodes using the following command.
    sudo service apparmor status
    sudo service apparmor stop
    
# Step 3: Install CRI-O Runtime On All The Nodes

We will be using CRI-O instead of Docker for this setup as Kubernetes deprecated Docker engine

Execute the following commands on all the nodes to install required dependencies and the latest version of CRIO.


      sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list <<< "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_22.04/ /"
      sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:1.28.list <<< "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/1.28/xUbuntu_22.04/ /"

      curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:1.28/xUbuntu_22.04/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -
      curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_22.04/Release.key | sudo apt-key --keyring /etc/apt/trusted.gpg.d/libcontainers.gpg add -

      sudo apt-get update
      sudo apt-get install cri-o cri-o-runc -y

      sudo systemctl daemon-reload
      sudo systemctl enable crio --now


# Step 4: Install Kubeadm & Kubelet & Kubectl on all Nodes


Download the GPG key for the Kubernetes APT repository on all the nodes.

      sudo apt-get install -y apt-transport-https ca-certificates curl gpg

      sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1-28-apt-keyring.gpg <<< "$(curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key)"
      echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-1-28-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes-1.28.list

      sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-1-29-apt-keyring.gpg <<< "$(curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key)"
      echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-1-29-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes-1.29.list


Update apt repo
      sudo apt-get update -y

 You can use the following commands to find the latest versions. Install the first version in 1.29 so that you can practice cluster upgrade task.

      apt-cache madison kubeadm | tac     
Specify the version as shown below. Here I am using 1.29.0-1.1(It is not suitable to use the latest version since it will be having bugs)
So we will go with the 1.29.0-1.1 version

      sudo apt-get install -y kubelet="1.29.0-1.1" kubectl="1.29.0-1.1" kubeadm="1.29.0-1.1"

Update apt repo, again:

      sudo apt-get update -y

Add hold to the packages to prevent upgrades.

      sudo apt-mark hold kubelet kubeadm kubectl

Now we have all the required utilities and tools for configuring Kubernetes components using kubeadm.

Add the node IP to KUBELET_EXTRA_ARGS. For that install jq:

      sudo apt-get install -y jq
      sudo sh -c 'local_ip="$(ip --json addr show eth0 | jq -r .[0].addr_info[] | grep "\"family\":\"inet\"" | cut -d "\"" -f 4)"; echo "KUBELET_EXTRA_ARGS=--node-ip=$local_ip" > /etc/default/kubelet'


# Step 5: Initialize Kubeadm On Master Node To Setup Control Plane


Set the following environment variables. Replace 10.1.0.220 with the IP of your master node.

    IPADDR="$(ip addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1)"
    NODENAME=$(hostname -s)
    POD_CIDR="192.168.0.0/16"

For a Private IP address-based setup use the following init command.

    sudo kubeadm init --apiserver-advertise-address=$IPADDR  --apiserver-cert-extra-sans=$IPADDR  --pod-network-cidr=$POD_CIDR --node-name=$NODENAME

Use the following commands from the output to create the kubeconfig in master so that you can use kubectl to interact with cluster API.

    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

Now, verify the kubeconfig by executing the following kubectl command to list all the pods in the kube-system namespace.

    kubectl get po -n kube-system

You can get the cluster info using the following command.

    kubectl cluster-info 

# Step 6: Join Worker Nodes To Kubernetes Master Node

We have set up cri-o, kubelet, and kubeadm utilities on the worker nodes as well.

Now, let’s join the worker node to the master node using the Kubeadm join command you have got in the output while setting up the master node.

If you missed copying the join command, execute the following command in the master node to recreate the token with the join command.

    kubeadm token create --print-join-command

Here is what the command looks like. Use sudo if you running as a normal user. This command performs the TLS bootstrapping for the nodes.

    sudo kubeadm join 10.1.0.220:6443 --token j4eice.4654g3sd1g54fsda \
        --discovery-token-ca-cert-hash sha256:356541dg85sdfg4sf85g4g1sdf65g4sdf5g4321dfggdfg5g3216543516dfdfgdf


Now execute the kubectl command from the master node to check if the node is added to the master.

    kubectl get nodes

Example output,

    ubuntu@prashantkubernetesmaster01:~$ kubectl get nodes
    NAME                         STATUS   ROLES           AGE   VERSION
    prashantkubernetesmaster01   Ready    control-plane   14m   v1.29.0
    prashantkubernetesworker01   Ready    <none>          11m   v1.29.0


In the above command, the ROLE is <none> for the worker nodes. You can add a label to the worker node using the following command. Replace prashantkubernetesworker01 with the hostname of the worker node you want to label.

    kubectl label node prashantkubernetesworker01  node-role.kubernetes.io/worker=worker

You can further add more nodes with the same join command.


# Step 7: Install Calico Network Plugin for Pod Networking

Execute the following commands to install the Calico network plugin operator on the cluster.

    kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

After a couple of minutes, if you check the pods in kube-system namespace, you will see calico pods and running CoreDNS pods.

    kubectl get po -n kube-system

# Step 8: Setup Kubernetes Metrics Server

Kubeadm doesn’t install metrics server component during its initialization. We have to install it separately.

To verify this, if you run the top command, you will see the Metrics API not available error.

    ubuntu@prashantkubernetesmaster01:~$ kubectl top nodes
    error: Metrics API not available

To install the metrics server, execute the following metric server manifest file. It deploys metrics server version v0.6.2


    kubectl apply -f https://github.com/paccciii/kubernetes_metrics/blob/main/metrics-server.yaml


Once the metrics server objects are deployed, it takes a minute for you to see the node and pod metrics using the top command.

    kubectl top nodes

It will show something like this,

    ubuntu@prashantkubernetesmaster01:~$ kubectl top nodes
    NAME                         CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
    prashantkubernetesmaster01   985m         24%    2410Mi          30%
    prashantkubernetesworker01   351m         8%     2029Mi          25%


# Step 9: Deploy A Sample Nginx Application

Now that we have all the components to make the cluster and applications work, let’s deploy a sample Nginx application and see if we can access it over a NodePort

Create an Nginx deployment. Execute the following directly on the command line. It deploys the pod in the default namespace.

    cat <<EOF | kubectl apply -f -
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: nginx-deployment
    spec:
      selector:
        matchLabels:
          app: nginx
      replicas: 2 
      template:
        metadata:
          labels:
            app: nginx
        spec:
          containers:
          - name: nginx
            image: nginx:latest
            ports:
            - containerPort: 80      
    EOF

Expose the Nginx deployment on a NodePort 32000

    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: Service
    metadata:
      name: nginx-service
    spec:
      selector: 
        app: nginx
      type: NodePort  
      ports:
        - port: 80
          targetPort: 80
          nodePort: 32000
    EOF

Check the pod status using the following command.

    kubectl get pods


