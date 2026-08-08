# Scripts - Kubernetes 实用脚本集

本目录包含用于 Kubernetes 集群管理和维护的实用脚本。

## 📋 脚本列表

### 1. `cluster-init.sh` - 集群初始化
初始化 Kubernetes 集群环境，创建基础命名空间。

**用途:**
- 检查 kubectl 安装
- 验证集群连接
- 创建生产、测试、监控命名空间

**使用方法:**
```bash
bash scripts/cluster-init.sh
```

---

### 2. `deploy-app.sh` - 应用部署
简化应用部署流程，支持多个命名空间。

**用途:**
- 快速部署应用
- 自动验证命名空间
- 监控部署状态

**使用方法:**
```bash
bash scripts/deploy-app.sh <app-name> <namespace> [image-tag]

# 示例
bash scripts/deploy-app.sh myapp production v1.0.0
```

---

### 3. `health-check.sh` - 集群健康检查
检查 Kubernetes 集群和节点的健康状态。

**检查项:**
- ✅ 集群连接状态
- ✅ 节点就绪情况
- ✅ Pod 运行状态
- ✅ 存储类配置

**使用方法:**
```bash
bash scripts/health-check.sh
```

---

### 4. `backup-etcd.sh` - ETCD 备份
备份 Kubernetes ETCD 数据库，用于灾难恢复。

**用途:**
- 定期备份集群数据
- 灾难恢复
- 版本控制

**使用方法:**
```bash
bash scripts/backup-etcd.sh
```

**注意:** 需要 `sudo` 权限

---

## 🚀 快速开始

### 权限设置
所有脚本需要可执行权限：
```bash
chmod +x scripts/*.sh
```

### 首次使用
```bash
# 1. 初始化集群
bash scripts/cluster-init.sh

# 2. 检查集群健康状态
bash scripts/health-check.sh

# 3. 部署应用
bash scripts/deploy-app.sh myapp production
```

---

## 📝 最佳实践

1. **定期备份**: 每周至少备份一次 ETCD
   ```bash
   # 添加到 cron 定时任务
   0 2 * * 0 /path/to/scripts/backup-etcd.sh
   ```

2. **部署前检查**: 始终在部署前运行健康检查
   ```bash
   bash scripts/health-check.sh && bash scripts/deploy-app.sh myapp production
   ```

3. **日志记录**: 将脚本输出重定向到日志文件
   ```bash
   bash scripts/deploy-app.sh myapp production 2>&1 | tee deploy.log
   ```

---

## 🔧 故障排除

### 权限拒绝
```bash
# 解决方法
chmod +x scripts/*.sh
```

### kubectl 命令不found
```bash
# 检查 kubectl 安装
which kubectl

# 添加到 PATH
export PATH=$PATH:/usr/local/bin
```

### ETCD 备份失败
```bash
# 检查证书路径
ls -la /etc/kubernetes/pki/etcd/

# 确保有适当的权限
sudo -l
```

---

## 📚 相关文档

- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [ETCD 备份恢复](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)
- [kubectl 参考](https://kubernetes.io/docs/reference/kubectl/)
