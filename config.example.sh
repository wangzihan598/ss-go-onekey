#!/usr/bin/env bash
#===============================================================================
# 配置示例 —— 仅含占位符，切勿把真实密码提交到 Git 仓库
#
# 用法：
#   cp config.example.sh config.local.sh
#   编辑 config.local.sh 填入真实值
#   source ./config.local.sh
#   bash ./install.sh
#
# config.local.sh 已在 .gitignore 中，不会被提交。
# 更推荐的方式：不落盘密码，直接运行时输入或在命令中通过 SS_PASSWORD 传入。
#===============================================================================

# --- 必填：连接密码 ---
# 8-64 位，不能包含空格或制表符。真实值请在运行时填写，不要提交。
export SS_PASSWORD='CHANGE_ME_DO_NOT_COMMIT'

# --- 可选：端口（默认 443，范围 1-65535）---
export SS_PORT='443'

# --- 可选：加密方式编号 1-12（默认 12 = chacha20-ietf-poly1305）---
# 1 aes-128-cfb  2 aes-128-ctr  3 aes-192-cfb  4 aes-192-ctr
# 5 aes-256-cfb  6 aes-256-ctr  7 chacha20-ietf  8 xchacha20
# 9 aes-128-gcm  10 aes-192-gcm  11 aes-256-gcm  12 chacha20-ietf-poly1305
export SS_CIPHER='12'

# --- 可选：详细日志模式 Y/N（默认 N）---
export SS_VERBOSE='N'

# --- 可选：上游 ss-go.sh 地址（默认官方仓库）---
# export SS_SCRIPT_URL='https://raw.githubusercontent.com/ToyoDAdoubiBackup/doubi/master/ss-go.sh'

# --- 可选：工作目录与日志路径 ---
# export SS_WORKDIR='/root/ss-go-onekey'
# export SS_LOG_FILE='/root/ss-go-onekey/install.log'

# --- 可选：超时设置（秒）---
# export SS_PROMPT_TIMEOUT='30'    # 等待每个交互提示
# export SS_INSTALL_TIMEOUT='900'  # 等待整个安装过程结束
