#!/bin/bash
sudo service docker restart
docker ps -aq --filter "name=minecraft" | grep -q . && docker stop minecraft && docker rm -fv minecraft
docker run -d \
 -e EULA=TRUE \
 -e TYPE=FORGE \
 -e TYPE=PAPER -e VERSION=1.15.2 \
 -p 25565:25565 \
 --volume ~/minecraft/data:/data \
 --restart=unless-stopped \
 --name minecraft \
 itzg/minecraft-server