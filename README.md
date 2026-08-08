# Kubernetes Cluster Lab - 企业级集群部署完整实践

🚀 一个完整的 Kubernetes 集群构建和应用部署实验项目，涵盖集群搭建、私有镜像仓库、入口控制器、监控平台和自动化部署。

## 📌 项目概览

本项目记录了在 Ubuntu 环境下构建 **Kubernetes 三节点生产级集群** 的全过程，并集成了企业级工具链：

- **集群部署**: 使用 kubeadm + containerd 搭建高可用 Kubernetes 集群
- **私有仓库**: Harbor 企业级容器镜像仓库
- **入口控制**: Ingress-Nginx 流量管理
- **监控平台**: Prometheus + Grafana 实时监控
- **自动化**: Ansible 和 Helm 自动化部署
- **脚本工具**: 集群管理和维护脚本集合

## 🏗️ 系统架构

```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                    │
│                                                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  k8s-master  │  │  k8s-node1   │  │  k8s-node2   │  │
│  │ 192.168.76.4 │  │ 192.168.76.9 │  │192.168.76.19 │  │
│  │ Control Plane│  │   Worker     │  │   Worker     │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│         ▲                  ▲                  ▲           │
│         └──────────────────┴──────────────────┘           │
│                      Calico CNI                          │
└─────────────────────────────────────────────────────────┘
         ▲                       ▲
         │                       │
    ┌────┴────┐          ┌──────┴──────┐
    │          │          │             │
┌───────┐ ┌────────┐ ┌──────────┐ ┌────────────┐
│Harbor │ │ Jenkins│ │ Prometheus
│192...10│ │Ingress-│ │+ Grafana │
│       │ │ Nginx  │ │Monitoring│
└───────┘ └────────┘ └──────────┘ └────────────┘
```

## 📚 文档结构

### 核心指南
| 文档 | 描述 |
|------|------|
| [README.md](./README.md) | 本项目整体介绍（当前文件） |
| [kubectl集群搭建](./kubectl集群搭建) | Kubernetes 集群初始化和配置详解 |
| [常见问题.md](./常见问题.md) | 集群部署和运维常见问题解决方案 |

### 组件部署指南

#### 容器与镜像管理
- **[Harbor](./Harbor)** - 企业级私有容器镜像仓库
  - 镜像上传和管理
  - HTTP/HTTPS 配置
  - 与 Kubernetes 集成

#### 网络与入口
- **[Kubernetes Ingress-Nginx](./Kubernetes%20Ingress-Nginx)** - HTTP(S) 流量管理
  - Helm 安装部署
  - Ingress 规则配置
  - NodePort 访问测试

#### 监控与可观测性
- **[Prometheus + Grafana](./Prometheus%20%2B%20Grafana)** - 实时监控平台
  - kube-prometheus-stack 部署
  - Grafana Dashboard 配置
  - Prometheus 数据源管理

#### 应用交付
- **[helm](./helm)** - Kubernetes 包管理
  - Helm 仓库配置
  - Chart 部署管理
  - 应用升级和回滚

- **[Ansible](./Ansible)** - 基础设施自动化
  - Inventory 主机管理
  - Playbook 编写和执行
  - 节点初始化自动化

- **[jenkins](./jenkins)** - CI/CD 流水线
  - Jenkins 集群部署
  - Pipeline 配置
  - 自动构建和发布

### 自动化脚本
- **[scripts/](./scripts/)** - 集群管理工具集
  - `cluster-init.sh` - 集群初始化
  - `deploy-app.sh` - 应用部署工具
  - `health-check.sh` - 健康检查
  - `backup-etcd.sh` - ETCD 备份恢复

## 🌍 环境信息

### 硬件配置
| 类型 | 配置 |
|------|------|
| 虚拟化平台 | VMware Workstation / vSphere |
| 操作系统 | Ubuntu 24.04 LTS |
| CPU | 4核 (每节点) |
| 内存 | 8GB (每节点) |
| 存储 | 100GB (每节点) |

