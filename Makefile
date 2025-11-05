# Gitspace Runtime - Makefile
# 统一构建 Docker 和 K8s Gitspace 使用的镜像

# ========================================
# 配置变量
# ========================================

# 镜像仓库
REGISTRY ?= ghcr.io/ysicing
PROJECT := gitspace-runtime

# 版本管理
VERSION ?= latest
GIT_COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE := $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')

# 镜像名称
BASE_IMAGE := $(REGISTRY)/$(PROJECT):base-$(VERSION)
VSCODE_IMAGE := $(REGISTRY)/$(PROJECT):vscode-$(VERSION)
CURSOR_IMAGE := $(REGISTRY)/$(PROJECT):cursor-$(VERSION)
JETBRAINS_IMAGE := $(REGISTRY)/$(PROJECT):jetbrains-$(VERSION)

# 构建参数
DOCKER_BUILD_ARGS := --build-arg BUILD_DATE=$(BUILD_DATE) \
                     --build-arg VCS_REF=$(GIT_COMMIT)

# 多平台支持
PLATFORMS := linux/amd64,linux/arm64
BUILDX_BUILDER := gitspace-builder

.PHONY: help
help: ## 显示帮助信息
	@echo "Gitspace Runtime - 镜像构建工具"
	@echo ""
	@echo "使用方法:"
	@echo "  make <target>"
	@echo ""
	@echo "主要目标:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ========================================
# 构建目标
# ========================================

.PHONY: build-base
build-base: ## 构建基础镜像
	@echo "🔨 构建基础镜像: $(BASE_IMAGE)"
	docker build $(DOCKER_BUILD_ARGS) \
		-t $(BASE_IMAGE) \
		-f base/Dockerfile \
		.
	@echo "✅ 基础镜像构建完成"

.PHONY: build-vscode
build-vscode: build-base ## 构建 VSCode 镜像 (依赖 base)
	@echo "🔨 构建 VSCode 镜像: $(VSCODE_IMAGE)"
	docker build $(DOCKER_BUILD_ARGS) \
		-t $(VSCODE_IMAGE) \
		-f vscode/Dockerfile \
		.
	@echo "✅ VSCode 镜像构建完成"

.PHONY: build-cursor
build-cursor: build-base ## 构建 Cursor 镜像 (依赖 base)
	@echo "🔨 构建 Cursor 镜像: $(CURSOR_IMAGE)"
	@echo "⚠️  Cursor 镜像尚未实现"
	# docker build $(DOCKER_BUILD_ARGS) \
	# 	-t $(CURSOR_IMAGE) \
	# 	-f cursor/Dockerfile \
	# 	.

.PHONY: build-jetbrains
build-jetbrains: build-base ## 构建 JetBrains 镜像 (依赖 base)
	@echo "🔨 构建 JetBrains 镜像: $(JETBRAINS_IMAGE)"
	@echo "⚠️  JetBrains 镜像尚未实现"
	# docker build $(DOCKER_BUILD_ARGS) \
	# 	-t $(JETBRAINS_IMAGE) \
	# 	-f jetbrains/Dockerfile \
	# 	.

.PHONY: build-all
build-all: build-base build-vscode ## 构建所有镜像
	@echo "✅ 所有镜像构建完成"

# ========================================
# 推送目标
# ========================================

.PHONY: push-base
push-base: build-base ## 推送基础镜像
	@echo "📤 推送基础镜像: $(BASE_IMAGE)"
	docker push $(BASE_IMAGE)
	@echo "✅ 基础镜像推送完成"

.PHONY: push-vscode
push-vscode: build-vscode ## 推送 VSCode 镜像
	@echo "📤 推送 VSCode 镜像: $(VSCODE_IMAGE)"
	docker push $(VSCODE_IMAGE)
	@echo "✅ VSCode 镜像推送完成"

.PHONY: push-cursor
push-cursor: build-cursor ## 推送 Cursor 镜像
	@echo "📤 推送 Cursor 镜像: $(CURSOR_IMAGE)"
	docker push $(CURSOR_IMAGE)

.PHONY: push-jetbrains
push-jetbrains: build-jetbrains ## 推送 JetBrains 镜像
	@echo "📤 推送 JetBrains 镜像: $(JETBRAINS_IMAGE)"
	docker push $(JETBRAINS_IMAGE)

.PHONY: push-all
push-all: push-base push-vscode ## 推送所有镜像
	@echo "✅ 所有镜像推送完成"

# ========================================
# 多平台构建 (buildx)
# ========================================

.PHONY: buildx-setup
buildx-setup: ## 设置 buildx 多平台构建环境
	@echo "🔧 设置 buildx 构建器..."
	-docker buildx create --name $(BUILDX_BUILDER) --use
	docker buildx inspect --bootstrap
	@echo "✅ buildx 构建器就绪"

.PHONY: buildx-base
buildx-base: buildx-setup ## 多平台构建基础镜像
	@echo "🔨 多平台构建基础镜像: $(BASE_IMAGE)"
	docker buildx build $(DOCKER_BUILD_ARGS) \
		--platform $(PLATFORMS) \
		-t $(BASE_IMAGE) \
		-f base/Dockerfile \
		--push \
		.
	@echo "✅ 基础镜像多平台构建完成"

