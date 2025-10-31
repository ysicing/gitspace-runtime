#!/bin/bash
# Gitspace 多镜像构建脚本

set -e

VERSION=${1:-latest}
REGISTRY=${REGISTRY:-gitness}

echo "=========================================="
echo "Building Gitspace Multi-Image Stack"
echo "Version: $VERSION"
echo "Registry: $REGISTRY"
echo "=========================================="

# 切换到镜像目录
cd "$(dirname "$0")"

# 1. 构建基础镜像
echo ""
echo "[1/7] Building base image..."
docker build \
    -t ${REGISTRY}/gitspace:base-${VERSION} \
    -f base/Dockerfile \
    .

echo "✓ Base image built: ${REGISTRY}/gitspace:base-${VERSION}"

# 2. 构建 VSCode 镜像
echo ""
echo "[2/7] Building VSCode image..."
docker build \
    --build-arg BASE_IMAGE=${REGISTRY}/gitspace:base-${VERSION} \
    -t ${REGISTRY}/gitspace:vscode-${VERSION} \
    -f vscode/Dockerfile \
    .

echo "✓ VSCode image built: ${REGISTRY}/gitspace:vscode-${VERSION}"

# 3. 构建 JetBrains 镜像
echo ""
echo "[3/7] Building JetBrains image..."
docker build \
    --build-arg BASE_IMAGE=${REGISTRY}/gitspace:base-${VERSION} \
    -t ${REGISTRY}/gitspace:jetbrains-${VERSION} \
    -f jetbrains/Dockerfile \
    .

echo "✓ JetBrains image built: ${REGISTRY}/gitspace:jetbrains-${VERSION}"

# 4. 构建 Cursor 镜像
echo ""
echo "[4/7] Building Cursor image..."
docker build \
    --build-arg VSCODE_IMAGE=${REGISTRY}/gitspace:vscode-${VERSION} \
    -t ${REGISTRY}/gitspace:cursor-${VERSION} \
    -f cursor/Dockerfile \
    .

echo "✓ Cursor image built: ${REGISTRY}/gitspace:cursor-${VERSION}"

# 5. 创建 latest 标签（指向 vscode）
echo ""
echo "[5/7] Tagging vscode image as latest..."
docker tag ${REGISTRY}/gitspace:vscode-${VERSION} ${REGISTRY}/gitspace:latest

echo "✓ Tagged: ${REGISTRY}/gitspace:latest -> vscode-${VERSION}"

# 6. 显示镜像列表
echo ""
echo "[6/7] Built images:"
echo "=========================================="
docker images | grep "${REGISTRY}/gitspace" | grep "${VERSION}\|latest"

# 7. 显示镜像大小
echo ""
echo "[7/7] Image sizes:"
echo "=========================================="
docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | \
    grep "${REGISTRY}/gitspace" | \
    grep "${VERSION}\|latest"

echo ""
echo "=========================================="
echo "✓ Build completed successfully!"
echo "=========================================="
echo ""
echo "To push images:"
echo "  docker push ${REGISTRY}/gitspace:base-${VERSION}"
echo "  docker push ${REGISTRY}/gitspace:vscode-${VERSION}"
echo "  docker push ${REGISTRY}/gitspace:jetbrains-${VERSION}"
echo "  docker push ${REGISTRY}/gitspace:cursor-${VERSION}"
echo "  docker push ${REGISTRY}/gitspace:latest"
echo ""
echo "To test images:"
echo "  # VSCode"
echo "  kubectl apply -f examples/gitspace-vscode.yaml"
echo ""
echo "  # JetBrains (IntelliJ)"
echo "  kubectl apply -f examples/gitspace-jetbrains.yaml"
echo ""
echo "  # Cursor"
echo "  kubectl apply -f examples/gitspace-cursor.yaml"
echo ""
