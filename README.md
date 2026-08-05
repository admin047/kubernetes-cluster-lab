# kubernetes-cluster-lab
Kubernetes 三节点集群搭建实验（基于 Ubuntu + containerd + kubeadm + Calico）

本项目用于在实验环境中搭建一个简单的三节点 Kubernetes 集群（1 Master + 2 Worker），便于学习集群组件、Pod 调度、Service 暴露与基础运维操作。README 已结合仓库中原始内容与常见实践进行了整理与补充。

---

## 目录
- 一、实验概览
- 二、节点信息与版本
- 三、先决条件
- 四、系统初始化（所有节点）
- 五、安装 containerd
- 六、安装 Kubernetes 组件（kubeadm / kubelet / kubectl）
- 七、初始化 Master 节点
- 八、Worker 加入集群
- 九、安装 Calico 网络插件
- 十、部署测试应用与验证
- 十一、常见问题排查
- 十二、远程管理示例
- 许可证

---

# 一、实验概览

集群目标：
- 1 x Control Plane（k8s-master）
- 2 x Worker（k8s-node1、k8s-node2）
- 使用 containerd 作为容器运行时
- 使用 kubeadm 部署
- 使用 Calico 作为 CNI（示例使用 v3.29.0）

拓扑图（简化）：

                 kubectl
                    |
                 k8s-master (Control Plane)
                    |
             -----------------
             |               |
          k8s-node1        k8s-node2
           (Worker)         (Worker)

---

# 二、节点信息与版本

| 主机         | IP            | 角色          |
| ------------ | ------------- | ------------- |
| k8s-master   | 192.168.76.4  | Control Plane |
| k8s-node1    | 192.168.76.9  | Worker        |
| k8s-node2    | 192.168.76.19 | Worker        |

操作系统：
```
Ubuntu 24.04 LTS
```

关键版本（实验采用）：
```
Kubernetes: v1.30.14
containerd: 系统包（Ubuntu 提供）
Calico: v3.29.0
```

---

# 三、先决条件

在所有节点上以 root 或具备 sudo 权限的用户执行以下操作，并确保节点之间网络互通（能互相 ping、能访问 6443 端口）：

- 关闭防火墙（实验环境）或按生产环境调整规则（开放 Kubernetes 所需端口）。
- 关闭 Swap（Kubernetes 要求）。
- 配置主机名与 /etc/hosts，使节点能通过主机名互相访问。
- 时间同步（推荐安装并启用 chrony 或 systemd-timesyncd）。

---

# 四、系统初始化（所有节点）

1. 更新与安装基础工具：
```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release vim
```

2. 关闭 Swap（临时）：
```bash
sudo swapoff -a
```
永久禁用 (编辑 /etc/fstab，将 swap 行注释掉)：
```bash
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

3. 设置内核参数（确保网络转发与 iptables 能处理 bridge 流量）：
```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system
```

4. 配置主机名与 hosts（示例）：
```bash
sudo hostnamectl set-hostname k8s-master   # 在 master 上
sudo hostnamectl set-hostname k8s-node1    # 在 node1 上
sudo hostnamectl set-hostname k8s-node2    # 在 node2 上

# 编辑 /etc/hosts（在每台机器都加）
sudo tee -a /etc/hosts <<EOF
192.168.76.4   k8s-master
192.168.76.9   k8s-node1
192.168.76.19  k8s-node2
EOF
```

注意：生产环境请按安全策略开启并配置防火墙规则，而不是全部禁用。

---

# 五、安装 containerd（所有节点）

1. 安装 containerd：
```bash
sudo apt update
sudo apt install -y containerd
```

2. 生成默认配置并启用 systemd cgroup：
```bash
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
# 编辑 /etc/containerd/config.toml，将 SystemdCgroup 设置为 true（一般在 [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options] 下）
# 或使用 sed 替换（谨慎使用，建议手动确认）
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

3. 重启与启用：
```bash
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo systemctl status containerd --no-pager
```

---

# 六、安装 Kubernetes 组件（kubeadm / kubelet / kubectl）

