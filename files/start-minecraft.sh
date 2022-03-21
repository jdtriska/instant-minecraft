#!/bin/bash
sudo service docker restart
docker ps -aq --filter "name=minecraft" | grep -q . && docker stop minecraft && docker rm -fv minecraft
docker run -d \
 -it \
 -e EULA=TRUE \
 -e FORCE_REDOWNLOAD=true \
 -e TYPE=PAPER -e VERSION=1.15.2 -e PAPER_DOWNLOAD_URL=https://papermc.io/api/v2/projects/paper/versions/1.18.2/builds/393/downloads/paper-1.18.2-265.jar \
 -p 25565:25565 \
 --volume ~/minecraft/data:/data \
 --restart=unless-stopped \
 --name minecraft \
 itzg/minecraft-server:latest