# Kubernetes Cluster Lab —— 三节点集群 + Harbor 私有镜像仓库 + Ingress-Nginx

本仓库记录在 Ubuntu 环境下搭建 Kubernetes 三节点集群（1 Master + 2 Worker），在集群外部部署 Harbor 私有镜像仓库并将镜像推送到 Harbor，再在集群中部署应用并通过 ingress-nginx 暴露服务的完整实验步骤与常见问题排查。

---

## 目录
- 1. 项目简介与架构
- 2. 环境信息
- 3. 前置准备
- 4. 在单独主机部署 Harbor（私有镜像仓库）
- 5. Kubernetes 三节点集群搭建（kubeadm + containerd）
- 6. 网络插件：Calico
- 7. 在集群中使用 Harbor 镜像（含认证）
- 8. 安装 ingress-nginx（Helm）
- 9. 测试应用：Deployment / Service / Ingress
- 10. 常见问题与排障
- 11. 参考文档

---

## 1. 项目简介与架构

目标：
- 在实验环境中部署 Harbor 作为私有镜像仓库；
- 使用 kubeadm 在 1 台 Master 和 2 台 Worker 上部署 Kubernetes 集群；
- 使用 Calico 提供网络互通；
- 用 Helm 安装 ingress-nginx，暴露集群内服务；
- 将镜像推到 Harbor，并在 Kubernetes 中拉取运行。

架构示意：

                 Docker Client
                      |
                      v
               +---------------+
               |    Harbor     |
               | 192.168.76.10 |
               +---------------+
                      |
                Docker Registry
                      |
                      v
              Kubernetes Cluster
        +-------------+-------------+
        |             |             |
     k8s-master    k8s-node1     k8s-node2

---

## 2. 环境信息（实验示例）

Harbor 服务器
- OS: Ubuntu 24.04
- IP: 192.168.76.10
- Docker: 29.7.1
- Docker Compose: v5.4.0

Kubernetes 节点
- k8s-master: 192.168.76.4 (Control Plane)
- k8s-node1: 192.168.76.9 (Worker)
- k8s-node2: 192.168.76.19 (Worker)

Kubernetes 版本：
```
v1.30.14
```
容器运行时：
```
containerd 2.2.1
```
网络插件：Calico

---

## 3. 前置准备（各节点通用）
- 关闭 swap：
```bash
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab
```
- 设置主机名（按节点分别设置）：
```bash
hostnamectl set-hostname k8s-master
hostnamectl set-hostname k8s-node1
hostnamectl set-hostname k8s-node2
```
- /etc/hosts 添加内网解析：
```
192.168.76.4  k8s-master
192.168.76.9  k8s-node1
192.168.76.19 k8s-node2
```
- 关闭或按需配置防火墙（实验环境可关闭 ufw）：
```bash
systemctl disable --now ufw
```

---

## 4. 在单独主机部署 Harbor（私有镜像仓库）

1. 进入安装目录并下载离线安装包（示例）：
```bash
cd /opt
wget https://github.com/goharbor/harbor/releases/download/v2.x.x/harbor-offline-installer.tar.gz
tar -zxvf harbor-offline-installer.tar.gz
cd harbor
```

2. 复制并编辑配置：
```bash
cp harbor.yml.tmpl harbor.yml
# 编辑 harbor.yml:
# hostname: 192.168.76.10
# 如果使用 HTTP（实验环境），取消 https 配置或注释证书相关配置
# 设置管理员密码
# harbor_admin_password: Harbor12345
```

3. 安装 Harbor：
```bash
./install.sh
```
安装后用 `docker ps` 查看相关容器：
```
harbor-core
harbor-db
harbor-registry
harbor-nginx
harbor-portal
```

4. Docker（在需要向 Harbor 推镜像的机器上）配置 HTTP 非安全仓库（实验环境）：
编辑 /etc/docker/daemon.json：
```json
{
  "insecure-registries": [
    "192.168.76.10"
  ]
}
```
重启 Docker：
```bash
systemctl restart docker
```
验证：
```bash
docker info | grep -A5 "Insecure Registries"
```

注意（Kubernetes 节点使用 containerd 时）：若 Kubernetes 节点 Pull 镜像需访问 HTTP Harbor，应在每个 containerd 节点配置不安全仓库（示例）：

编辑 /etc/containerd/config.toml（或使用 `containerd config default > /etc/containerd/config.toml` 生成后修改），添加（示例）：
```toml
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."192.168.76.10"]
  endpoint = ["http://192.168.76.10:80"]
```
然后重启 containerd：
```bash
systemctl restart containerd
```

5. 登录 Harbor（在推镜像的主机上）：
```bash
docker login 192.168.76.10
# Username: admin
# Password: <harbor_admin_password>
# 成功应显示: Login Succeeded
```

6. 在 Harbor 创建项目（例如 web 项目）：
在 Web UI: http://192.168.76.10 → 创建项目 k8s-demo

7. 推送测试镜像：
```bash
docker pull nginx
docker tag nginx 192.168.76.10/k8s-demo/nginx:v1
docker push 192.168.76.10/k8s-demo/nginx:v1
```

---

## 5. Kubernetes 三节点集群搭建（kubeadm + containerd）

1. 在所有节点安装 containerd：
```bash
apt update
apt install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# 修改 config.toml，确保 SystemdCgroup = true（在相应位置设置）
# 如需配置 Harbor 非安全 registry，也在此处添加 mirror 配置（参见上文）
systemctl restart containerd
systemctl enable containerd
```