### 网络拓扑
| 节点 | 角色 | IP 地址 | 用途 |
|------|------|--------|------|
| k8s-master | Control Plane | 192.168.76.4 | 集群管理、API Server、Scheduler |
| k8s-node1 | Worker | 192.168.76.9 | 应用工作负载运行 |
| k8s-node2 | Worker | 192.168.76.19 | 应用工作负载运行 |
| harbor-srv | Registry | 192.168.76.10 | 私有镜像仓库 |

### 软件版本
| 组件 | 版本 |
|------|------|
| Kubernetes | v1.30.14 |
| Container Runtime | containerd 2.2.1 |
| Docker | 29.7.1 |
| Docker Compose | v5.4.0 |
| Helm | 3.x |
| Ansible | 2.x |
| Calico | v3.29.0 |
| Ingress-Nginx | 4.11.3 |

## 🚀 快速开始

### 前置条件
- 三台 Ubuntu 24.04 LTS 虚拟机
- 网络互通且已配置静态 IP
- 至少 4 核 CPU 和 8GB 内存
- root 或 sudo 权限

### 一键部署流程

#### 1️⃣ 准备基础环境
```bash
# 在所有节点执行
# 关闭 swap
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# 配置主机名
hostnamectl set-hostname k8s-master   # 在 Master 节点
hostnamectl set-hostname k8s-node1    # 在 Worker1
hostnamectl set-hostname k8s-node2    # 在 Worker2

# 配置 /etc/hosts
cat >> /etc/hosts <<EOF
192.168.76.4  k8s-master
192.168.76.9  k8s-node1
192.168.76.19 k8s-node2
192.168.76.10 harbor
EOF
```

#### 2️⃣ 安装容器运行时 (containerd)
```bash
# 在所有节点执行
apt update && apt install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# 修改 cgroup 驱动为 systemd
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd
```

#### 3️⃣ 安装 Kubernetes 组件
```bash
# 在所有节点执行
apt update && apt install -y \
  apt-transport-https \
  ca-certificates \
  curl

# 添加 Kubernetes 仓库
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | \
  tee /etc/apt/sources.list.d/kubernetes.list

apt update
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet
```

#### 4️⃣ 初始化 Master 节点
```bash
# 在 Master 节点执行
kubeadm init \
  --apiserver-advertise-address=192.168.76.4 \
  --pod-network-cidr=192.168.0.0/16 \
  --kubernetes-version=v1.30.14

# 配置 kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 查看 join 命令输出，复制供 Worker 使用
kubeadm token create --print-join-command
```

#### 5️⃣ Worker 节点加入集群
```bash
# 在 Worker 节点执行（使用上步的 join 命令）
kubeadm join 192.168.76.4:6443 \
  --token <your-token> \
  --discovery-token-ca-cert-hash sha256:<your-hash>
```

#### 6️⃣ 安装网络插件 (Calico)
```bash
# 在 Master 节点执行
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.0/manifests/calico.yaml

# 等待网络就绪
kubectl get pods -n kube-system | grep calico
kubectl get nodes  # 所有节点应显示 Ready
```

#### 7️⃣ 部署 Harbor 私有仓库
参考 [Harbor 部署指南](./Harbor)

#### 8️⃣ 部署 Ingress-Nginx
参考 [Ingress-Nginx 部署指南](./Kubernetes%20Ingress-Nginx)

#### 9️⃣ 部署监控平台
参考 [Prometheus + Grafana 部署指南](./Prometheus%20%2B%20Grafana)

## 📋 常见操作命令

### 集群验证
```bash
# 查看节点状态
kubectl get nodes -o wide

# 查看集群信息
kubectl cluster-info

# 验证关键组件
kubectl get pods -n kube-system

# 查看 API 服务器版本
kubectl version
```

### 集群管理
```bash
# 创建命名空间
kubectl create namespace production

# 查看 Pod 日志
kubectl logs -f <pod-name> -n <namespace>

# 进入容器 shell
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash

# 查看资源使用情况
kubectl top nodes
kubectl top pods -n <namespace>
```

