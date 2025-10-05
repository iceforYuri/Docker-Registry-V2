#!/bin/bash

git add .
git commit -m $*
git push origin go_邪修 --force


echo "提交完成! 按任意键继续..."
read -n 1 -s