2. 在所有节点安装 Kubernetes 组件（kubeadm、kubelet、kubectl）并锁版本：
```bash
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
```

3. 初始化 Master（在 k8s-master 上）：
```bash
kubeadm init \
  --apiserver-advertise-address=192.168.76.4 \
  --pod-network-cidr=192.168.0.0/16
```
配置 kubectl（在 master 的用户下）：
```bash
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```
验证节点状态：
```bash
kubectl get nodes
```

4. Worker 加入集群（在每个 Worker 上执行 kubeadm join 命令，使用 init 输出的 token 与 hash）：
```bash
kubeadm join 192.168.76.4:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```
Master查看加入结果：
```bash
kubectl get nodes
```

---

## 6. 安装 Calico（网络插件）
在 Master 上：
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/calico.yaml
```
查看 kube-system Pod：
```bash
kubectl get pods -n kube-system
# 关键信息: calico-node, coredns, kube-proxy 等均 Running
```

---

## 7. 在集群中使用 Harbor 镜像（含认证）

- 如果 Harbor 项目为公开（不需要身份），可直接在 Deployment 中使用镜像地址：
```yaml
image: 192.168.76.10/k8s-demo/nginx:v1
```

- 若 Harbor 需要认证（常见），需要创建 imagePullSecret：
```bash
kubectl create secret docker-registry regcred \
  --docker-server=192.168.76.10 \
  --docker-username=admin \
  --docker-password=Harbor12345 \
  --docker-email=you@example.com
```
在 Pod/Deployment 中引用：
```yaml
spec:
  imagePullSecrets:
  - name: regcred
```

---

## 8. 安装 ingress-nginx（使用 Helm）

1. 添加仓库并更新：
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```
2. 创建 namespace 并安装：
```bash
kubectl create namespace ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --version 4.11.3
```
3. 验证：
```bash
kubectl get pods -n ingress-nginx
helm list -n ingress-nginx
```

测试（在无外部 LB 的 VMware NAT 环境）可使用 ingress-nginx 的 NodePort 暴露端口，例如查看 Service 输出的 NodePort 并通过 Host 头访问：
```bash
kubectl get svc -n ingress-nginx
# 假设 80:30936/TCP，则：
curl -H "Host: nginx.test.com" http://192.168.76.19:30936
```

---

## 9. 测试应用：Deployment / Service / Ingress（示例）

1. Deployment（nginx-demo）：
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-demo
  template:
    metadata:
      labels:
        app: nginx-demo
    spec:
      containers:
      - name: nginx
        image: 192.168.76.10/k8s-demo/nginx:v1
        ports:
        - containerPort: 80
```
部署：
```bash
kubectl apply -f deployment.yaml
```

2. Service（ClusterIP）：
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-demo-service
spec:
  selector:
    app: nginx-demo
  ports:
  - port: 80
    targetPort: 80
```
部署：
```bash
kubectl apply -f service.yaml
kubectl get endpoints nginx-demo-service
```

3. Ingress（通过 ingress-nginx 暴露）：
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-demo-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: nginx.test.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-demo-service
            port:
              number: 80
```
部署并测试（结合上文的 NodePort 访问方式）：
```bash
kubectl apply -f ingress.yaml
kubectl get ingress
# 在客户端:
curl -H "Host: nginx.test.com" http://<ingress-node-ip>:<ingress-node-port>
```

---

## 10. 常见问题与排障

问题：docker login 报 HTTPS 连接被拒绝（connection refused:443）
- 原因：Docker 默认使用 HTTPS，而 Harbor 在实验中使用 HTTP。
- 解决：在 Docker 客户端主机 /etc/docker/daemon.json 中加入 harbor 为 insecure registry（见第4节），并重启 Docker。

问题：旧版 docker-compose 安装时报 No module named distutils
- 原因：Ubuntu 24.04 删除了 distutils，旧版 docker-compose (1.x) 依赖 distutils。
- 解决：使用 Docker Compose V2（`docker compose`）或安装相应的 python-distutils 包（非推荐，建议使用 Compose V2）。

问题：Ingress 访问返回 504 Gateway Time-out
- 原因：防火墙或 iptables 规则阻断了节点间 Pod 通信，Ingress 节点无法访问后端 Pod。
- 解决：确认集群节点防火墙已关闭或放行必要端口，清空不必要的 iptables 规则；确认 Calico 或 CNI 配置正确。

问题：ingress-nginx 创建失败，报 failed calling webhook validate.nginx.ingress.kubernetes.io EOF
- 原因：ingress-nginx 的 admission webhook 未初始化完成或证书问题。
- 解决：等待 webhook 启动；如反复失败，可 helm uninstall 后重装 ingress-nginx，并检查 webhook Pod 日志。

问题：Kubernetes 节点拉取 Harbor HTTP 镜像失败（containerd）
- 原因：containerd 未配置访问非安全 registry。
- 解决：在各节点的 /etc/containerd/config.toml 中添加 registry mirror 配置并重启 containerd（详见第4节 containerd 配置）。

---

## 11. 参考文档
- Harbor 官方仓库与文档（离线安装包与 harbor.yml 配置）
- Kubernetes 官方文档（kubeadm、kubelet、kubectl）
- Calico 官方安装清单
- ingress-nginx Helm chart

---

如果你希望，我可以：
- 把这个 README.md 直接提交到仓库（创建/更新文件），或
- 把示例 YAML文件拆分放到 repo 的 `manifests/` 目录并创建一个包含部署命令的脚本（例如 `deploy.sh`）。
