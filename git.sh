#!/bin/bash

git add .
git commit -m $*
git push origin stage2

echo "提交完成! 按任意键继续..."
read -n 1 -s