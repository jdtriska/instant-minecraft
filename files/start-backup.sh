#!/bin/bash
echo -e "$(crontab -l 2>/dev/null | grep -v minecraft-backup)\n0 0 * * * /usr/bin/flock -n /home/ec2-user/minecraft/scripts/backup.sh.lock -c \"/bin/sh /home/ec2-user/minecraft/scripts/backup.sh\" #minecraft-backup" | crontab -