在所有节点上添加 Kubernetes apt 源并安装指定版本（示例为 v1.30.14）：

```bash
# 准备
sudo apt update
sudo apt install -y ca-certificates curl

# 添加官方 GPG key（现代方式）
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

# 添加 apt 源
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

# 更新并安装（带 -00 后缀锁定精确包）
sudo apt update
sudo apt install -y kubelet=1.30.14-00 kubeadm=1.30.14-00 kubectl=1.30.14-00

# 防止自动升级替换版本
sudo apt-mark hold kubelet kubeadm kubectl
```

如果你不需要精确版本，也可以省略具体版本号，但实验中建议固定版本以保证可重复性。

---

# 七、初始化 Master 节点

在 k8s-master 上执行：

```bash
sudo kubeadm init \
  --apiserver-advertise-address=192.168.76.4 \
  --pod-network-cidr=192.168.0.0/16
```

成功后，按照 kubeadm 输出做以下操作以配置 kubectl（以普通用户为例）：
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

检查节点和控制面状态：
```bash
kubectl get nodes
kubectl get pods -n kube-system
```

记录或保存 kubeadm 输出中关于 Worker 加入集群的 `kubeadm join ...` 命令（包含 token 和 discovery-token-ca-cert-hash），也可使用下一节的命令动态生成。

---

# 八、Worker 节点加入集群

在任一 Worker（或同时在两台）上执行 kubeadm join（使用 init 输出的 join 命令）：
```bash
sudo kubeadm join 192.168.76.4:6443 \
  --token <token-from-master> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

如果 token 已过期，在 master 上创建并打印 join 命令：
```bash
sudo kubeadm token create --print-join-command
```

回到 master 上验证：
```bash
kubectl get nodes
```

预期状态：
```
NAME         STATUS   ROLES    AGE    VERSION
k8s-master   Ready    control-plane ...
k8s-node1    Ready    <none>   ...
k8s-node2    Ready    <none>   ...
```

---

# 九、安装 Calico 网络插件（Master）

示例使用 Calico v3.29.0（跟 kubeadm init 使用的 pod-network-cidr 保持一致）：

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/calico.yaml
```

检查 Calico Pod 状态：
```bash
kubectl get pods -n kube-system
kubectl get ds -n kube-system
```

等待 calico-node、coredns 等 POD 进入 Running 状态。

---

# 十、部署测试应用与验证

1. 部署 nginx：
```bash
kubectl create deployment nginx --image=nginx
kubectl get pods -o wide
```

2. 扩容到 3 个副本：
```bash
kubectl scale deployment nginx --replicas=3
kubectl get pods -l app=nginx
```

3. 暴露为 NodePort 服务：
```bash
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get svc
# 访问格式: http://<NodeIP>:<NodePort>
```

常用诊断命令：
```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> [-c <container>] -n <namespace>
```

---

# 十一、常见问题排查

- kubelet 与 containerd 的 cgroup 驱动不匹配：
  - containerd 配置中需启用 SystemdCgroup=true，kubelet 也应使用 systemd cgroup 驱动（默认取决于系统）。
  - 查看 kubelet 日志： sudo journalctl -u kubelet -b

- Pod 一直 Pending：
  - 检查 CNI 是否就绪（kubectl get pods -n kube-system）
  - 检查 Node taints 与 Pod 的调度约束

- 无法 join：
  - 检查 master 的 6443 端口是否可达（nc / telnet）
  - 检查 token 是否过期（在 master 上重新生成 join 命令）

- Calico Pod CrashLoop：
  - 使用 kubectl describe pod 与 kubectl logs 查看具体错误
  - 检查内核参数、iptables、内核模块（bridge-nf-call-iptables）

---

# 十二、远程管理示例

远程关机：
```bash
ssh root@192.168.xx.xx "systemctl poweroff"
```

远程重启：
```bash
ssh root@192.168.xx.xx "reboot"
```

（将上面的 IP 替换为目标节点地址）

---

# 许可证
MIT
