#!/bin/bash

shopt -s extglob

rm -rf target/linux/generic target/linux/qualcommbe package/kernel package/firmware package/boot

git_clone_path main https://github.com/openwrt/openwrt package/kernel

rm -rf package/kernel/mac80211
git_clone_path master https://github.com/coolsnowwolf/lede  target/linux/generic target/linux/qualcommbe package/boot package/firmware package/kernel/mac80211 package/kernel/rtl837x

wget -N https://github.com/coolsnowwolf/lede/raw/refs/heads/master/include/kernel-6.18 -P target/linux/generic/

rm -rf package/feeds/kiddin9/{quectel_QMI_WWAN,simcom_QMI_WWAN,fibocom_QMI_WWAN,quectel_MHI,rkp-ipid,fast-classifier} package/feeds/packages/{v4l2loopback,libpfring,xtables-addons}

# ---- backports 7.2 只兼容 6.19+：struct sockaddr_unsized 在 6.18 不存在，
# ath12k/qmi.c 调用 backport_kernel_connect 会报 incompatible pointer type
# （run 43191716753/43217772771）→ 在 backports 源码里补一个兼容定义
# 注意：mac80211 的 Build/Patch 只加载 patches-*/{build,subsys,ath,ath12k,...}
# 子目录里的补丁，放在 patches-qualcommbe/ 根目录的会被静默忽略（上一轮即因此无效）
mkdir -p package/kernel/mac80211/patches-qualcommbe/build
rm -f package/kernel/mac80211/patches-qualcommbe/999-backport-sockaddr-unsized.patch
cat > package/kernel/mac80211/patches-qualcommbe/build/999-backport-sockaddr-unsized.patch <<'PATCH'
--- a/backport-include/linux/net.h
+++ b/backport-include/linux/net.h
@@ -7,9 +7,17 @@
 
 #if LINUX_VERSION_IS_LESS(6,19,0)
 /*
- * The in-kernel socket API takes struct sockaddr_unsized since 6.19.
- * Older kernels still expect struct sockaddr here.
+ * struct sockaddr_unsized was only introduced in 6.19; provide a compatible
+ * definition for older kernels so that the ath12k casts and this wrapper
+ * refer to the same type (backports 7.2 otherwise fails to compile on 6.18
+ * with "passing argument 2 of 'backport_kernel_connect' from incompatible
+ * pointer type").
  */
+struct sockaddr_unsized {
+	unsigned short sa_family;
+	char sa_data[];
+};
+
 static inline int backport_kernel_connect(struct socket *sock,
 					  struct sockaddr_unsized *addr,
 					  int addrlen, int flags)
PATCH
