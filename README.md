# Minecraft Bedrock Dedicated Server

## Setup a Linux server

All of my servers run Ubuntu 22.04 LTS. For this project, I am using a physical device to run Docker containers. This is the same host used for the ARK Survival Evolved server.

This goes without saying, but the first thing that needs to be done when using a fresh Ubuntu image is to run `sudo apt update` and `sudo apt upgrade`. Below is the series of steps that I followed to get a Docker container up and running.

## Install Docker

Docker isn't natively installed on Ubuntu. There was some setup I needed to do and packages I needed to install.

### Docker-related packages

I followed this guide to setup docker for my Ubuntu server, https://docs.docker.com/engine/install/ubuntu/. I'm not sure what the first few steps are doing, so I'll just include the apt packages I installed below.

```BASH
$ sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## Preparing server

Below we are setting up our working directory and installing any server code dependencies.

```BASH
$ mkdir /mincraftBedrock && mkdir /mincraftBedrock/serverCode
$ apt update && apt upgrade
$ apt install -y curl wget unzip openssl grep screen
```

Note that the working directory is `/minecraftBedrock`, so when you see `./{}` assume we are in the working directory.

## Downloading server code

Below we are downloading the files and binaries needed to run the server.

```BASH
$ wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb -O libssl1.1.deb
$ sudo dpkg -i libssl1.1.deb
$ rm -f libssl1.1.deb
$ DOWNLOAD_URL=$(curl -H "Accept-Encoding: identity" -H "Accept-Language: en" -s -L -A "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; BEDROCK-UPDATER)" https://minecraft.net/en-us/download/server/bedrock/ |  grep -o 'https://minecraft.azureedge.net/bin-linux/[^"]*')
$ wget $DOWNLOAD_URL -O ./bedrock-server.zip
$ unzip bedrock-server.zip -d .
$ rm bedrock-server.zip
```

## Setting up a Dockerfile

Below we are setting up a Dockerfile, which will be used to automate the Docker image build process. If you are following this process, create a file named "Dockerfile" in your working directory, and paste the line of text provided below.

```Docker
FROM ubuntu:latest

RUN mkdir mincraftBedrock && mkdir mincraftBedrock/serverCode && \
    apt update && apt upgrade && \
    apt install -y curl wget unzip openssl grep screen cron systemctl vim && \
    systemctl enable cron

WORKDIR /minecraftBedrock/serverCode

COPY ./serverCode .
COPY ./scripts/crontab /var/spool/cron/crontabs/root
    
EXPOSE 19132/udp 19133/udp 19132/tcp 19133/tcp
```

Note that I tried making a docker image "from scratch", but running server code didn't seem possible without a file system. If I find a way to just run the binary, I will come back and update this. It would be nice to have it as lite weight as possible.

### Building the Docker image

Below we are using a `docker build` command to build the Dockerfile into an image. Once we have a cached image, we can run `docker run` to create a new container. I used this in a BASH script because it is too annoying to type out.

Note that here we are searching the working directory (".") for a file name "Dockerfile". See previous step if needed.

```BASH
sudo docker build -t minecraft-image .
```

A word on Docker images: An image is an executable package that provides everything needed to run a piece of software. It can include, code, libraries, env vars, and configuration files. Images are built from instructions specified in a Dockerfile, and aren't meant to be changed. Images determine how containers are created/compiled.

### Building the Docker container

Now that we have cached image, let us use `docker run` to create a docker container that will actually run the server. Note that we are outputting stdin and stderr into log files.

```BASH
sudo docker run -d -v "$PWD/serverCode/worlds:/minecraftBedrock/serverCode/worlds" -p 19132:19132/udp -p 19133:19133/udp -p 19132:19132/tcp -p 19133:19133/tcp --name minecraft-container minecraft-image tail -f /dev/null
```

Note that the `tail -f /dev/null` is used so that the container doesn't exit once it created. This will allow the container to run continuously.

A word on Docker containers: A container is a runable instance of an image. It provides an execution environment for any packages, libraries, or configurations specified in an image. A container can be started, stopped, restarted, etc. Each container is isolated from others running on a host.

## Exec docker container

Now that the container is started, we need to run the server binary. I'll include additional steps that I took below, but once you issue the `docker exec` command and have a tty session, then the only thing left to do is `./bedrock_server`. 

### Screen program

There was an interesting program that I learned about, "screen" is a program used to open a run a continuous session with a binary. This session could be opened, closed, paused, etc. This was useful because I could run the server binary in the screen program and not push it to the back ground in any way. Prior to this program, I was having issues pushing the server to the background and issuing `docker exec` to pick up where I left off. screen made running the server very simple.

```BASH
#!/bin/bash

screen -dmS minecraftBedrock
screen -S minecraftBedrock -X stuff "^M"
screen -S minecraftBedrock -X stuff "./bedrock_server^M"
```

Note that when `docker run` is entered, we can assume that there are no existing screen sessions.

## Backing up game files

When running the server binary, you can enter `save {hold|query|resume}` which will save the data of the server to the `./worlds/` directory. Since we're using a docker container, we can mount a folder from the host OS to `./worlds/` so that way game data is saved on the host OS and container. If the docker container fails, or is stopped, then we still have the data on our host OS.

Out of paranoia, you can copy the backup data to a second back up location. This can be done by using the cp command.

## Cron event

Now, let us set up a cron even to run a script that enters the `save` commands in the server. This script will open the screen session we created in the last step and pass in the save commands. 

```BASH
#!/bin/bash

screen -S minecraftBedrock  -X stuff "save hold^M"
sleep 1
screen -S minecraftBedrock  -X stuff "save query^M"
sleep 1
screen -S minecraftBedrock  -X stuff "save resume^M"
```

Additionally, on our **host** machine we will create a crontab event to run the script every 15 minutes.

```cron
*/15 * * * * docker exec minecraft-container /minecraftBedrock/serverCode/screenSave.sh >> /home/jbone/minecraftBedrock/logs/cron.log 2>&1
```

Note that the Docker container instance of Ubuntu is very stripped down, so it is small as possible. It only includes the needed packages, so there are some packages that are missing. I wasn't able to get systemctl or cron events to work on the Docker container. However, I was able to issue the script commands from my host OS.

Also, note that you may need to add the "docker" to your users group, so that way the cron event doesn't need to use "sudo".

## Setting port forward

The `docker run` command we used already maps ports on the host machine to the docker container, so it will forward any traffic received on ports 13132 and 13133 to the Docker container. All that is really needed is setting a port forward on the hosts default gateway.

## Extra Docker info I learned

### Docker commands

0. Simple hello-world: `sudo docker run hello-world`
1. Ubuntu container: `sudo docker pull ubuntu:22.04`
2. List all cached images: `sudo docker images`
3. Remove a image: `sudo docker rmi {image name or id}`
4. List all containers: `sudo docker ps -a`
5. Remve a container: `sudo docker rm {container name or id}`
6. Create a container from an image: `sudo docker run -it --name minecraftContainer0 ubuntu:22.04`
7. Create new image from container: `sudo docker commit minecraftContainer0 minecraft-image0`
8. Open container from new image: `sudo docker run -it --name minecraftContainer1 miinecraft-image0`
9. Start container: `sudo docker start minecraftContainer1`
	- Note that this will just start it in the backgorund, there will be no interactive terminal yet.
10. Interact with running container: `sudo docker exec -it minecraftContainer1 /bin/bash`

Note that the `run` option will look in the local cache for any images that match the specified image. If nothing matches, it will go out to DockerHub and fetch the specified image, the image will now be in the cache.

```BASH
$ sudo docker run hello-world
Unable to find image 'hello-world:latest' locally
latest: Pulling from library/hello-world
c1ec31eb5944: Pull complete
Digest: sha256:ac69084025c660510933cca701f615283cdbb3aa0963188770b54c31c8962493
Status: Downloaded newer image for hello-world:latest

Hello from Docker!
...
$ sudo docker run hello-world

Hello from Docker!
...
```

### Useful options

sudo docker run {...}
- -i, keeps STDIN open even if not attached.
- --name minecraftUbuntu, specifies the name of the container as minecraftUbuntu.
- -p 127.0.0.1:80:8080/tcp, exposes port to host OS.
	- Ensure UFW doesn't block connections to port.
- -t or --tty, allocates a pseudo-TTY, which allows you to interact with the container through a terminal.
- -u {username}, specifies a username to login with.
- -v {$(pwd):$(pwd)}, mount volume within file system // -v ./content:/content
	- --read-only, control whether container can write files.
- -w /path/to/dir, set working directory.
- /bin/bash, the command to run inside the container. In this case, it starts an interactive Bash shell.

## References

- https://pimylifeup.com/ubuntu-minecraft-bedrock-server/