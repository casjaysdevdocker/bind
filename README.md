## 👋 Welcome to bind 🚀  

bind README  
  
  
## Install my system scripts  

```shell
 sudo bash -c "$(curl -q -LSsf "https://github.com/systemmgr/installer/raw/main/install.sh")"
 sudo systemmgr --config && sudo systemmgr install scripts  
```
  
## Automatic install/update  
  
```shell
dockermgr update bind
```
  
## Install and run container
  
```shell
dockerHome="/var/lib/srv/$USER/docker/casjaysdevdocker/bind/bind/latest/rootfs"
mkdir -p "/var/lib/srv/$USER/docker/bind/rootfs"
git clone "https://github.com/dockermgr/bind" "$HOME/.local/share/CasjaysDev/dockermgr/bind"
cp -Rfva "$HOME/.local/share/CasjaysDev/dockermgr/bind/rootfs/." "$dockerHome/"
docker run -d \
--restart always \
--privileged \
--name casjaysdevdocker-bind-latest \
--hostname bind \
-e TZ=${TIMEZONE:-America/New_York} \
-v "$dockerHome/data:/data:z" \
-v "$dockerHome/config:/config:z" \
-p 80:80 \
casjaysdevdocker/bind:latest
```
  
## via docker-compose  
  
```yaml
version: "2"
services:
  ProjectName:
    image: casjaysdevdocker/bind
    container_name: casjaysdevdocker-bind
    environment:
      - TZ=America/New_York
      - HOSTNAME=bind
    volumes:
      - "/var/lib/srv/$USER/docker/casjaysdevdocker/bind/bind/latest/rootfs/data:/data:z"
      - "/var/lib/srv/$USER/docker/casjaysdevdocker/bind/bind/latest/rootfs/config:/config:z"
    ports:
      - 80:80
    restart: always
```
  
## Get source files  
  
```shell
dockermgr download src casjaysdevdocker/bind
```
  
OR
  
```shell
git clone "https://github.com/casjaysdevdocker/bind" "$HOME/Projects/github/casjaysdevdocker/bind"
```
  
## Build container  
  
```shell
cd "$HOME/Projects/github/casjaysdevdocker/bind"
buildx 
```
  
## Authors  
  
🤖 casjay: [Github](https://github.com/casjay) 🤖  
⛵ casjaysdevdocker: [Github](https://github.com/casjaysdevdocker) [Docker](https://hub.docker.com/u/casjaysdevdocker) ⛵  
