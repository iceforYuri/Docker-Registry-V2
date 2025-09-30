#!/bin/bash

git add .
git commit -m $*
git push origin stage4


echo "提交完成! 按任意键继续..."
read -n 1 -s