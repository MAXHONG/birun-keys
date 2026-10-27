# birun-keys

币润行情节点部署**公钥**列表（只放公钥，绝不放私钥）。

三台节点上的 `/usr/local/sbin/birun-key-sync`（由 birun 仓库 `infra/ssh/install-key-sync.sh` 安装）每 5 分钟拉取 `authorized_keys`，
写入 `ubuntu` 用户 authorized_keys 的托管区块。只接受 `ssh-ed25519 <key> birun-deploy-<名字>` 格式，最多 10 条。

- 新增密钥：追加一行并提交，5 分钟内生效
- 吊销密钥：删除该行并提交，5 分钟内生效