### 备份和恢复
```bash
# 备份 ETCD
bash scripts/backup-etcd.sh

# 集群健康检查
bash scripts/health-check.sh

# 初始化集群配置
bash scripts/cluster-init.sh
```

## 🔧 使用脚本工具

### 集群初始化脚本
```bash
# 创建生产、测试、监控命名空间
bash scripts/cluster-init.sh
```

### 应用部署脚本
```bash
# 快速部署应用（自动验证命名空间）
bash scripts/deploy-app.sh myapp production v1.0.0
```

### 健康检查脚本
```bash
# 检查集群、节点、Pod、存储等状态
bash scripts/health-check.sh
```

### ETCD 备份脚本
```bash
# 定期备份集群状态（需 sudo）
bash scripts/backup-etcd.sh

# 推荐添加到 cron 定时任务
0 2 * * 0 /path/to/scripts/backup-etcd.sh
```

## 📖 详细文档导航

### 🔹 入门向导
1. [集群搭建步骤](./kubectl集群搭建) - 完整的部署流程
2. [Harbor 使用指南](./Harbor) - 私有镜像仓库配置
3. [Ingress 配置](./Kubernetes%20Ingress-Nginx) - 网络流量管理

### 🔹 高级特性
1. [Prometheus 监控](./Prometheus%20%2B%20Grafana) - 可观测性平台
2. [Helm 包管理](./helm) - 应用模板化部署
3. [Ansible 自动化](./Ansible) - 基础设施即代码
4. [Jenkins CI/CD](./jenkins) - 持续集成和部署

### 🔹 运维指南
1. [常见问题解决](./常见问题.md) - Q&A 问题库
2. [脚本工具说明](./scripts/README.md) - 自动化工具使用

## ⚠️ 常见问题速查表

| 问题 | 解决方案 |
|------|--------|
| 节点 NotReady | 安装网络插件 (Calico) |
| docker login HTTPS 失败 | 配置 insecure-registries |
| Pod 无法拉取 Harbor 镜像 | 在 containerd 配置 registry mirror |
| Ingress 返回 504 | 检查防火墙，关闭不必要的 iptables 规则 |
| Pod CrashLoopBackOff | 检查日志、镜像、资源限制 |
| Grafana 无法访问 | 修改 Service 类型为 NodePort |

更多问题详见 [常见问题.md](./常见问题.md)

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

### 报告问题
- 详细描述问题现象
- 提供相关错误日志
- 说明所用的软件版本

### 改进建议
- 文档优化
- 新脚本工具
- 部署经验分享

## 📚 参考资源

### 官方文档
- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [Kubernetes 中文文档](https://kubernetes.io/zh/)
- [Docker 官方文档](https://docs.docker.com/)
- [Helm 官方文档](https://helm.sh/docs/)

### 社区资源
- [kubeadm 安装指南](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [containerd 官方文档](https://containerd.io/)
- [Calico 网络插件](https://docs.tigera.io/calico/latest/about/)
- [Ingress-Nginx 项目](https://kubernetes.github.io/ingress-nginx/)
- [Harbor 项目](https://goharbor.io/)
- [Prometheus 官方文档](https://prometheus.io/docs/)
- [Grafana 官方文档](https://grafana.com/docs/)

### 学习资源
- [Kubernetes 中文社区](https://www.kubernetes.org.cn/)
- [云原生社区](https://cloudnative.to/)
- [CNCF 官方网站](https://www.cncf.io/)

## 📄 许可证

MIT License - 详见 LICENSE 文件

## 👤 作者

**admin047** - 云原生工程师

## 🎯 项目目标

✅ 学习 Kubernetes 集群搭建原理  
✅ 掌握企业级容器技术栈  
✅ 实践 GitOps 和基础设施即代码  
✅ 建立完整的 DevOps 工程实践  
✅ 分享云原生技术知识  

---

**最后更新**: 2024年8月  
**Kubernetes 版本**: v1.30.14  
**项目状态**: 🟢 活跃维护