.PHONY: buildx-vscode
buildx-vscode: buildx-base ## 多平台构建 VSCode 镜像
	@echo "🔨 多平台构建 VSCode 镜像: $(VSCODE_IMAGE)"
	docker buildx build $(DOCKER_BUILD_ARGS) \
		--platform $(PLATFORMS) \
		-t $(VSCODE_IMAGE) \
		-f vscode/Dockerfile \
		--push \
		.
	@echo "✅ VSCode 镜像多平台构建完成"

.PHONY: buildx-all
buildx-all: buildx-base buildx-vscode ## 多平台构建所有镜像
	@echo "✅ 所有镜像多平台构建完成"

# ========================================
# 版本管理
# ========================================

.PHONY: tag
tag: ## 为镜像打标签 (用法: make tag VERSION=1.0.0)
	@if [ "$(VERSION)" = "latest" ]; then \
		echo "❌ 请指定版本号: make tag VERSION=1.0.0"; \
		exit 1; \
	fi
	@echo "🏷️  为镜像打标签: $(VERSION)"
	docker tag $(REGISTRY)/$(PROJECT):base-latest $(REGISTRY)/$(PROJECT):base-$(VERSION)
	docker tag $(REGISTRY)/$(PROJECT):vscode-latest $(REGISTRY)/$(PROJECT):vscode-$(VERSION)
	@echo "✅ 标签创建完成"

# ========================================
# 测试和验证
# ========================================

.PHONY: test-base
test-base: build-base ## 测试基础镜像
	@echo "🧪 测试基础镜像..."
	docker run --rm $(BASE_IMAGE) git --version
	docker run --rm $(BASE_IMAGE) jq --version
	docker run --rm $(BASE_IMAGE) bash -c "ls -la /usr/local/gitspace/scripts/common/"
	@echo "✅ 基础镜像测试通过"

.PHONY: test-vscode
test-vscode: build-vscode ## 测试 VSCode 镜像
	@echo "🧪 测试 VSCode 镜像..."
	docker run --rm $(VSCODE_IMAGE) code-server --version
	docker run --rm $(VSCODE_IMAGE) bash -c "ls -la /usr/local/gitspace/scripts/vscode/"
	@echo "✅ VSCode 镜像测试通过"

.PHONY: test-all
test-all: test-base test-vscode ## 测试所有镜像
	@echo "✅ 所有镜像测试通过"

# ========================================
# 清理
# ========================================

.PHONY: clean
clean: ## 清理本地镜像
	@echo "🧹 清理本地镜像..."
	-docker rmi $(BASE_IMAGE)
	-docker rmi $(VSCODE_IMAGE)
	-docker rmi $(CURSOR_IMAGE)
	-docker rmi $(JETBRAINS_IMAGE)
	@echo "✅ 清理完成"

.PHONY: prune
prune: ## 清理 Docker 构建缓存
	@echo "🧹 清理 Docker 构建缓存..."
	docker builder prune -f
	docker system prune -f
	@echo "✅ 缓存清理完成"

# ========================================
# 开发工具
# ========================================

.PHONY: shell-base
shell-base: build-base ## 进入基础镜像 shell
	docker run --rm -it $(BASE_IMAGE) bash

.PHONY: shell-vscode
shell-vscode: build-vscode ## 进入 VSCode 镜像 shell
	docker run --rm -it $(VSCODE_IMAGE) bash

.PHONY: inspect-base
inspect-base: ## 检查基础镜像信息
	@echo "📋 基础镜像信息:"
	docker inspect $(BASE_IMAGE) | jq '.[0] | {Id, Size, Architecture, Os, Created}'

.PHONY: inspect-vscode
inspect-vscode: ## 检查 VSCode 镜像信息
	@echo "📋 VSCode 镜像信息:"
	docker inspect $(VSCODE_IMAGE) | jq '.[0] | {Id, Size, Architecture, Os, Created}'

# ========================================
# CI/CD 集成
# ========================================

.PHONY: ci-build
ci-build: ## CI 环境下的构建 (不缓存)
	@echo "🤖 CI 环境构建..."
	docker build --no-cache $(DOCKER_BUILD_ARGS) -t $(BASE_IMAGE) -f base/Dockerfile .
	docker build --no-cache $(DOCKER_BUILD_ARGS) -t $(VSCODE_IMAGE) -f vscode/Dockerfile .
	@echo "✅ CI 构建完成"

.PHONY: ci-test
ci-test: ci-build test-all ## CI 环境下的测试
	@echo "✅ CI 测试完成"

# ========================================
# 发布流程
# ========================================

.PHONY: release
release: ## 发布新版本 (用法: make release VERSION=1.0.0)
	@if [ "$(VERSION)" = "latest" ]; then \
		echo "❌ 请指定版本号: make release VERSION=1.0.0"; \
		exit 1; \
	fi
	@echo "🚀 发布版本: $(VERSION)"
	@echo "1️⃣  构建镜像..."
	$(MAKE) buildx-all VERSION=$(VERSION)
	@echo "2️⃣  打标签..."
	$(MAKE) tag VERSION=$(VERSION)
	@echo "3️⃣  推送镜像..."
	docker push $(REGISTRY)/$(PROJECT):base-$(VERSION)
	docker push $(REGISTRY)/$(PROJECT):vscode-$(VERSION)
	@echo "✅ 版本 $(VERSION) 发布完成"

.DEFAULT_GOAL := help
