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
mkdir -p "$HOME/.local/share/srv/docker/bind/rootfs"
git clone "https://github.com/dockermgr/bind" "$HOME/.local/share/CasjaysDev/dockermgr/bind"
cp -Rfva "$HOME/.local/share/CasjaysDev/dockermgr/bind/rootfs/." "$HOME/.local/share/srv/docker/bind/rootfs/"
docker run -d \
--restart always \
--privileged \
--name casjaysdevdocker-bind \
--hostname bind \
-e TZ=${TIMEZONE:-America/New_York} \
-v "$HOME/.local/share/srv/docker/casjaysdevdocker-bind/rootfs/data:/data:z" \
-v "$HOME/.local/share/srv/docker/casjaysdevdocker-bind/rootfs/config:/config:z" \
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
      - "$HOME/.local/share/srv/docker/casjaysdevdocker-bind/rootfs/data:/data:z"
      - "$HOME/.local/share/srv/docker/casjaysdevdocker-bind/rootfs/config:/config:z"
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
